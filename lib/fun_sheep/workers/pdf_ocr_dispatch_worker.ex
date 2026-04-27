defmodule FunSheep.Workers.PdfOcrDispatchWorker do
  @moduledoc """
  Entry point for async PDF OCR. Runs once per material:

    1. Download the PDF from storage to local disk
    2. `pdfinfo` → page count
    3. If pages ≤ chunk size: one Vision async op against the whole PDF
       If pages > chunk size: `qpdf` splits into chunks, each chunk is
       uploaded back to storage and submitted as its own Vision op
    4. Stores the operation names in `uploaded_materials.ocr_operations["chunks"]`
    5. Enqueues one `PdfOcrPollerWorker` job per chunk

  Re-entrant: the material's `ocr_operations` is the source of truth. If this
  worker crashed mid-split we detect the existing chunk records and resume
  from the first chunk that has no operation name yet.
  """

  use Oban.Worker, queue: :pdf_ocr, max_attempts: 3

  alias FunSheep.{Content, Courses, Notifications, Storage}
  alias FunSheep.Content.UploadedMaterial
  alias FunSheep.OCR.{GoogleVision, PdfSplitter}
  alias FunSheep.Storage.GCS

  require Logger

  # Pages per async chunk. Kept below Vision's 2000-page per-file limit by
  # a wide margin so each long-running operation finishes in a few minutes,
  # which tolerates Cloud Run worker restarts without losing much progress.
  @chunk_pages 200

  # Vision writes one JSON output file per `batchSize` pages within a chunk.
  # 20 means a 200-page chunk yields ~10 output files — small enough to list
  # and parse cheaply, big enough to keep GCS ops count reasonable.
  @vision_batch_size 20

  @impl Oban.Worker
  def perform(
        %Oban.Job{args: %{"material_id" => material_id}, attempt: attempt, max_attempts: max} =
          _job
      ) do
    material = Content.get_uploaded_material!(material_id)

    result =
      cond do
        material.ocr_status == :completed ->
          {:ok, :already_completed}

        already_dispatched?(material) ->
          # Chunks already submitted on a prior attempt. Just re-enqueue pollers
          # in case they got lost (e.g. Oban pruned them) and exit.
          reenqueue_pollers(material)
          {:ok, :already_dispatched}

        true ->
          do_dispatch(material)
      end

    # On final failed attempt, advance the course counter and notify the teacher
    # so the course doesn't hang forever at "Processing uploaded materials…".
    case result do
      {:error, _reason} when attempt >= max ->
        Logger.error(
          "[PDF OCR] Exhausted #{max} attempts for material #{material_id}, advancing course"
        )

        advance_course_on_failure(material)
        :ok

      other ->
        other
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  defp already_dispatched?(%UploadedMaterial{ocr_operations: %{"chunks" => [_ | _]}}), do: true
  defp already_dispatched?(_), do: false

  defp do_dispatch(%UploadedMaterial{} = material) do
    {:ok, _} =
      Content.update_uploaded_material(material, %{ocr_status: :processing, ocr_error: nil})

    with {:ok, local_path, cleanup} <- download_to_tmp(material),
         {:ok, total_pages} <- PdfSplitter.page_count(local_path),
         {:ok, chunks} <- maybe_split(material, local_path, total_pages),
         {:ok, uploaded_chunks} <- upload_chunks(material, chunks),
         {:ok, op_chunks} <- submit_vision_ops(material, uploaded_chunks, total_pages) do
      cleanup.()
      record_and_enqueue(material, op_chunks, total_pages)
      :ok
    else
      {:error, reason} = err ->
        Logger.error("[PDF OCR] dispatch failed material=#{material.id}: #{inspect(reason)}")

        Content.update_uploaded_material(material, %{
          ocr_status: :failed,
          ocr_error: "dispatch failed: #{inspect(reason)}"
        })

        err
    end
  end

  defp download_to_tmp(%UploadedMaterial{file_path: key, id: id}) do
    case Storage.get(key) do
      {:ok, bytes} ->
        tmp_dir = Path.join(System.tmp_dir!(), "funsheep_pdf_#{id}")
        File.mkdir_p!(tmp_dir)
        local_path = Path.join(tmp_dir, "source.pdf")
        File.write!(local_path, bytes)

        cleanup = fn -> File.rm_rf(tmp_dir) end
        {:ok, local_path, cleanup}

      {:error, reason} ->
        {:error, {:storage_get_failed, reason}}
    end
  end

  defp maybe_split(_material, local_path, total_pages) when total_pages <= @chunk_pages do
    # Small PDF — no need to split. Use the original file as the single chunk.
    {:ok, [%{index: 0, start_page: 1, page_count: total_pages, path: local_path, is_whole: true}]}
  end

  defp maybe_split(%UploadedMaterial{id: id}, local_path, _total_pages) do
    out_dir = Path.join(Path.dirname(local_path), "chunks")

    case PdfSplitter.split(local_path, @chunk_pages, out_dir) do
      {:ok, chunks} ->
        {:ok, Enum.map(chunks, &Map.put(&1, :is_whole, false))}

      {:error, reason} ->
        Logger.error("[PDF OCR] split failed material=#{id}: #{inspect(reason)}")
        {:error, {:split_failed, reason}}
    end
  end

  defp upload_chunks(material, chunks) do
    # For chunks that are just the original file (is_whole: true), we reuse
    # the already-uploaded object. Otherwise upload each chunk back to
    # storage at a deterministic path so retries skip re-upload.
    uploaded =
      Enum.map(chunks, fn chunk ->
        if chunk.is_whole do
          Map.put(chunk, :storage_key, material.file_path)
        else
          key = chunk_storage_key(material, chunk.index)

          case Storage.object_info(key) do
            {:ok, _} ->
              Map.put(chunk, :storage_key, key)

            {:error, :not_found} ->
              bytes = File.read!(chunk.path)

              case Storage.put(key, bytes, content_type: "application/pdf") do
                {:ok, _} ->
                  # Delete the local chunk immediately after upload to keep
                  # peak /tmp usage bounded to ~1x the PDF size even for
                  # many-chunk splits.
                  File.rm(chunk.path)
                  Map.put(chunk, :storage_key, key)

                {:error, reason} ->
                  throw({:upload_failed, chunk.index, reason})
              end

            {:error, reason} ->
              throw({:storage_check_failed, chunk.index, reason})
          end
        end
      end)

    {:ok, uploaded}
  catch
    {:upload_failed, idx, reason} -> {:error, {:chunk_upload_failed, idx, reason}}
    {:storage_check_failed, idx, reason} -> {:error, {:chunk_check_failed, idx, reason}}
  end

  defp submit_vision_ops(material, chunks, _total_pages) do
    Enum.reduce_while(chunks, {:ok, []}, fn chunk, {:ok, acc} ->
      gcs_uri = storage_gcs_uri(chunk.storage_key)
      output_prefix = vision_output_prefix(material, chunk.index)

      case GoogleVision.start_pdf_async(gcs_uri,
             output_prefix: output_prefix,
             batch_size: @vision_batch_size
           ) do
        {:ok, op_name} ->
          entry = %{
            "name" => op_name,
            "start_page" => chunk.start_page,
            "page_count" => chunk.page_count,
            "output_prefix" => output_prefix,
            "storage_key" => chunk.storage_key,
            "status" => "running",
            "error" => nil,
            "index" => chunk.index
          }

          {:cont, {:ok, [entry | acc]}}

        {:error, reason} ->
          {:halt, {:error, {:vision_submit_failed, chunk.index, reason}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      other -> other
    end
  end

  defp record_and_enqueue(material, chunk_entries, total_pages) do
    {:ok, _} =
      Content.update_uploaded_material(material, %{
        ocr_operations: %{"chunks" => chunk_entries},
        ocr_pages_expected: total_pages,
        ocr_pages_total: total_pages,
        ocr_started_at: DateTime.utc_now() |> DateTime.truncate(:second),
        ocr_status: :processing
      })

    for entry <- chunk_entries do
      %{material_id: material.id, chunk_index: entry["index"]}
      |> FunSheep.Workers.PdfOcrPollerWorker.new(schedule_in: 15)
      |> Oban.insert()
    end
  end

  defp reenqueue_pollers(%UploadedMaterial{id: material_id, ocr_operations: %{"chunks" => chunks}}) do
    for %{"index" => index, "status" => status} <- chunks, status == "running" do
      %{material_id: material_id, chunk_index: index}
      |> FunSheep.Workers.PdfOcrPollerWorker.new()
      |> Oban.insert()
    end
  end

  defp chunk_storage_key(%UploadedMaterial{file_path: file_path}, index) do
    # Deterministic path so a resumed dispatch run finds the same chunks.
    base = Path.rootname(file_path)
    "#{base}.chunks/c#{index}.pdf"
  end

  defp vision_output_prefix(%UploadedMaterial{id: id}, chunk_index) do
    # Vision writes JSONs under this `gs://` prefix. Must end with `/`.
    "gs://#{storage_bucket()}/ocr-output/#{id}/c#{chunk_index}/"
  end

  defp storage_gcs_uri(key) do
    case Application.get_env(:fun_sheep, :storage_backend) do
      FunSheep.Storage.GCS -> GCS.gcs_uri(key)
      # Local mode (tests/dev): use a gs:// style URI pointing at the
      # local key. Vision is mocked in this mode so the URI is informational.
      _ -> "gs://local/#{key}"
    end
  end

  defp storage_bucket do
    case Application.get_env(:fun_sheep, :storage_backend) do
      FunSheep.Storage.GCS -> GCS.bucket_name()
      _ -> "local"
    end
  end

  # Called when the dispatch worker exhausts all retries. Increments the
  # course OCR counter so the course can still advance (rather than hanging
  # at "Processing uploaded materials…" forever), and notifies the teacher.
  defp advance_course_on_failure(material) do
    course_id = material.course_id
    {new_count, total} = Courses.increment_ocr_completed(course_id)

    Phoenix.PubSub.broadcast(
      FunSheep.PubSub,
      "course:#{course_id}",
      {:processing_update, %{ocr_completed: new_count, ocr_total: total}}
    )

    if new_count >= total do
      course = Courses.get_course!(course_id)
      failed_count = Courses.count_failed_materials(course_id)

      if failed_count >= total do
        # All materials failed — mark course as failed and notify teacher
        Courses.update_course(course, %{
          processing_status: "failed",
          processing_step:
            "OCR failed for all #{total} uploaded files. Please check your files and reprocess."
        })

        notify_teacher(course, :all_failed)
      else
        # Some succeeded — advance to extraction if discovery is also done
        notify_teacher(course, :some_failed)
        metadata = course.metadata || %{}

        if metadata["discovery_complete"] == true do
          Courses.advance_to_extraction(course_id)
        end
      end
    end
  end

  defp notify_teacher(course, reason) do
    with user_role_id when not is_nil(user_role_id) <- course.created_by_id do
      # Deduplicate: skip if an unread notification for this course failure
      # already exists. Each reprocess attempt would otherwise flood the bell.
      already_notified =
        Notifications.unread_exists?(user_role_id,
          type: :course_processing_failed,
          course_id: course.id
        )

      unless already_notified do
        {title, body} =
          case reason do
            :all_failed ->
              {"Course setup failed",
               "We couldn't process the uploaded files for \"#{course.name}\". Please check your files and try reprocessing."}

            :some_failed ->
              failed_count = Courses.count_failed_materials(course.id)
              total = Courses.get_course!(course.id).ocr_total_count

              if failed_count >= total do
                {"Course setup failed",
                 "We couldn't process any of the uploaded files for \"#{course.name}\". Please check your files and try reprocessing."}
              else
                {"Some files couldn't be processed",
                 "One or more files for \"#{course.name}\" failed to process. The course will continue with the files that succeeded."}
              end
          end

        Notifications.enqueue(user_role_id,
          type: :course_processing_failed,
          title: title,
          body: body,
          priority: 1,
          channels: [:in_app, :push],
          payload: %{"course_id" => course.id}
        )
      end
    end
  end
end
