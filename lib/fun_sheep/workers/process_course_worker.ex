defmodule FunSheep.Workers.ProcessCourseWorker do
  @moduledoc """
  Oban worker that initiates the course processing pipeline.

  This is the entry point — called after course creation.
  Pipeline order:
    1. Web search — finds textbooks, question banks, practice tests
    2. Discovery — AI-powered chapter/section identification (uses web results)
    3. OCR — processes uploaded materials (parallel, only if materials exist)

  After discovery + OCR complete, question extraction is triggered.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias FunSheep.{Content, Courses}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"course_id" => course_id}}) do
    course = Courses.get_course!(course_id)
    materials = Content.list_materials_by_course(course_id)
    pending = Enum.filter(materials, fn m -> m.ocr_status == :pending end)
    has_materials = pending != []

    Logger.info(
      "[Pipeline] Starting pipeline for course #{course_id} (#{length(pending)} materials)"
    )

    # Track what needs to complete before question extraction
    Courses.update_course(course, %{
      processing_status: "processing",
      processing_step: "Starting course analysis...",
      ocr_total_count: length(pending),
      ocr_completed_count: 0,
      metadata:
        Map.merge(course.metadata || %{}, %{
          "web_search_complete" => false,
          "discovery_complete" => false,
          "ocr_complete" => !has_materials
        })
    })

    # Step 1: Web content discovery runs FIRST
    # After it completes, it triggers CourseDiscoveryWorker with search context
    FunSheep.Workers.WebContentDiscoveryWorker.enqueue(course_id)

    # Parallel: OCR materials (only if there are uploads)
    if has_materials do
      for material <- pending do
        %{material_id: material.id, course_id: course_id}
        |> FunSheep.Workers.OCRMaterialWorker.new()
        |> Oban.insert()
      end
    end

    :ok
  end
end
