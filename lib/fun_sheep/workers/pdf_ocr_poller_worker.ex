defmodule FunSheep.Workers.PdfOcrPollerWorker do
  @moduledoc """
  Polls a single Vision async operation (one chunk of a split PDF).

  Each chunk of a split PDF gets its own poller job — independent retry,
  independent failure. A chunk's page range is known at dispatch time and
  stored in the material's `ocr_operations["chunks"]`, so each poller only
  touches the OcrPage rows for its own slice of the PDF.

  Returns `{:snooze, seconds}` when the Vision LRO is still running. The
  poller backs off from 30s → 300s so idle polling doesn't thrash the
  Vision API. A 1,000-page PDF (5 chunks at 200 pages each) finishes in
  2–5 minutes of wall clock, so most chunks need 2–4 poll attempts.
  """

  use Oban.Worker, queue: :pdf_ocr, max_attempts: 40

  alias FunSheep.{Content, Repo}
  alias FunSheep.Content.{UploadedMaterial, OcrPage}
  alias FunSheep.OCR.GoogleVision
  alias FunSheep.Storage
  alias FunSheep.Storage.GCS

  require Logger

  import Ecto.Query

  @impl Oban.Worker
  def perform(
        %Oban.Job{args: %{"material_id" => material_id, "chunk_index" => chunk_index}} = job
      ) do
    material = Content.get_uploaded_material!(material_id)
    chunks = get_in(material.ocr_operations, ["chunks"]) || []

    case Enum.find(chunks, &(&1["index"] == chunk_index)) do
      nil ->
        # Material was recreated or the chunk disappeared. Nothing to do.
        Logger.warning("[PDF poll] chunk #{chunk_index} not found for material=#{material_id}")
        :ok

      %{"status" => status} when status in ["done", "failed"] ->
        # Another poller already finished this chunk. Idempotent no-op.
        :ok

      %{"name" => name} = chunk ->
        poll_chunk(material, chunk, name, job)
    end
  end

  defp poll_chunk(material, chunk, op_name, job) do
    case GoogleVision.fetch_operation(op_name) do
      {:ok, :running} ->
        {:snooze, poll_delay_seconds(job.attempt)}

      {:ok, :done} ->
        handle_chunk_done(material, chunk)

      {:error, reason} ->
        handle_chunk_failed(material, chunk, reason)
    end
  end

  defp handle_chunk_done(%UploadedMaterial{} = material, chunk) do
    output_prefix = chunk["output_prefix"]
    start_page = chunk["start_page"]
    chunk_index = chunk["index"]

    case read_output_jsons(output_prefix) do
      {:ok, json_docs} ->
        page_results =
          json_docs
          |> Enum.flat_map(&GoogleVision.parse_async_output/1)
          |> Enum.reject(&is_nil/1)

        {inserted, _updated} = upsert_pages(material, start_page, page_results)

        if inserted > 0 do
          _ = Content.increment_ocr_pages_completed(material.id, inserted)
        end

        update_chunk_status(material.id, chunk_index, "done", nil)
        maybe_finalize_material(material.id)
        broadcast_progress(material.id)
        :ok

      {:error, reason} ->
        Logger.error(
          "[PDF poll] output read failed material=#{material.id} chunk=#{chunk_index}: #{inspect(reason)}"
        )

        update_chunk_status(material.id, chunk_index, "failed", inspect(reason))
        maybe_finalize_material(material.id)
        broadcast_progress(material.id)
        :ok
    end
  end

  defp handle_chunk_failed(%UploadedMaterial{} = material, chunk, reason) do
    update_chunk_status(material.id, chunk["index"], "failed", inspect(reason))
    maybe_finalize_material(material.id)
    broadcast_progress(material.id)
    :ok
  end

  defp read_output_jsons(output_prefix) do
    # output_prefix looks like "gs://bucket/ocr-output/<mat>/cN/". The
    # Storage layer works on bucket-relative keys (no gs:// prefix),
    # so strip the bucket portion before listing.
    relative = strip_gs_prefix(output_prefix)

    case list_output_keys(relative) do
      {:ok, keys} ->
        jsons =
          keys
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.reduce_while([], fn key, acc ->
            case Storage.get(key) do
              {:ok, body} -> {:cont, [body | acc]}
              {:error, reason} -> {:halt, {:error, {:get_failed, key, reason}}}
            end
          end)

        case jsons do
          list when is_list(list) -> {:ok, Enum.reverse(list)}
          err -> err
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_output_keys(prefix) do
    case Application.get_env(:fun_sheep, :storage_backend) do
      FunSheep.Storage.GCS -> GCS.list_objects(prefix)
      _ -> list_local_keys(prefix)
    end
  end

  defp list_local_keys(prefix) do
    base = FunSheep.Storage.Local.uploads_dir()
    search = Path.join(base, prefix)

    case File.ls(search) do
      {:ok, entries} ->
        {:ok, Enum.map(entries, &Path.join(prefix, &1))}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp strip_gs_prefix("gs://" <> rest) do
    # "bucket/path/inside/bucket/" → "path/inside/bucket/"
    [_bucket, key] = String.split(rest, "/", parts: 2)
    key
  end

  defp strip_gs_prefix(prefix), do: prefix

  defp upsert_pages(material, start_page, page_results) do
    # Each `page_results` entry has page_number 1..N within the chunk.
    # Offset by `start_page - 1` so material-level page numbers stay global.
    Enum.reduce(page_results, {0, 0}, fn result, {ins, upd} ->
      global_page = start_page + (result.page_number - 1)

      status =
        cond do
          is_binary(result.error) and result.error != "" -> :failed
          result.text in [nil, ""] -> :failed
          true -> :completed
        end

      attrs = %{
        material_id: material.id,
        page_number: global_page,
        extracted_text: result.text,
        bounding_boxes: %{"blocks" => result.blocks},
        images: %{"pages" => result.pages},
        status: status,
        error: result.error
      }

      case Content.upsert_ocr_page(attrs) do
        {:inserted, _page} -> {ins + 1, upd}
        {:updated, _page} -> {ins, upd + 1}
        {:error, _cs} -> {ins, upd}
      end
    end)
  end

  defp update_chunk_status(material_id, chunk_index, new_status, error_msg) do
    Repo.transaction(fn ->
      material =
        Repo.one!(
          from m in UploadedMaterial,
            where: m.id == ^material_id,
            lock: "FOR UPDATE"
        )

      chunks = get_in(material.ocr_operations, ["chunks"]) || []

      updated_chunks =
        Enum.map(chunks, fn chunk ->
          if chunk["index"] == chunk_index do
            chunk
            |> Map.put("status", new_status)
            |> Map.put("error", error_msg)
          else
            chunk
          end
        end)

      {:ok, _} =
        Content.update_uploaded_material(material, %{
          ocr_operations: %{"chunks" => updated_chunks}
        })
    end)
  end

  defp maybe_finalize_material(material_id) do
    material = Content.get_uploaded_material!(material_id)
    chunks = get_in(material.ocr_operations, ["chunks"]) || []
    statuses = Enum.map(chunks, & &1["status"])

    cond do
      Enum.any?(statuses, &(&1 == "running")) ->
        :still_running

      Enum.all?(statuses, &(&1 == "done")) and completed_pages?(material_id) ->
        Content.update_uploaded_material(material, %{ocr_status: :completed, ocr_error: nil})
        post_completion_hooks(material)

      Enum.all?(statuses, &(&1 == "failed")) ->
        Content.update_uploaded_material(material, %{
          ocr_status: :failed,
          ocr_error: aggregate_chunk_errors(chunks)
        })

      true ->
        # Some chunks done, some failed — partial success. Question extraction
        # can still use the pages that succeeded, so advance the course and
        # surface the partial state to the user.
        Content.update_uploaded_material(material, %{
          ocr_status: :partial,
          ocr_error: aggregate_chunk_errors(chunks)
        })

        post_completion_hooks(material)
    end
  end

  defp completed_pages?(material_id) do
    count =
      Repo.one(
        from p in OcrPage,
          where: p.material_id == ^material_id and p.status == :completed,
          select: count()
      )

    count > 0
  end

  defp aggregate_chunk_errors(chunks) do
    chunks
    |> Enum.filter(&(&1["status"] == "failed"))
    |> Enum.map_join("; ", fn c -> "chunk #{c["index"]}: #{c["error"] || "unknown"}" end)
  end

  defp post_completion_hooks(%UploadedMaterial{course_id: nil}), do: :ok

  defp post_completion_hooks(%UploadedMaterial{id: material_id, course_id: course_id}) do
    # Mirror OCRMaterialWorker: once a material completes its OCR, kick off
    # relevance + completeness checks and advance the course's OCR counter.
    FunSheep.Workers.MaterialRelevanceWorker.enqueue(material_id)
    FunSheep.Workers.TextbookCompletenessWorker.enqueue(material_id)
    advance_course(course_id)
  end

  defp advance_course(course_id) do
    {new_count, total} = FunSheep.Courses.increment_ocr_completed(course_id)

    Phoenix.PubSub.broadcast(
      FunSheep.PubSub,
      "course:#{course_id}",
      {:processing_update, %{ocr_completed: new_count, ocr_total: total}}
    )

    if new_count >= total do
      maybe_trigger_extraction(course_id)
    end

    :ok
  end

  defp maybe_trigger_extraction(course_id) do
    course = FunSheep.Courses.get_course!(course_id)
    metadata = course.metadata || %{}

    if metadata["discovery_complete"] == true do
      FunSheep.Courses.update_course(course, %{
        processing_status: "extracting",
        processing_step: "Extracting and generating questions...",
        metadata: Map.merge(metadata, %{"ocr_complete" => true})
      })

      %{course_id: course_id}
      |> FunSheep.Workers.QuestionExtractionWorker.new()
      |> Oban.insert()
    end
  end

  defp broadcast_progress(material_id) do
    material = Content.get_uploaded_material!(material_id)

    Phoenix.PubSub.broadcast(
      FunSheep.PubSub,
      "material:#{material_id}",
      {:ocr_progress,
       %{
         material_id: material_id,
         pages_completed: material.ocr_pages_completed,
         pages_expected: material.ocr_pages_expected,
         ocr_status: material.ocr_status
       }}
    )
  end

  # Polling backoff: starts at 30s, doubles per attempt, capped at 300s.
  # This is what Oban's snooze uses when we're waiting on Vision.
  defp poll_delay_seconds(attempt) do
    base = (30 * :math.pow(2, max(0, attempt - 1))) |> round()
    min(base, 300)
  end
end
