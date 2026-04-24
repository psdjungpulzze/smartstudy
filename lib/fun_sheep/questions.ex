defmodule FunSheep.Questions do
  @moduledoc """
  The Questions context.

  Central question bank management. Handles question creation,
  tagging, and attempt recording.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo
  alias FunSheep.Questions.{Question, QuestionAttempt, QuestionFigure, QuestionStats}

  ## Questions

  def list_questions do
    Repo.all(Question)
  end

  # Questions that are safe to show students: fully validated. Pending and
  # needs_review are hidden so students never see an unvetted question; failed
  # are hidden for obvious reasons. Admin queries should use the `_all`
  # variants below.
  @student_visible [:passed]

  # North Star invariant I-1: a question enters adaptive flows only when it
  # carries a fine-grained skill tag (section_id set AND classification
  # trusted). `:uncategorized` and `:low_confidence` rows are excluded so
  # diagnostic signals aren't built on thin evidence (invariant I-15).
  @adaptive_classifications [:ai_classified, :admin_reviewed]

  @doc """
  Scopes a query to adaptive-eligible questions — carrying a section tag and
  a trusted classification. See North Star invariants I-1 and I-15.
  """
  def tagged_for_adaptive(query \\ Question) do
    query
    |> where([q], not is_nil(q.section_id))
    |> where([q], q.classification_status in ^@adaptive_classifications)
  end

  @doc """
  Returns classification coverage for a course so backfills can see the real
  gap before running AI.
  """
  def classification_coverage(course_id) do
    base = from(q in Question, where: q.course_id == ^course_id)

    rows =
      from(q in base,
        group_by: q.classification_status,
        select: {q.classification_status, count(q.id)}
      )
      |> Repo.all()
      |> Map.new()

    total = rows |> Map.values() |> Enum.sum()
    tagged = Map.get(rows, :ai_classified, 0) + Map.get(rows, :admin_reviewed, 0)
    low_confidence = Map.get(rows, :low_confidence, 0)
    untagged = Map.get(rows, :uncategorized, 0)

    by_chapter =
      from(q in base,
        join: c in FunSheep.Courses.Chapter,
        on: c.id == q.chapter_id,
        group_by: [c.id, c.name, c.position],
        order_by: c.position,
        select: %{
          chapter_id: c.id,
          chapter_name: c.name,
          total: count(q.id),
          tagged:
            fragment(
              "COUNT(*) FILTER (WHERE ? IN ('ai_classified', 'admin_reviewed'))",
              q.classification_status
            ),
          untagged:
            fragment(
              "COUNT(*) FILTER (WHERE ? = 'uncategorized')",
              q.classification_status
            )
        }
      )
      |> Repo.all()

    %{
      total: total,
      tagged: tagged,
      untagged: untagged,
      low_confidence: low_confidence,
      by_chapter: by_chapter
    }
  end

  def count_questions_by_course(course_id) do
    Question
    |> where([q], q.course_id == ^course_id)
    |> where([q], q.validation_status in ^@student_visible)
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns `%{source_type => count}` of student-visible questions for a
  course. Powers the admin source-health dashboard (Phase 8) and the
  per-course source-mix check in the coverage auditor (Phase 6).

  Rows without a `source_type` (pre-backfill) are grouped under `:unknown`
  so the migration window surfaces visibly — once backfill completes the
  `:unknown` bucket should drop to 0.
  """
  def questions_by_source_type(course_id, opts \\ []) do
    statuses = Keyword.get(opts, :statuses, @student_visible)

    from(q in Question,
      where: q.course_id == ^course_id,
      where: q.validation_status in ^statuses,
      group_by: q.source_type,
      select: {q.source_type, count(q.id)}
    )
    |> Repo.all()
    |> Map.new(fn
      {nil, c} -> {:unknown, c}
      pair -> pair
    end)
  end

  @doc """
  Returns `%{{chapter_id, difficulty} => count}` of student-visible,
  adaptive-eligible questions for a course. Powers the Phase 6 coverage
  auditor (which chapters / difficulties are below the per-tuple target)
  and the coverage heatmap in the admin dashboard (Phase 8).
  """
  def coverage_by_chapter(course_id) do
    from(q in Question,
      where: q.course_id == ^course_id,
      where: q.validation_status in ^@student_visible,
      where: not is_nil(q.section_id),
      where: q.classification_status in ^@adaptive_classifications,
      where: not is_nil(q.chapter_id),
      group_by: [q.chapter_id, q.difficulty],
      select: {q.chapter_id, q.difficulty, count(q.id)}
    )
    |> Repo.all()
    |> Map.new(fn {chapter_id, difficulty, count} -> {{chapter_id, difficulty}, count} end)
  end

  @doc """
  Counts unattempted, adaptive-eligible questions for a specific student
  in a (course, chapter, difficulty) tuple. Used by Phase 6's within-session
  demand-driven generation: when the supply for a tuple drops below a
  threshold, enqueue more AI generation targeting that difficulty.

  "Unattempted" = no row in `question_attempts` for this `(user_role_id,
  question_id)` pair. Questions the student has answered — right or wrong —
  are excluded so this reflects the true "how many fresh hard questions
  can we still show them" metric.
  """
  def unattempted_supply_for(user_role_id, course_id, chapter_id, difficulty) do
    from(q in Question,
      left_join:
        qa in subquery(
          from(a in QuestionAttempt,
            where: a.user_role_id == ^user_role_id,
            distinct: a.question_id,
            select: %{question_id: a.question_id}
          )
        ),
      on: qa.question_id == q.id,
      where: q.course_id == ^course_id,
      where: q.chapter_id == ^chapter_id,
      where: q.difficulty == ^difficulty,
      where: q.validation_status in ^@student_visible,
      where: not is_nil(q.section_id),
      where: q.classification_status in ^@adaptive_classifications,
      where: is_nil(qa.question_id),
      select: count(q.id)
    )
    |> Repo.one()
  end

  @doc """
  Counts ALL questions regardless of validation state. For progress UI during
  the generate→validate pipeline.
  """
  def count_all_questions_by_course(course_id) do
    Question
    |> where([q], q.course_id == ^course_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Re-enqueues a validation job for every question still in `:pending` for
  the given course. Intended as a manual recovery step after upstream LLM
  outages cause Oban to exhaust retries and drop the original jobs —
  otherwise those questions remain `:pending` forever and the course
  never finalizes.

  Returns `{:ok, enqueued_count}`. Batches in chunks of 10 to match the
  validator's preferred batch size.

  Typical usage from a remote iex on the worker host:

      iex> FunSheep.Questions.requeue_pending_validations("<course_id>")
      {:ok, 2449}
  """
  @spec requeue_pending_validations(String.t()) :: {:ok, non_neg_integer()}
  def requeue_pending_validations(course_id) when is_binary(course_id) do
    ids =
      from(q in Question,
        where: q.course_id == ^course_id and q.validation_status == :pending,
        select: q.id
      )
      |> Repo.all()

    ids
    |> Enum.chunk_every(10)
    |> Enum.each(fn batch ->
      FunSheep.Workers.QuestionValidationWorker.enqueue(batch, course_id: course_id)
    end)

    {:ok, length(ids)}
  end

  @doc """
  Returns a map of `%{validation_status => count}` for a course. Powers the
  UI during the validation phase — lets the user see how many questions are
  pending, approved, flagged, or rejected without running the full query on
  the client.
  """
  def count_by_validation_status(course_id) do
    counts =
      from(q in Question,
        where: q.course_id == ^course_id,
        group_by: q.validation_status,
        select: {q.validation_status, count(q.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      pending: Map.get(counts, :pending, 0),
      passed: Map.get(counts, :passed, 0),
      needs_review: Map.get(counts, :needs_review, 0),
      failed: Map.get(counts, :failed, 0)
    }
  end

  @doc """
  Batched count of questions per course_id. Returns `%{course_id => count}`.
  Used by the admin course table to avoid N+1 queries.
  """
  def count_all_by_courses([]), do: %{}

  def count_all_by_courses(course_ids) when is_list(course_ids) do
    from(q in Question,
      where: q.course_id in ^course_ids,
      group_by: q.course_id,
      select: {q.course_id, count(q.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Batched count of `:pending` questions per course_id. Returns
  `%{course_id => pending_count}` — course_ids with zero pending are
  omitted. Powers the admin "Requeue pending validations" action.
  """
  def count_pending_by_course(course_id) do
    from(q in Question,
      where: q.course_id == ^course_id and q.validation_status == :pending,
      select: count(q.id)
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  @spec count_pending_by_courses([String.t()]) :: %{String.t() => non_neg_integer()}
  def count_pending_by_courses([]), do: %{}

  def count_pending_by_courses(course_ids) when is_list(course_ids) do
    from(q in Question,
      where: q.course_id in ^course_ids and q.validation_status == :pending,
      group_by: q.course_id,
      select: {q.course_id, count(q.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  def list_questions_by_course(course_id, filters \\ %{}) do
    Question
    |> where([q], q.course_id == ^course_id)
    |> where([q], q.validation_status in ^@student_visible)
    |> maybe_filter_chapter(filters)
    |> maybe_filter_section(filters)
    |> maybe_filter_difficulty(filters)
    |> maybe_filter_question_type(filters)
    |> order_by([q], desc: q.inserted_at)
    |> preload([:chapter, :section])
    |> Repo.all()
  end

  @doc """
  Lists every question for a course regardless of validation state. Used by
  admin / review dashboards only — never by student-facing LiveViews.
  """
  def list_all_questions_by_course(course_id, filters \\ %{}) do
    Question
    |> where([q], q.course_id == ^course_id)
    |> maybe_filter_chapter(filters)
    |> maybe_filter_section(filters)
    |> maybe_filter_difficulty(filters)
    |> maybe_filter_question_type(filters)
    |> order_by([q], desc: q.inserted_at)
    |> preload([:chapter, :section])
    |> Repo.all()
  end

  @doc """
  Lists questions flagged for manual review. Used by the admin review queue.
  """
  def list_questions_needing_review(course_id) do
    Question
    |> where([q], q.course_id == ^course_id and q.validation_status == :needs_review)
    |> order_by([q], desc: q.inserted_at)
    |> preload([:chapter, :section])
    |> Repo.all()
  end

  @doc """
  Lists every question flagged for review across all courses. For the global
  admin review queue.
  """
  def list_all_questions_needing_review do
    Question
    |> where([q], q.validation_status == :needs_review)
    |> order_by([q], desc: q.inserted_at)
    |> preload([:chapter, :section, :course])
    |> Repo.all()
  end

  @doc """
  Counts questions needing review across all courses.
  """
  def count_questions_needing_review do
    Question
    |> where([q], q.validation_status == :needs_review)
    |> Repo.aggregate(:count)
  end

  @doc """
  Admin override — marks a reviewed question as passed so students can see
  it. Records who approved it in validation_report.
  """
  def admin_approve_question(%Question{} = question, reviewer_id \\ nil) do
    report =
      (question.validation_report || %{})
      |> Map.put("admin_decision", %{
        "action" => "approve",
        "reviewer_id" => reviewer_id,
        "at" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    question
    |> Question.changeset(%{
      validation_status: :passed,
      validation_report: report,
      validated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Admin override — marks a reviewed question as failed so students never
  see it. Records who rejected it in validation_report.
  """
  def admin_reject_question(%Question{} = question, reviewer_id \\ nil) do
    report =
      (question.validation_report || %{})
      |> Map.put("admin_decision", %{
        "action" => "reject",
        "reviewer_id" => reviewer_id,
        "at" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    question
    |> Question.changeset(%{
      validation_status: :failed,
      validation_report: report,
      validated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Admin edit — updates question content/answer/explanation/options and marks
  it passed. Used when the admin fixes the validator's complaints directly.
  """
  def admin_edit_and_approve(%Question{} = question, attrs, reviewer_id \\ nil) do
    report =
      (question.validation_report || %{})
      |> Map.put("admin_decision", %{
        "action" => "edit_and_approve",
        "reviewer_id" => reviewer_id,
        "at" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    merged =
      attrs
      |> Map.new(fn
        {k, v} when is_atom(k) -> {k, v}
        {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      end)
      |> Map.merge(%{
        validation_status: :passed,
        validation_report: report,
        validated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    question
    |> Question.changeset(merged)
    |> Repo.update()
  end

  defp maybe_filter_chapter(query, %{"chapter_id" => chapter_id}) when chapter_id != "" do
    where(query, [q], q.chapter_id == ^chapter_id)
  end

  defp maybe_filter_chapter(query, %{chapter_id: chapter_id}) when not is_nil(chapter_id) do
    where(query, [q], q.chapter_id == ^chapter_id)
  end

  defp maybe_filter_chapter(query, _), do: query

  defp maybe_filter_section(query, %{"section_id" => section_id}) when section_id != "" do
    where(query, [q], q.section_id == ^section_id)
  end

  defp maybe_filter_section(query, %{section_id: section_id}) when not is_nil(section_id) do
    where(query, [q], q.section_id == ^section_id)
  end

  defp maybe_filter_section(query, _), do: query

  defp maybe_filter_difficulty(query, %{"difficulty" => difficulty}) when difficulty != "" do
    where(query, [q], q.difficulty == ^difficulty)
  end

  defp maybe_filter_difficulty(query, %{difficulty: difficulty}) when not is_nil(difficulty) do
    where(query, [q], q.difficulty == ^difficulty)
  end

  defp maybe_filter_difficulty(query, _), do: query

  defp maybe_filter_question_type(query, %{"question_type" => type}) when type != "" do
    where(query, [q], q.question_type == ^type)
  end

  defp maybe_filter_question_type(query, %{question_type: type}) when not is_nil(type) do
    where(query, [q], q.question_type == ^type)
  end

  defp maybe_filter_question_type(query, %{question_types: types})
       when is_list(types) and types != [] do
    # question_type is a native PostgreSQL ENUM. Postgrex cannot implicitly cast
    # text[] to question_type[] in a parameterized ANY(...) comparison, so we
    # must pass atoms — Ecto.Enum handles them via the correct ENUM OID.
    atom_types = Enum.map(types, &to_question_type_atom/1)
    where(query, [q], q.question_type in ^atom_types)
  end

  defp maybe_filter_question_type(query, _), do: query

  defp maybe_filter_question_types_list(query, []), do: query

  defp maybe_filter_question_types_list(query, types) when is_list(types) do
    atom_types = Enum.map(types, &to_question_type_atom/1)
    where(query, [q], q.question_type in ^atom_types)
  end

  defp to_question_type_atom(t) when is_atom(t), do: t
  defp to_question_type_atom(t) when is_binary(t), do: String.to_existing_atom(t)

  def list_questions_by_chapter(chapter_id) do
    from(q in Question,
      where: q.chapter_id == ^chapter_id and q.validation_status in ^@student_visible
    )
    |> Repo.all()
  end

  def get_question!(id), do: Repo.get!(Question, id)

  @doc """
  Non-raising variant. Used by the assessment engine to look up a just-answered
  question without crashing the session if the row was deleted mid-flight.
  """
  def get_question(id), do: Repo.get(Question, id)

  @doc "Gets a question with chapter and stats preloaded (for tutor context)."
  def get_question_with_context!(id) do
    Question
    |> Repo.get!(id)
    |> Repo.preload([:chapter, :stats])
  end

  @doc "Lists a student's attempts for a specific question, ordered chronologically."
  def list_attempts_for_question(user_role_id, question_id) do
    from(qa in QuestionAttempt,
      where: qa.user_role_id == ^user_role_id and qa.question_id == ^question_id,
      order_by: [asc: qa.inserted_at]
    )
    |> Repo.all()
  end

  def create_question(attrs \\ %{}) do
    %Question{}
    |> Question.changeset(attrs)
    |> Repo.insert()
  end

  def update_question(%Question{} = question, attrs) do
    question
    |> Question.changeset(attrs)
    |> Repo.update()
  end

  def delete_question(%Question{} = question) do
    Repo.delete(question)
  end

  def change_question(%Question{} = question, attrs \\ %{}) do
    Question.changeset(question, attrs)
  end

  ## Question Attempts

  def list_question_attempts do
    Repo.all(QuestionAttempt)
  end

  def list_attempts_by_user(user_role_id) do
    from(qa in QuestionAttempt,
      where: qa.user_role_id == ^user_role_id,
      order_by: [desc: qa.inserted_at],
      preload: [:question]
    )
    |> Repo.all()
  end

  def get_question_attempt!(id), do: Repo.get!(QuestionAttempt, id)

  def create_question_attempt(attrs \\ %{}) do
    %QuestionAttempt{}
    |> QuestionAttempt.changeset(attrs)
    |> Repo.insert()
  end

  def update_question_attempt(%QuestionAttempt{} = question_attempt, attrs) do
    question_attempt
    |> QuestionAttempt.changeset(attrs)
    |> Repo.update()
  end

  def delete_question_attempt(%QuestionAttempt{} = question_attempt) do
    Repo.delete(question_attempt)
  end

  def change_question_attempt(%QuestionAttempt{} = question_attempt, attrs \\ %{}) do
    QuestionAttempt.changeset(question_attempt, attrs)
  end

  @doc """
  Returns questions in a chapter where the user has at least one incorrect attempt.
  """
  def list_wrong_questions_for_chapter(user_role_id, chapter_id) do
    from(q in Question,
      join: qa in QuestionAttempt,
      on: qa.question_id == q.id,
      where:
        qa.user_role_id == ^user_role_id and
          q.chapter_id == ^chapter_id and
          q.validation_status in ^@student_visible and
          qa.is_correct == false,
      distinct: q.id,
      select: q
    )
    |> Repo.all()
  end

  ## Practice & Quick Test Queries

  @doc """
  Lists questions the user has gotten wrong, prioritized by most recently wrong
  and never correctly answered. Optionally filters by chapter.

  Questions attempted in the user's most recent `limit` attempts are excluded
  so the user does not see identical cards across back-to-back sessions. If
  the exclusion leaves fewer than `limit` questions, previously-seen questions
  backfill the remainder so the user always receives a full session when any
  weak questions exist.
  """
  def list_weak_questions(user_role_id, course_id, chapter_id \\ nil, limit \\ 20, opts \\ []) do
    recent_ids = recently_attempted_question_ids(user_role_id, limit)
    chapter_ids = Keyword.get(opts, :chapter_ids, [])
    question_types = Keyword.get(opts, :question_types, [])

    primary =
      weak_questions_query(user_role_id, course_id, chapter_id, limit,
        exclude: recent_ids,
        chapter_ids: chapter_ids,
        question_types: question_types
      )
      |> Repo.all()

    if length(primary) >= limit do
      primary
    else
      shortfall = limit - length(primary)
      already_picked = Enum.map(primary, & &1.id)

      backfill =
        weak_questions_query(user_role_id, course_id, chapter_id, shortfall,
          exclude: already_picked,
          chapter_ids: chapter_ids,
          question_types: question_types
        )
        |> Repo.all()

      primary ++ backfill
    end
  end

  defp weak_questions_query(user_role_id, course_id, chapter_id, limit, opts) do
    exclude_ids = Keyword.get(opts, :exclude, [])
    chapter_ids = Keyword.get(opts, :chapter_ids, [])
    question_types = Keyword.get(opts, :question_types, [])

    from(q in Question,
      join: qa in QuestionAttempt,
      on: qa.question_id == q.id,
      left_join:
        cq in subquery(
          from(ca in QuestionAttempt,
            where: ca.user_role_id == ^user_role_id and ca.is_correct == true,
            distinct: ca.question_id,
            select: %{question_id: ca.question_id}
          )
        ),
      on: cq.question_id == q.id,
      where:
        q.course_id == ^course_id and
          q.validation_status in ^@student_visible and
          not is_nil(q.section_id) and
          q.classification_status in ^@adaptive_classifications and
          qa.user_role_id == ^user_role_id and
          qa.is_correct == false,
      group_by: [q.id, cq.question_id],
      order_by: [
        # Prioritize questions never answered correctly (NULL cq means no correct attempt)
        asc: fragment("CASE WHEN ? IS NULL THEN 0 ELSE 1 END", cq.question_id),
        # Then most recently wrong
        desc: max(qa.inserted_at)
      ],
      limit: ^limit,
      preload: [:chapter, :section, :stats]
    )
    |> maybe_filter_chapter_for_practice(chapter_id)
    |> maybe_filter_chapter_ids(chapter_ids)
    |> maybe_exclude_question_ids(exclude_ids)
    |> maybe_filter_question_types_list(question_types)
  end

  defp maybe_filter_chapter_for_practice(query, nil), do: query

  defp maybe_filter_chapter_for_practice(query, chapter_id) do
    where(query, [q], q.chapter_id == ^chapter_id)
  end

  # Scopes practice to the specific chapters in a test schedule. Empty list
  # falls through unfiltered so returning students without a schedule_id
  # query param keep getting the course-wide behavior.
  defp maybe_filter_chapter_ids(query, []), do: query

  defp maybe_filter_chapter_ids(query, chapter_ids) when is_list(chapter_ids) do
    where(query, [q], q.chapter_id in ^chapter_ids)
  end

  @doc """
  Returns the subset of `question_ids` that this user has previously
  answered incorrectly at least once. Used by `PracticeEngine` to compute
  real wrong→right "improved" counts in the summary — without this, the
  summary can't distinguish "just correct" from "learned to get right."
  """
  def previously_wrong_question_ids(_user_role_id, []), do: MapSet.new()

  def previously_wrong_question_ids(user_role_id, question_ids)
      when is_list(question_ids) do
    from(qa in QuestionAttempt,
      where:
        qa.user_role_id == ^user_role_id and
          qa.question_id in ^question_ids and
          qa.is_correct == false,
      distinct: true,
      select: qa.question_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Returns per-skill deficit scores for a user in a course.
  `deficit = 1 - correct/total` in [0.0, 1.0]. Higher = weaker.
  Returns `%{section_id => %{correct, total, deficit}}`.
  """
  def skill_deficits(user_role_id, course_id, opts \\ []) do
    chapter_ids = Keyword.get(opts, :chapter_ids, [])

    base =
      from(q in Question,
        join: qa in QuestionAttempt,
        on: qa.question_id == q.id,
        where:
          qa.user_role_id == ^user_role_id and
            q.course_id == ^course_id and
            not is_nil(q.section_id) and
            q.classification_status in ^@adaptive_classifications,
        group_by: q.section_id,
        select: %{
          section_id: q.section_id,
          correct: fragment("COUNT(*) FILTER (WHERE ?)", qa.is_correct),
          total: count(qa.id)
        }
      )

    base
    |> maybe_filter_chapter_ids(chapter_ids)
    |> Repo.all()
    |> Map.new(fn row ->
      deficit =
        if row.total > 0 do
          Float.round(1.0 - row.correct / row.total, 4)
        else
          0.0
        end

      {row.section_id, Map.put(row, :deficit, deficit)}
    end)
  end

  @doc """
  Questions suitable for interleaved review — pulled from sections where the
  student has demonstrated competence (deficit below `review_floor`, default
  0.3). Recently-attempted excluded. North Star I-6.
  """
  def list_review_candidates(user_role_id, course_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    review_floor = Keyword.get(opts, :review_floor, 0.3)
    exclude_ids = Keyword.get(opts, :exclude, [])
    question_types = Keyword.get(opts, :question_types, [])

    deficits = skill_deficits(user_role_id, course_id)

    mastered_section_ids =
      deficits
      |> Enum.filter(fn {_id, %{deficit: d, total: total}} ->
        total >= 2 and d <= review_floor
      end)
      |> Enum.map(fn {id, _} -> id end)

    if mastered_section_ids == [] do
      []
    else
      # Phase 10: spaced review prioritization. The Ebbinghaus
      # forgetting curve + Cepeda et al. 2008 say a mastered skill
      # decays without revisit — the longer since the student last
      # touched a section, the higher the retention benefit of
      # interleaving one of its questions now. Left-join to the
      # per-section "last attempt at" timestamp and order by that
      # ascending (oldest first) instead of random. Sections without
      # prior attempts bubble up first (they can't be decayed but also
      # haven't been practiced for this student, so review is still
      # valuable).
      last_attempt_by_section =
        from(q in Question,
          join: qa in QuestionAttempt,
          on: qa.question_id == q.id,
          where: qa.user_role_id == ^user_role_id,
          group_by: q.section_id,
          select: %{section_id: q.section_id, last_attempt: max(qa.inserted_at)}
        )

      Question
      |> where([q], q.course_id == ^course_id)
      |> where([q], q.validation_status in ^@student_visible)
      |> tagged_for_adaptive()
      |> where([q], q.section_id in ^mastered_section_ids)
      |> maybe_exclude_question_ids(exclude_ids)
      |> maybe_filter_question_types_list(question_types)
      |> join(:left, [q], la in subquery(last_attempt_by_section),
        on: la.section_id == q.section_id
      )
      |> order_by([q, la],
        asc_nulls_first: la.last_attempt,
        asc: fragment("random()")
      )
      |> limit(^limit)
      |> preload([:chapter, :section, :stats])
      |> Repo.all()
    end
  end

  def list_questions_for_quick_test(user_role_id, course_id \\ nil, limit \\ 20)
  def list_questions_for_quick_test(nil, _course_id, _limit), do: []

  def list_questions_for_quick_test(user_role_id, course_id, limit) do
    recent_ids = recently_attempted_question_ids(user_role_id, limit)

    primary =
      quick_test_query(user_role_id, course_id, limit, exclude: recent_ids)
      |> Repo.all()

    if length(primary) >= limit do
      primary
    else
      shortfall = limit - length(primary)
      already_picked = Enum.map(primary, & &1.id)

      backfill =
        quick_test_query(user_role_id, course_id, shortfall, exclude: already_picked)
        |> Repo.all()

      primary ++ backfill
    end
  end

  defp quick_test_query(user_role_id, course_id, limit, opts) do
    exclude_ids = Keyword.get(opts, :exclude, [])

    from(q in Question,
      left_join: qa in QuestionAttempt,
      on: qa.question_id == q.id and qa.user_role_id == ^user_role_id,
      where:
        q.validation_status in ^@student_visible and
          not is_nil(q.section_id) and
          q.classification_status in ^@adaptive_classifications,
      group_by: q.id,
      order_by: [
        # Wrong answers first (0), then unseen (1), then correct (2)
        asc:
          fragment(
            """
            CASE
              WHEN bool_or(COALESCE(?, false) = false AND ? IS NOT NULL) THEN 0
              WHEN NOT bool_or(? IS NOT NULL) THEN 1
              ELSE 2
            END
            """,
            qa.is_correct,
            qa.id,
            qa.id
          ),
        asc: fragment("random()")
      ],
      limit: ^limit,
      preload: [:chapter]
    )
    |> maybe_filter_course_for_quick_test(course_id)
    |> maybe_exclude_question_ids(exclude_ids)
  end

  defp maybe_filter_course_for_quick_test(query, nil), do: query

  defp maybe_filter_course_for_quick_test(query, course_id) do
    where(query, [q], q.course_id == ^course_id)
  end

  defp maybe_exclude_question_ids(query, []), do: query

  defp maybe_exclude_question_ids(query, ids) do
    where(query, [q], q.id not in ^ids)
  end

  # Returns up to `count` distinct question IDs the user has most recently
  # attempted (any outcome). Used to deprioritize just-seen questions when
  # starting a new practice or quick test session.
  defp recently_attempted_question_ids(nil, _count), do: []

  defp recently_attempted_question_ids(user_role_id, count) do
    from(qa in QuestionAttempt,
      where: qa.user_role_id == ^user_role_id,
      group_by: qa.question_id,
      order_by: [desc: max(qa.inserted_at)],
      limit: ^count,
      select: qa.question_id
    )
    |> Repo.all()
  end

  ## Attempt Tracking / Aggregation

  @doc """
  Lists attempts for a user and course, preloading the question.
  """
  def list_attempts_for_user_and_course(user_role_id, course_id) do
    from(qa in QuestionAttempt,
      join: q in assoc(qa, :question),
      where: qa.user_role_id == ^user_role_id and q.course_id == ^course_id,
      order_by: [desc: qa.inserted_at],
      preload: [:question]
    )
    |> Repo.all()
  end

  @doc """
  Lists attempts for a user and chapter, preloading the question.
  """
  def list_attempts_for_user_and_chapter(user_role_id, chapter_id) do
    from(qa in QuestionAttempt,
      join: q in assoc(qa, :question),
      where: qa.user_role_id == ^user_role_id and q.chapter_id == ^chapter_id,
      order_by: [desc: qa.inserted_at],
      preload: [:question]
    )
    |> Repo.all()
  end

  @doc """
  Counts correct attempts for a user in a specific chapter.
  """
  def count_correct_attempts(user_role_id, chapter_id) do
    from(qa in QuestionAttempt,
      join: q in assoc(qa, :question),
      where:
        qa.user_role_id == ^user_role_id and
          q.chapter_id == ^chapter_id and
          qa.is_correct == true,
      select: count(qa.id)
    )
    |> Repo.one()
  end

  @doc """
  Counts total attempts for a user in a specific chapter.
  """
  def count_total_attempts(user_role_id, chapter_id) do
    from(qa in QuestionAttempt,
      join: q in assoc(qa, :question),
      where: qa.user_role_id == ^user_role_id and q.chapter_id == ^chapter_id,
      select: count(qa.id)
    )
    |> Repo.one()
  end

  @doc """
  Returns all attempts a user has made on questions in the given section,
  chronologically ordered, with the question preloaded so mastery checks
  can read the authored difficulty enum.
  """
  def list_section_attempts(user_role_id, section_id) do
    from(qa in QuestionAttempt,
      join: q in assoc(qa, :question),
      where: qa.user_role_id == ^user_role_id and q.section_id == ^section_id,
      order_by: [asc: qa.inserted_at],
      preload: [question: q]
    )
    |> Repo.all()
  end

  @doc """
  Returns the subset of the given section IDs that have at least one
  student-visible (passed) question. Used by ReadinessCalculator to
  distinguish practicable sections from empty ones.
  """
  def sections_with_questions([]), do: MapSet.new()

  def sections_with_questions(section_ids) when is_list(section_ids) do
    from(q in Question,
      where: q.section_id in ^section_ids and q.validation_status in ^@student_visible,
      select: q.section_id,
      distinct: true
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  For each section, returns the set of difficulty levels that have at least one
  student-visible, adaptive-eligible question.

  Returns `%{section_id => MapSet.t(difficulty_atom)}`. Sections with no
  qualifying questions are absent from the map.

  Used by `ReadinessCalculator` to compute per-section difficulty coverage so
  that a section with only easy questions cannot masquerade as "fully covered"
  for students who need medium or hard content to reach mastery.
  """
  def section_difficulty_counts([]), do: %{}

  def section_difficulty_counts(section_ids) when is_list(section_ids) do
    from(q in Question,
      where:
        q.section_id in ^section_ids and
          q.validation_status in ^@student_visible and
          not is_nil(q.section_id),
      group_by: [q.section_id, q.difficulty],
      select: {q.section_id, q.difficulty}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {section_id, difficulty}, acc ->
      Map.update(acc, section_id, MapSet.new([difficulty]), &MapSet.put(&1, difficulty))
    end)
  end

  @doc """
  Counts questions per `{chapter_id, difficulty}` tuple for a course, filtered
  to student-visible, adaptive-eligible questions. Used by `ScopeReadiness` to
  detect which difficulty buckets are undersupplied within a chapter.

  Returns `%{{chapter_id, difficulty} => count}`.
  """
  def counts_by_chapter_and_difficulty(_course_id, []), do: %{}

  def counts_by_chapter_and_difficulty(course_id, chapter_ids)
      when is_list(chapter_ids) do
    from(q in Question,
      where:
        q.course_id == ^course_id and
          q.chapter_id in ^chapter_ids and
          q.validation_status in ^@student_visible and
          not is_nil(q.section_id) and
          q.classification_status in ^@adaptive_classifications,
      group_by: [q.chapter_id, q.difficulty],
      select: {q.chapter_id, q.difficulty, count(q.id)}
    )
    |> Repo.all()
    |> Map.new(fn {ch_id, diff, cnt} -> {{ch_id, diff}, cnt} end)
  end

  @doc """
  Counts attempts for a user across multiple chapters in a single query.
  """
  def count_attempts_in_chapters(_user_role_id, []), do: 0

  def count_attempts_in_chapters(user_role_id, chapter_ids) when is_list(chapter_ids) do
    from(qa in QuestionAttempt,
      join: q in assoc(qa, :question),
      where: qa.user_role_id == ^user_role_id and q.chapter_id in ^chapter_ids,
      select: count(qa.id)
    )
    |> Repo.one()
  end

  ## Question Stats (Aggregate / Crowd-Sourced Difficulty)

  @doc """
  Updates aggregate stats for a question after an attempt is recorded.
  Creates the stats row if it doesn't exist yet.

  This is the core of crowd-sourced difficulty: every student attempt
  feeds into the difficulty score that drives adaptive testing.
  """
  def update_question_stats(question_id, is_correct, time_taken_seconds \\ nil) do
    case Repo.get_by(QuestionStats, question_id: question_id) do
      nil ->
        %QuestionStats{}
        |> QuestionStats.changeset(%{
          question_id: question_id,
          total_attempts: 1,
          correct_attempts: if(is_correct, do: 1, else: 0),
          difficulty_score: QuestionStats.compute_difficulty(if(is_correct, do: 1, else: 0), 1),
          avg_time_seconds: (time_taken_seconds || 0) / 1.0
        })
        |> Repo.insert()

      stats ->
        new_total = stats.total_attempts + 1
        new_correct = stats.correct_attempts + if(is_correct, do: 1, else: 0)
        new_difficulty = QuestionStats.compute_difficulty(new_correct, new_total)

        new_avg_time =
          if time_taken_seconds do
            # Running average
            (stats.avg_time_seconds * stats.total_attempts + time_taken_seconds) / new_total
          else
            stats.avg_time_seconds
          end

        stats
        |> QuestionStats.changeset(%{
          total_attempts: new_total,
          correct_attempts: new_correct,
          difficulty_score: new_difficulty,
          avg_time_seconds: Float.round(new_avg_time, 1)
        })
        |> Repo.update()
    end
  end

  @doc """
  Creates a question attempt AND updates aggregate stats in one call.
  This ensures stats are always in sync with attempts.
  """
  def record_attempt_with_stats(attrs) do
    case create_question_attempt(attrs) do
      {:ok, attempt} ->
        update_question_stats(
          attempt.question_id,
          attempt.is_correct,
          attempt.time_taken_seconds
        )

        Phoenix.PubSub.broadcast(
          FunSheep.PubSub,
          "student_progress:#{attempt.user_role_id}",
          :readiness_updated
        )

        {:ok, attempt}

      error ->
        error
    end
  end

  @doc """
  Gets stats for a question. Returns nil if no attempts yet.
  """
  def get_question_stats(question_id) do
    Repo.get_by(QuestionStats, question_id: question_id)
  end

  @doc """
  Gets stats for multiple questions at once (batch lookup).
  Returns a map of question_id => %QuestionStats{}.
  """
  def get_bulk_question_stats(question_ids) when is_list(question_ids) do
    from(qs in QuestionStats,
      where: qs.question_id in ^question_ids
    )
    |> Repo.all()
    |> Map.new(&{&1.question_id, &1})
  end

  @doc """
  Returns the crowd-sourced difficulty for a question.
  Falls back to 0.5 (medium) if no stats exist.
  """
  def crowd_difficulty(question_id) do
    case get_question_stats(question_id) do
      nil -> 0.5
      stats -> stats.difficulty_score
    end
  end

  @doc """
  Lists questions for a course with their stats preloaded.
  """
  def list_questions_with_stats(course_id, filters \\ %{}) do
    Question
    |> where([q], q.course_id == ^course_id)
    |> where([q], q.validation_status in ^@student_visible)
    |> tagged_for_adaptive()
    |> maybe_filter_chapter(filters)
    |> maybe_filter_section(filters)
    |> maybe_filter_difficulty(filters)
    |> maybe_filter_question_type(filters)
    |> order_by([q], desc: q.inserted_at)
    |> preload([:chapter, :section, :stats])
    |> Repo.all()
  end

  ## Figure attachments

  @doc """
  Attaches a list of SourceFigure IDs to a question. Ignores invalid IDs
  (they would fail the FK constraint).
  """
  def attach_figures(%Question{} = question, figure_ids) when is_list(figure_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      figure_ids
      |> Enum.with_index()
      |> Enum.map(fn {fid, idx} ->
        %{
          question_id: question.id,
          source_figure_id: fid,
          position: idx,
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} =
      Repo.insert_all(QuestionFigure, entries,
        on_conflict: :nothing,
        conflict_target: [:question_id, :source_figure_id]
      )

    {:ok, count}
  end

  def attach_figures(_question, _), do: {:ok, 0}

  @doc """
  Preloads a question's figures.
  """
  def with_figures(%Question{} = question) do
    Repo.preload(question, :figures)
  end

  def with_figures(questions) when is_list(questions) do
    Repo.preload(questions, :figures)
  end
end
