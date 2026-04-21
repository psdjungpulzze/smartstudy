defmodule FunSheep.Workers.OCRMaterialWorker do
  @moduledoc """
  Oban worker that processes a single uploaded material through OCR.

  After OCR completes, atomically increments the course's ocr_completed_count.
  When all materials in a course are OCR'd, marks OCR as complete and checks
  if discovery is also done to trigger question extraction.
  """

  use Oban.Worker, queue: :ocr, max_attempts: 5

  alias FunSheep.Courses
  alias FunSheep.OCR.Pipeline

  require Logger

  # Short backoff with jitter — transient failures (socket closed, connect
  # errors) typically clear within seconds, so we don't want to leave
  # materials idle for minutes. Caps at 30s. Per-attempt delays: ~5s, 10s,
  # 20s, 30s, 30s across 5 Oban attempts.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    base = :math.pow(2, attempt) |> round()
    jitter = :rand.uniform(3)
    min(base * 2 + jitter, 30)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"material_id" => material_id, "course_id" => course_id}} = job) do
    # Skip if course processing was cancelled
    course = Courses.get_course!(course_id)

    if course.processing_status == "cancelled" do
      :ok
    else
      do_process(material_id, course_id, job)
    end
  end

  defp do_process(material_id, course_id, job) do
    case Pipeline.process(material_id) do
      {:ok, _pages} ->
        # Check if this material matches the course subject/topic
        FunSheep.Workers.MaterialRelevanceWorker.enqueue(material_id)

        # Verify textbook completeness — worker no-ops on non-textbook kinds.
        FunSheep.Workers.TextbookCompletenessWorker.enqueue(material_id)

        advance_course(course_id)
        :ok

      {:error, {:transient, reason}} ->
        Logger.warning("[OCR] Transient failure material #{material_id}: #{inspect(reason)}")

        if job.attempt < job.max_attempts do
          # Snooze the job so Oban puts it back on the queue with our
          # backoff delay. Do NOT advance course counters — the material is
          # still :processing and will reach a terminal state on a later
          # attempt.
          {:snooze, backoff(job)}
        else
          # Exhausted retries on a transient error — mark it terminal now.
          Logger.error("[OCR] Exhausted retries for material #{material_id}: #{inspect(reason)}")

          FunSheep.Content.update_uploaded_material(
            FunSheep.Content.get_uploaded_material!(material_id),
            %{ocr_status: :failed, ocr_error: "Exhausted retries: #{inspect(reason)}"}
          )

          advance_course(course_id)
          :ok
        end

      {:error, {:fatal, reason}} ->
        Logger.error("[OCR] Fatal failure material #{material_id}: #{inspect(reason)}")
        advance_course(course_id)
        :ok
    end
  end

  defp advance_course(course_id) do
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
