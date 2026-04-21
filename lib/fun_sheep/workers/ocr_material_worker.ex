defmodule FunSheep.Workers.OCRMaterialWorker do
  @moduledoc """
  Oban worker that processes a single uploaded material through OCR.

  After OCR completes, atomically increments the course's ocr_completed_count.
  When all materials in a course are OCR'd, marks OCR as complete and checks
  if discovery is also done to trigger question extraction.
  """

  use Oban.Worker, queue: :ocr, max_attempts: 3

  alias FunSheep.Courses
  alias FunSheep.OCR.Pipeline

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"material_id" => material_id, "course_id" => course_id}}) do
    # Skip if course processing was cancelled
    course = Courses.get_course!(course_id)

    if course.processing_status == "cancelled" do
      :ok
    else
      do_process(material_id, course_id)
    end
  end

  defp do_process(material_id, course_id) do
    case Pipeline.process(material_id) do
      {:ok, _pages} ->
        # Check if this material matches the course subject/topic
        FunSheep.Workers.MaterialRelevanceWorker.enqueue(material_id)

        # Verify textbook completeness — worker no-ops on non-textbook kinds.
        FunSheep.Workers.TextbookCompletenessWorker.enqueue(material_id)

      {:error, reason} ->
        Logger.error("[OCR] Failed material #{material_id}: #{inspect(reason)}")
        :ok
    end

    {new_count, total} = Courses.increment_ocr_completed(course_id)

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

    # When all OCR is done, mark it and check if extraction can start
    if new_count >= total do
      Logger.info("[OCR] All #{total} materials processed for course #{course_id}")
      mark_ocr_complete(course_id)

      # If we're in enrichment mode, EnrichDiscoveryWorker handles the next steps
      course = Courses.get_course!(course_id)
      enriching = get_in(course.metadata || %{}, ["enriching"]) == true

      unless enriching do
        maybe_trigger_extraction(course_id)
      end
    end

    :ok
  end

  defp mark_ocr_complete(course_id) do
    course = Courses.get_course!(course_id)
    metadata = Map.merge(course.metadata || %{}, %{"ocr_complete" => true})
    Courses.update_course(course, %{metadata: metadata})
  end

  defp maybe_trigger_extraction(course_id) do
    course = Courses.get_course!(course_id)
    metadata = course.metadata || %{}

    discovery_done = metadata["discovery_complete"] == true

    if discovery_done do
      Logger.info("[OCR] Both discovery and OCR complete, triggering extraction for #{course_id}")

      Courses.update_course(course, %{
        processing_status: "extracting",
        processing_step: "Extracting and generating questions...",
        metadata: Map.merge(metadata, %{"ocr_complete" => true})
      })

      Phoenix.PubSub.broadcast(
        FunSheep.PubSub,
        "course:#{course_id}",
        {:processing_update,
         %{status: "extracting", step: "Extracting and generating questions..."}}
      )

      %{course_id: course_id}
      |> FunSheep.Workers.QuestionExtractionWorker.new()
      |> Oban.insert()
    else
      Logger.info("[OCR] Waiting for discovery to complete")
    end
  end
end
