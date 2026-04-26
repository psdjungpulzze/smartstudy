defmodule FunSheep.Workers.DocumentTextWorker do
  @moduledoc """
  Oban worker that extracts text from Office XML documents (DOCX, PPTX, XLSX).

  Invoked by OCRMaterialWorker when format detection identifies a DOCX, PPTX,
  or XLSX file. Downloads the file from storage, splits it into page-sized
  chunks using `TextExtractor.extract_pages/2`, persists each chunk as an
  OcrPage record (mirroring the EPUB pipeline), marks the material completed,
  then advances the course OCR counter so `QuestionExtractionWorker` can
  proceed once all materials are done.

  No fake or placeholder content is ever written — if extraction fails the
  material is marked `:failed` with an honest error message.

  Job args:
    - `"material_id"` — UUID of the UploadedMaterial to process
    - `"course_id"`   — UUID of the parent Course (needed for advance_course)
  """

  use Oban.Worker, queue: :ebook, max_attempts: 3

  alias FunSheep.{Content, Courses, Storage}
  alias FunSheep.Documents.TextExtractor

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"material_id" => material_id, "course_id" => course_id}
      }) do
    material = Content.get_uploaded_material!(material_id)

    if material.ocr_status == :completed do
      Logger.info("[DocText] Material #{material_id} already completed, skipping")
      :ok
    else
      do_extract(material, course_id)
    end
  end

  defp do_extract(material, course_id) do
    {:ok, _} =
      Content.update_uploaded_material(material, %{ocr_status: :processing, ocr_error: nil})

    with {:ok, bytes} <- Storage.get(material.file_path),
         {:ok, pages} <- TextExtractor.extract_pages(bytes, material.file_name || "") do
      Logger.info("[DocText] Extracted #{length(pages)} pages from material #{material.id}")

      # Idempotent on retry
      Content.delete_ocr_pages_for_material(material.id)

      Enum.each(pages, fn {page_number, text} ->
        attrs = %{
          material_id: material.id,
          page_number: page_number,
          extracted_text: text,
          bounding_boxes: %{},
          images: %{},
          status: if(text in ["", nil], do: :failed, else: :completed),
          error: nil
        }

        case Content.upsert_ocr_page(attrs) do
          {_tag, _page} ->
            :ok

          {:error, cs} ->
            Logger.warning(
              "[DocText] Failed to upsert page #{page_number} for material #{material.id}: #{inspect(cs.errors)}"
            )
        end
      end)

      {:ok, _} =
        Content.update_uploaded_material(material, %{ocr_status: :completed, ocr_error: nil})

      advance_course(course_id)
      :ok
    else
      {:error, {:unknown_extension, ext}} ->
        Logger.warning(
          "[DocText] Unsupported extension #{ext} for material #{material.id}"
        )

        Content.update_uploaded_material(material, %{
          ocr_status: :failed,
          ocr_error: "Unsupported format: #{ext}"
        })

        advance_course(course_id)
        :ok

      {:error, {:storage_get_failed, reason}} ->
        Logger.error(
          "[DocText] Storage download failed for material #{material.id}: #{inspect(reason)}"
        )

        Content.update_uploaded_material(material, %{
          ocr_status: :failed,
          ocr_error: "Download failed: #{inspect(reason)}"
        })

        advance_course(course_id)
        {:error, {:storage_get_failed, reason}}

      {:error, reason} ->
        Logger.error(
          "[DocText] Extraction failed for material #{material.id}: #{inspect(reason)}"
        )

        Content.update_uploaded_material(material, %{
          ocr_status: :failed,
          ocr_error: "Extraction failed: #{inspect(reason)}"
        })

        advance_course(course_id)
        {:error, reason}
    end
  end

  # Mirror the exact advance_course logic from OCRMaterialWorker so the
  # progress broadcasts, preliminary extraction threshold, and OCR-complete
  # detection all fire correctly for document materials.
  defp advance_course(course_id) do
    {new_count, total} = Courses.increment_ocr_completed(course_id)

    # Record when OCR first started so the UI can compute an ETA
    if new_count == 1, do: Courses.set_ocr_started_at(course_id)

    # Update processing step text periodically
    if rem(new_count, 50) == 0 or new_count >= total do
      course = Courses.get_course!(course_id)

      Courses.update_course(course, %{
        processing_step: "OCR processing: #{min(new_count, total)}/#{total} files..."
      })
    end

    # Broadcast progress
    Phoenix.PubSub.broadcast(
      FunSheep.PubSub,
      "course:#{course_id}",
      {:processing_update, %{ocr_completed: new_count, ocr_total: total}}
    )

    # Progressive unlock at 20%: fire preliminary extraction so the student can
    # start practising while the remaining 80% is still processing.
    if total > 0 and new_count < total do
      maybe_trigger_preliminary_extraction(course_id, new_count, total)
    end

    # When all OCR is done, mark it and check if extraction can start
    if new_count >= total do
      Logger.info("[DocText] All #{total} materials processed for course #{course_id}")
      mark_ocr_complete(course_id)

      course = Courses.get_course!(course_id)
      enriching = get_in(course.metadata || %{}, ["enriching"]) == true

      unless enriching do
        maybe_trigger_extraction(course_id)
      end
    end

    :ok
  end

  defp maybe_trigger_preliminary_extraction(course_id, new_count, total) do
    threshold_reached = new_count / total >= 0.20

    if threshold_reached do
      course = Courses.get_course!(course_id)
      metadata = course.metadata || %{}
      already_triggered = metadata["preliminary_extracted"] == true

      unless already_triggered do
        completed_ids = Courses.list_completed_material_ids(course_id)

        {:ok, _} =
          Courses.update_course(course, %{
            metadata:
              Map.merge(metadata, %{
                "preliminary_extracted" => true,
                "preliminary_material_ids" => completed_ids
              })
          })

        %{course_id: course_id, phase: "preliminary"}
        |> FunSheep.Workers.QuestionExtractionWorker.new()
        |> Oban.insert()

        Logger.info(
          "[DocText] Enqueued preliminary extraction at #{new_count}/#{total} for course #{course_id}"
        )
      end
    end
  end

  defp mark_ocr_complete(course_id) do
    course = Courses.get_course!(course_id)
    metadata = Map.merge(course.metadata || %{}, %{"ocr_complete" => true})
    Courses.update_course(course, %{metadata: metadata})
  end

  defp maybe_trigger_extraction(course_id) do
    course = Courses.get_course!(course_id)
    metadata = course.metadata || %{}

    textbook_kinds = [:textbook, :supplementary_book]

    has_textbook_ocr =
      FunSheep.Content.list_materials_by_course_and_kind(course_id, textbook_kinds)
      |> Enum.any?(&(&1.ocr_status == :completed))

    if has_textbook_ocr do
      Logger.info("[DocText] Textbook OCR done, triggering EnrichDiscovery for #{course_id}")
      Courses.advance_to_extraction(course_id)
    else
      discovery_done = metadata["discovery_complete"] == true

      if discovery_done do
        Logger.info("[DocText] Both discovery and OCR complete, advancing course #{course_id}")
        Courses.advance_to_extraction(course_id)
      else
        Logger.info("[DocText] Waiting for discovery to complete")
      end
    end
  end
end
