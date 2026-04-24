defmodule FunSheep.Assessments.ScopeReadiness do
  @moduledoc """
  Determines whether an assessment's scope can actually serve questions.

  `Engine.start_assessment/1` only surfaces `:no_questions_available` after
  exhausting every topic in scope — by which point the student is already
  on the assessment page. This module answers the same question up-front
  so the UI can route to a correct, actionable state:

    * `:ready`                       — every in-scope chapter has enough
                                        student-visible, adaptive-eligible
                                        questions
    * `{:course_not_ready, stage}`   — course is still processing
                                        (`stage` ∈ pending|processing|
                                        discovering|extracting|generating|
                                        validating)
    * `{:course_failed, status_info}`— course.processing_status == "failed"
                                        (discovery returned no chapters, 0
                                        questions generated, or all rejected
                                        by validation)
    * `{:scope_empty, chapter_ids}`  — course is "ready" but every chapter
                                        in scope has 0 visible questions
    * `{:scope_partial, %{ready:     — some chapters have enough questions
      ready_ids, missing: missing}}`   and some don't; assessment can run
                                        but won't cover the full scope

  A chapter counts as "ready" when it has at least
  `@min_questions_per_chapter` questions that are simultaneously:
    * `validation_status == :passed`
    * `section_id IS NOT NULL`
    * `classification_status IN (:ai_classified, :admin_reviewed)`

  Those are the same filters `Questions.list_questions_with_stats/2` applies,
  so readiness here is a true precheck of what the engine would see at
  runtime (North Star invariants I-1 and I-15).
  """

  import Ecto.Query

  alias FunSheep.{Courses, Questions, Repo}
  alias FunSheep.Assessments.TestSchedule
  alias FunSheep.Questions.Question

  @min_questions_per_chapter 3
  # Minimum questions per chapter per difficulty level before that bucket is
  # considered adequately supplied. Below this, `chapters_missing_difficulty/2`
  # will flag it for targeted generation.
  @min_questions_per_difficulty 3

  @all_difficulties [:easy, :medium, :hard]

  @adaptive_classifications [:ai_classified, :admin_reviewed]
  @student_visible [:passed]

  @type readiness ::
          :ready
          | {:course_not_ready, atom()}
          | {:course_failed, String.t() | nil}
          | {:scope_empty, [binary()]}
          | {:scope_partial, %{ready: [binary()], missing: [binary()]}}

  @doc """
  Minimum visible questions per chapter for that chapter to count as ready.
  """
  @spec min_questions_per_chapter() :: pos_integer()
  def min_questions_per_chapter, do: @min_questions_per_chapter

  @doc """
  Classifies the readiness of a `TestSchedule`'s scope.

  The actual question inventory for the scope is the ground truth: if every
  in-scope chapter has enough visible + adaptive-eligible questions, the
  student can take the assessment *regardless* of `course.processing_status`
  (some legacy courses were created before the status machine existed and
  still serve questions fine). `course.processing_status` only decides how
  we explain the block when the inventory is insufficient.
  """
  @spec check(TestSchedule.t()) :: readiness()
  def check(%TestSchedule{} = schedule) do
    chapter_ids = scope_chapter_ids(schedule)

    case evaluate_scope(schedule.course_id, chapter_ids) do
      :ready ->
        :ready

      # Some chapters have enough questions — let the student start now with
      # what's available. Gating on processing_status here would block every
      # user on the course whenever a new textbook upload triggers re-enrichment,
      # even though the chapters they're being tested on are already fully ready.
      {:scope_partial, _} = partial ->
        partial

      scope_block ->
        course = Courses.get_course!(schedule.course_id)

        case course_stage(course) do
          :ready -> scope_block
          {:failed, reason} -> {:course_failed, reason}
          {:not_ready, stage} -> {:course_not_ready, stage}
        end
    end
  end

  @doc """
  Chapter IDs from the scope that lack enough visible questions. Used by
  `Assessments.create_test_schedule/1` to decide which chapters to enqueue
  upfront generation for. Returns `[]` when the course has no chapters,
  the scope is empty, or every chapter is already ready.
  """
  @spec chapters_needing_generation(TestSchedule.t()) :: [binary()]
  def chapters_needing_generation(%TestSchedule{} = schedule) do
    chapter_ids = scope_chapter_ids(schedule)

    case chapter_ids do
      [] ->
        []

      ids ->
        counts = counts_by_chapter(schedule.course_id, ids)

        Enum.filter(ids, fn id ->
          Map.get(counts, id, 0) < @min_questions_per_chapter
        end)
    end
  end

  @doc """
  Returns `[{chapter_id, difficulty}]` pairs for which the chapter has fewer
  than `@min_questions_per_difficulty` student-visible, adaptive-eligible
  questions at that difficulty level.

  Used by `Assessments.ensure_generation_queued/1` to fire targeted per-difficulty
  generation so every chapter builds adequate supply at all three levels (easy,
  medium, hard) — not just in total.
  """
  @spec chapters_missing_difficulty(binary(), [binary()]) :: [{binary(), atom()}]
  def chapters_missing_difficulty(_course_id, []), do: []

  def chapters_missing_difficulty(course_id, chapter_ids) do
    counts = Questions.counts_by_chapter_and_difficulty(course_id, chapter_ids)

    for ch_id <- chapter_ids, diff <- @all_difficulties do
      {ch_id, diff, Map.get(counts, {ch_id, diff}, 0)}
    end
    |> Enum.filter(fn {_ch, _diff, count} -> count < @min_questions_per_difficulty end)
    |> Enum.map(fn {ch_id, diff, _} -> {ch_id, diff} end)
  end

  @doc """
  Chapter IDs referenced in the test schedule's scope map. Returns `[]` when
  the scope is missing, empty, or shaped unexpectedly — treated by `check/1`
  as "no chapters to serve", which bubbles up as `:scope_empty`.
  """
  @spec scope_chapter_ids(TestSchedule.t()) :: [binary()]
  def scope_chapter_ids(%TestSchedule{scope: scope}) when is_map(scope) do
    scope
    |> Map.get("chapter_ids", [])
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
  end

  def scope_chapter_ids(_), do: []

  @doc """
  `%{chapter_id => visible_question_count}` for a course, restricted to the
  given chapter IDs and to student-visible + adaptive-eligible rows. Missing
  chapters are represented as `0`.
  """
  @spec counts_by_chapter(binary(), [binary()]) :: %{binary() => non_neg_integer()}
  def counts_by_chapter(_course_id, []), do: %{}

  def counts_by_chapter(course_id, chapter_ids) when is_list(chapter_ids) do
    observed =
      from(q in Question,
        where: q.course_id == ^course_id,
        where: q.chapter_id in ^chapter_ids,
        where: q.validation_status in ^@student_visible,
        where: not is_nil(q.section_id),
        where: q.classification_status in ^@adaptive_classifications,
        group_by: q.chapter_id,
        select: {q.chapter_id, count(q.id)}
      )
      |> Repo.all()
      |> Map.new()

    Enum.reduce(chapter_ids, %{}, fn id, acc ->
      Map.put(acc, id, Map.get(observed, id, 0))
    end)
  end

  # --- internal ---

  defp evaluate_scope(_course_id, []), do: {:scope_empty, []}

  defp evaluate_scope(course_id, chapter_ids) do
    counts = counts_by_chapter(course_id, chapter_ids)

    {ready_ids, missing_ids} =
      Enum.split_with(chapter_ids, fn id ->
        Map.get(counts, id, 0) >= @min_questions_per_chapter
      end)

    cond do
      missing_ids == [] -> :ready
      ready_ids == [] -> {:scope_empty, missing_ids}
      true -> {:scope_partial, %{ready: ready_ids, missing: missing_ids}}
    end
  end

  @known_stages ~w(pending processing discovering extracting generating validating)

  # Maps `course.processing_status` (free-form string set across many workers)
  # into three buckets the UI actually needs. Unknown status strings bucket
  # into `:pending` so the UI falls back to "still processing" rather than
  # crashing — `String.to_atom/1` is deliberately avoided (atoms are not
  # garbage collected).
  defp course_stage(%{processing_status: status} = course) do
    case status do
      "ready" ->
        :ready

      "failed" ->
        {:failed, Map.get(course, :processing_step) || Map.get(course, :processing_error)}

      s when s in @known_stages ->
        {:not_ready, String.to_existing_atom(s)}

      _ ->
        {:not_ready, :pending}
    end
  end
end
