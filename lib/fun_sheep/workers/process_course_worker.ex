defmodule FunSheep.Workers.ProcessCourseWorker do
  @moduledoc """
  Oban worker that initiates the course processing pipeline.

  This is the entry point — called after course creation.
  Pipeline order:
    1. Web search — finds textbooks, question banks, practice tests
    2. Discovery — AI-powered chapter/section identification (uses web results)
    3. OCR — processes uploaded materials (parallel, only if materials exist)

  After discovery + OCR complete, question extraction is triggered.

  If the course has `auto_create_tests: true` and a `catalog_test_type`,
  TestSchedule records are seeded from upcoming `known_test_dates` for that
  test type so students see a real test calendar on first visit.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias FunSheep.{Assessments, Content, Courses}

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

    # Auto-create TestSchedules from known_test_dates if enabled
    maybe_create_test_schedules(course)

    :ok
  end

  # Creates TestSchedule records for the course creator from upcoming known_test_dates.
  # Only runs when the course has `auto_create_tests: true` and a catalog_test_type.
  # Each official date gets a system-level TestSchedule with full course scope.
  defp maybe_create_test_schedules(%{auto_create_tests: true, catalog_test_type: test_type, created_by_id: creator_id} = course)
       when is_binary(test_type) and is_binary(creator_id) do
    upcoming = Courses.list_upcoming_known_dates(test_type)

    if upcoming == [] do
      # No dates in DB yet — enqueue a one-off sync first, tests will be seeded after
      Logger.info("[Pipeline] No known_test_dates for #{test_type}, enqueuing TestDateSyncWorker")
      %{"test_type" => test_type}
      |> FunSheep.Workers.TestDateSyncWorker.new()
      |> Oban.insert()
    else
      Enum.each(upcoming, fn known_date ->
        attrs = %{
          name: known_date.test_name,
          test_date: known_date.test_date,
          scope: %{"all_chapters" => true},
          user_role_id: creator_id,
          course_id: course.id,
          schedule_type: :official,
          is_auto_created: true,
          known_test_date_id: known_date.id
        }

        case Assessments.create_test_schedule(attrs) do
          {:ok, schedule} ->
            Logger.info("[Pipeline] Auto-created test schedule #{schedule.id} for #{known_date.test_name}")

          {:error, changeset} ->
            Logger.warning("[Pipeline] Failed to auto-create test schedule: #{inspect(changeset.errors)}")
        end
      end)
    end
  end

  defp maybe_create_test_schedules(_course), do: :ok
end
