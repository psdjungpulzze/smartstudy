defmodule FunSheep.Workers.EnrichCourseWorker do
  @moduledoc """
  Oban worker that enriches an existing course with newly uploaded materials.

  Unlike `ProcessCourseWorker` (initial setup) or `reprocess_course` (wipe & redo),
  this worker:
    1. OCRs only the NEW pending materials
    2. Re-runs chapter/section discovery using OCR text as primary context
       (replaces existing chapters with textbook-accurate ones)
    3. Re-generates questions using the combined OCR + web content

  This is the flow triggered when a user uploads textbook pages to an
  already-processed course.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias FunSheep.{Content, Courses}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"course_id" => course_id}}) do
    course = Courses.get_course!(course_id)

    Logger.info("[Enrich] Starting enrichment for course #{course_id}")

    # Find materials that still need OCR
    all_materials = Content.list_materials_by_course(course_id)
    pending = Enum.filter(all_materials, fn m -> m.ocr_status == :pending end)

    if pending == [] do
      Logger.info("[Enrich] No pending materials to process for course #{course_id}")

      Courses.update_course(course, %{
        processing_status: "ready",
        processing_step: "No new materials to process"
      })

      broadcast(course_id, %{status: "ready", step: "No new materials to process"})
      :ok
    else
      do_enrich(course, pending, all_materials)
    end
  end

  defp do_enrich(course, pending_materials, _all_materials) do
    course_id = course.id
    pending_count = length(pending_materials)

    # Set up processing state
    Courses.update_course(course, %{
      processing_status: "processing",
      processing_step: "Processing #{pending_count} uploaded files...",
      ocr_total_count: pending_count,
      ocr_completed_count: 0,
      metadata:
        Map.merge(course.metadata || %{}, %{
          "enriching" => true,
          "ocr_complete" => false,
          "discovery_complete" => false
        })
    })

    broadcast(course_id, %{
      status: "processing",
      step: "Processing #{pending_count} uploaded files..."
    })

    # Step 1: Enqueue OCR for each pending material
    # When all OCR completes, OCRMaterialWorker will call maybe_trigger_extraction.
    # But we want discovery to re-run with OCR text first, so we override the flow:
    # We'll use a custom completion check in the metadata.
    for material <- pending_materials do
      %{material_id: material.id, course_id: course_id}
      |> FunSheep.Workers.OCRMaterialWorker.new()
      |> Oban.insert()
    end

    # Step 2: Enqueue the re-discovery worker to run AFTER OCR completes.
    # We schedule it with a dependency on OCR completion via the
    # EnrichDiscoveryWorker which polls for OCR completion.
    %{course_id: course_id}
    |> FunSheep.Workers.EnrichDiscoveryWorker.new(schedule_in: 5)
    |> Oban.insert()

    :ok
  end

  defp broadcast(course_id, data) do
    Phoenix.PubSub.broadcast(FunSheep.PubSub, "course:#{course_id}", {:processing_update, data})
  end
end
