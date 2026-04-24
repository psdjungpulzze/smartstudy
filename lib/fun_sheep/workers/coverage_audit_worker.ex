defmodule FunSheep.Workers.CoverageAuditWorker do
  @moduledoc """
  Background auditor that keeps every (course, chapter, difficulty)
  tuple above a target supply of adaptive-eligible questions. When a
  tuple drops below target, enqueues
  `AIQuestionGenerationWorker` with `difficulty: :easy | :medium |
  :hard` so new questions land at the right level.

  The product goal from the FunSheep North Star is "again-and-again
  until 100% ready" — that only works if the bank can keep serving
  fresh questions at each student's current difficulty level. Without
  this worker, `ScopeReadiness.@min_questions_per_chapter = 3` (the
  readiness gate) is the only backstop, and it doesn't consider
  difficulty at all. A student who exhausts the :hard pool for a
  chapter before reaching mastery gets zero fresh hard questions.

  Runs:
    * nightly via `Oban.Plugins.Cron` (catches slow-drain chapters)
    * on-demand when `Assessments.ensure_generation_queued/1` or
      `PracticeEngine` detect a low-supply tuple (faster reaction to
      a single student's exhaustion than waiting for cron)

  Tuning knobs (module attributes):
    * @target_per_tuple = 100 — initial target per the product spec.
      Tuple = (course_id, chapter_id, difficulty).
    * @regen_batch = 20 — how many questions to ask for per enqueue.
      Keeps AI cost bounded and lets the loop spread generation.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [
      period: 600,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing]
    ]

  alias FunSheep.{Courses, Questions}

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
    from(c in FunSheep.Courses.Course,
      where: c.processing_status == "ready",
      select: c.id
    )
    |> FunSheep.Repo.all()
    |> Enum.each(&audit_course/1)
  end

  defp audit_course(course_id) do
    course = Courses.get_course_with_chapters!(course_id)

    if course.chapters == [] do
      :ok
    else
      # Use the Phase 1 Questions helper: returns %{{chapter_id,
      # difficulty} => count} of student-visible + adaptive-eligible
      # questions. Tuples not in the map implicitly have 0.
      actuals = Questions.coverage_by_chapter(course_id)

      gaps =
        for ch <- course.chapters, d <- @difficulties do
          current = Map.get(actuals, {ch.id, d}, 0)
          deficit = @target_per_tuple - current

          {ch, d, current, deficit}
        end
        |> Enum.filter(fn {_ch, _d, _current, deficit} -> deficit > 0 end)

      Enum.each(gaps, fn {ch, d, current, deficit} ->
        # Cap at @regen_batch so a chapter with 100-question deficit
        # doesn't fire 100 generation jobs at once. Subsequent audit
        # runs pick up where this one left off — the system converges
        # over a few nightly cycles.
        batch = min(deficit, @regen_batch)

        Logger.info(
          "[CoverageAudit] course=#{course_id} chapter=#{ch.name} difficulty=#{d}" <>
            " current=#{current} target=#{@target_per_tuple} enqueuing=#{batch}"
        )

        FunSheep.Workers.AIQuestionGenerationWorker.enqueue(course_id,
          chapter_id: ch.id,
          count: batch,
          mode: "from_material",
          difficulty: d
        )
      end)

      :ok
    end
  end
end
