defmodule FunSheep.Workers.CoverageAuditWorker do
  @moduledoc """
  Background auditor that keeps every (course, section, difficulty)
  tuple above a target supply of adaptive-eligible questions. When a
  tuple drops below target, enqueues `AIQuestionGenerationWorker` with
  `section_id` and `difficulty` so new questions are targeted at the
  specific concept that is depleted.

  Auditing at section (concept) granularity is critical: a chapter
  can have 100 questions all covering one section and 0 covering five
  others. Chapter-level counting masks those concept-level gaps.

  The product goal from the FunSheep North Star is "again-and-again
  until 100% ready" — that only works if the bank can keep serving
  fresh questions at each student's current difficulty level for every
  concept they need to master.

  Runs:
    * nightly via `Oban.Plugins.Cron` (catches slow-drain sections)
    * on-demand when `Assessments.ensure_generation_queued/1` or
      `PracticeEngine` detect a low-supply tuple

  Tuning knobs (module attributes):
    * @target_per_tuple = 100 — target per (section_id, difficulty).
    * @regen_batch = 20 — questions per enqueue (cost-bounded).
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [
      period: 600,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing]
    ]

  alias FunSheep.{Content, Courses, Questions}

  import Ecto.Query
  require Logger

  @target_per_tuple 100
  @regen_batch 20
  @difficulties [:easy, :medium, :hard]

  def target_per_tuple, do: @target_per_tuple

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case args["course_id"] do
      nil -> audit_all_courses()
      course_id -> audit_course(course_id)
    end
  end

  @doc """
  Enqueue a coverage audit for a single course. Called by
  `Assessments.ensure_generation_queued/1` and the course-creation
  pipeline so fresh courses start converging toward the target without
  waiting for the nightly cron.
  """
  def enqueue_for_course(course_id) do
    %{course_id: course_id} |> __MODULE__.new() |> Oban.insert()
  end

  defp audit_all_courses do
    # Include both "ready" and "validating" courses. A course stuck in
    # "validating" with 0 pending questions will never self-recover via
    # finalize_after_validation — the audit must be able to reach it so
    # generation can eventually complete and push it back to "ready".
    from(c in FunSheep.Courses.Course,
      where: c.processing_status in ["ready", "validating"],
      select: c.id
    )
    |> FunSheep.Repo.all()
    |> Enum.each(&audit_course/1)
  end

  defp audit_course(course_id) do
    course = Courses.get_course_with_chapters!(course_id)

    all_sections =
      Enum.flat_map(course.chapters, fn ch ->
        Enum.map(ch.sections, fn s -> {ch, s} end)
      end)

    if all_sections == [] do
      :ok
    else
      # Section-level coverage: %{{section_id, difficulty} => count}.
      # A chapter with 50 questions in one section and 0 in five others
      # passes any chapter-level gate — only section-level auditing
      # catches those concept gaps.
      actuals = Questions.coverage_by_section(course_id)

      gaps =
        for {ch, s} <- all_sections, d <- @difficulties do
          current = Map.get(actuals, {s.id, d}, 0)
          deficit = @target_per_tuple - current
          {ch, s, d, current, deficit}
        end
        |> Enum.filter(fn {_ch, _s, _d, _current, deficit} -> deficit > 0 end)

      generation_mode =
        cond do
          course_has_grounding_material?(course_id) -> "from_material"
          course_has_web_context?(course_id) -> "from_web_context"
          true -> "from_curriculum"
        end

      Enum.each(gaps, fn {ch, s, d, current, deficit} ->
        batch = min(deficit, @regen_batch)

        Logger.info(
          "[CoverageAudit] course=#{course_id} chapter=#{ch.name}" <>
            " section=\"#{s.name}\" difficulty=#{d}" <>
            " current=#{current} target=#{@target_per_tuple} enqueuing=#{batch} mode=#{generation_mode}"
        )

        FunSheep.Workers.AIQuestionGenerationWorker.enqueue(course_id,
          chapter_id: ch.id,
          section_id: s.id,
          section_name: s.name,
          count: batch,
          mode: generation_mode,
          difficulty: d
        )
      end)

      :ok
    end
  end

  defp course_has_grounding_material?(course_id) do
    Content.list_materials_by_course(course_id)
    |> Enum.any?(fn m ->
      m.ocr_status == :completed and
        FunSheep.Workers.MaterialClassificationWorker.route(m) in [:ground, :extract_and_ground]
    end)
  end

  defp course_has_web_context?(course_id) do
    Content.list_sources_with_scraped_text(course_id) != []
  end
end
