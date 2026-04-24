defmodule FunSheep.MemorySpan do
  @moduledoc """
  Context for memory span tracking.

  A memory span measures how long a student retains knowledge before forgetting.
  It is calculated as the median time (in hours) between a correct answer and a
  subsequent incorrect answer on the same question (a "decay event").

  Spans are computed at three granularities:
  - `:question` — per individual question
  - `:chapter`  — median of question spans within a chapter
  - `:course`   — median of chapter spans within a course

  ## Usage

  After a practice session, enqueue `FunSheep.Workers.MemorySpanWorker` with
  the user_role_id and question_ids. The worker calls
  `recalculate_for_questions/2`, which cascades from question → chapter → course.

  Call `list_chapter_spans/2` and `get_course_span/2` to surface data in the UI.
  """

  import Ecto.Query

  alias FunSheep.MemorySpan.{Calculator, Span}
  alias FunSheep.Questions.{Question, QuestionAttempt}
  alias FunSheep.Repo

  # ── Recalculation ──────────────────────────────────────────────────────────

  @doc """
  Recalculates and upserts memory spans for a set of question_ids after a session.

  Cascades: question → chapter → course.

  Returns `:ok`.
  """
  @spec recalculate_for_questions(binary(), [binary()]) :: :ok
  def recalculate_for_questions(user_role_id, question_ids) when is_list(question_ids) do
    # 1. Load questions with their chapter/course associations
    questions =
      from(q in Question,
        where: q.id in ^question_ids,
        select: %{id: q.id, chapter_id: q.chapter_id, course_id: q.course_id}
      )
      |> Repo.all()

    # 2. Load all attempts for these questions for this user, ordered by inserted_at
    attempts =
      from(a in QuestionAttempt,
        where: a.user_role_id == ^user_role_id and a.question_id in ^question_ids,
        order_by: [asc: a.inserted_at],
        select: %{
          question_id: a.question_id,
          is_correct: a.is_correct,
          inserted_at: a.inserted_at
        }
      )
      |> Repo.all()

    attempts_by_question = Enum.group_by(attempts, & &1.question_id)

    # 3. Compute and upsert question-level spans
    question_span_results =
      Enum.map(questions, fn q ->
        q_attempts = Map.get(attempts_by_question, q.id, [])
        result = Calculator.compute_question_span(q_attempts)
        {q, result}
      end)

    for {q, result} <- question_span_results do
      upsert_question_span(user_role_id, q, result)
    end

    # 4. Collect unique chapter_ids (skip nil)
    chapter_ids =
      questions
      |> Enum.map(& &1.chapter_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    # 5. For each chapter: aggregate question spans → compute_topic_span → upsert
    for chapter_id <- chapter_ids do
      chapter_questions = Enum.filter(questions, &(&1.chapter_id == chapter_id))
      course_id = hd(chapter_questions).course_id

      question_spans =
        Enum.map(chapter_questions, fn q ->
          case Enum.find(question_span_results, fn {qr, _} -> qr.id == q.id end) do
            {_, {:ok, hours}} -> hours
            _ -> load_question_span_hours(user_role_id, q.id)
          end
        end)

      result = Calculator.compute_topic_span(question_spans)
      upsert_chapter_span(user_role_id, course_id, chapter_id, result)
    end

    # 6. Collect unique course_ids → aggregate chapter spans → upsert course span
    course_ids =
      questions
      |> Enum.map(& &1.course_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    for course_id <- course_ids do
      chapter_spans = load_all_chapter_span_hours(user_role_id, course_id)
      result = Calculator.compute_topic_span(chapter_spans)
      upsert_course_span(user_role_id, course_id, result)
    end

    :ok
  end

  # ── Queries ────────────────────────────────────────────────────────────────

  @doc """
  Returns chapter-level spans for a student in a course, ordered by
  span_hours ascending (shortest first = most at-risk).

  Chapters with no span data yet are included with span_hours: nil.
  """
  @spec list_chapter_spans(binary(), binary()) :: [Span.t()]
  def list_chapter_spans(user_role_id, course_id) do
    from(s in Span,
      where:
        s.user_role_id == ^user_role_id and
          s.course_id == ^course_id and
          s.granularity == "chapter",
      preload: [:chapter],
      order_by: [asc_nulls_last: s.span_hours]
    )
    |> Repo.all()
  end

  @doc """
  Returns the course-level span for a student, or nil if none exists.
  """
  @spec get_course_span(binary(), binary()) :: Span.t() | nil
  def get_course_span(user_role_id, course_id) do
    from(s in Span,
      where:
        s.user_role_id == ^user_role_id and
          s.course_id == ^course_id and
          s.granularity == "course" and
          is_nil(s.chapter_id) and
          is_nil(s.question_id)
    )
    |> Repo.one()
  end

  # ── Presentation Helpers ───────────────────────────────────────────────────

  @doc """
  Returns a `{emoji_label, description}` tuple for the given span_hours.

  Used for fun, motivational messaging in the UI.
  """
  @spec span_label(integer() | nil) :: {atom() | String.t(), String.t()}
  def span_label(nil),
    do: {:no_data, "Keep practicing to unlock your memory span!"}

  def span_label(hours) when hours < 72,
    do:
      {":zap: Speed runner!",
       "Your brain loves novelty — you move fast but decay fast too. Review every 2–3 days to cement the knowledge."}

  def span_label(hours) when hours < 168,
    do:
      {":runner: Almost there!",
       "A quick review every 5 days will carry you to solid retention. You're close!"}

  def span_label(hours) when hours < 336,
    do:
      {":muscle: Solid retention!",
       "Two weeks between reps and you're still sharp. That's genuinely good memory."}

  def span_label(hours) when hours < 672,
    do:
      {":puzzle: Strong memory!",
       "Monthly touch-ups are all you need. Most students never get here."}

  def span_label(_hours),
    do:
      {":trophy: Elite-level retention!",
       "You've basically made this permanent. A quick review every 2 months is plenty."}

  @doc """
  Returns a color class string ("green", "yellow", "red", "gray") for a span.
  """
  @spec span_color(integer() | nil) :: String.t()
  def span_color(nil), do: "gray"
  def span_color(hours) when hours < 7 * 24, do: "red"
  def span_color(hours) when hours < 21 * 24, do: "yellow"
  def span_color(_hours), do: "green"

  @doc """
  Returns a human-readable string for a span duration.

  Examples: "~3 days", "~2 weeks", "~1 month", "—"
  """
  @spec format_span(integer() | nil) :: String.t()
  def format_span(nil), do: "—"

  def format_span(hours) do
    days = div(hours, 24)

    cond do
      days < 1 -> "< 1 day"
      days < 7 -> "~#{days} #{if days == 1, do: "day", else: "days"}"
      days < 14 -> "~1 week"
      days < 21 -> "~2 weeks"
      days < 35 -> "~#{div(days, 7)} weeks"
      days < 60 -> "~1 month"
      true -> "~#{div(days, 30)} months"
    end
  end

  # ── Private Helpers ────────────────────────────────────────────────────────

  defp upsert_question_span(user_role_id, question, {:ok, span_hours}) do
    existing = load_existing_question_span(user_role_id, question.id)
    trend = compute_trend(existing && existing.span_hours, span_hours)
    previous = existing && existing.span_hours

    decay_count =
      from(a in QuestionAttempt,
        where: a.user_role_id == ^user_role_id and a.question_id == ^question.id,
        select: count()
      )
      |> Repo.one()

    attrs = %{
      user_role_id: user_role_id,
      course_id: question.course_id,
      chapter_id: question.chapter_id,
      question_id: question.id,
      granularity: "question",
      span_hours: span_hours,
      decay_event_count: decay_count || 0,
      trend: trend,
      previous_span_hours: previous,
      calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    do_upsert(attrs, [:user_role_id, :granularity, :question_id], :memory_spans_user_question_idx)
  end

  defp upsert_question_span(_user_role_id, _question, {:insufficient_data, _}), do: :ok

  defp upsert_chapter_span(user_role_id, course_id, chapter_id, {:ok, span_hours}) do
    existing = load_existing_chapter_span(user_role_id, chapter_id)
    trend = compute_trend(existing && existing.span_hours, span_hours)
    previous = existing && existing.span_hours

    attrs = %{
      user_role_id: user_role_id,
      course_id: course_id,
      chapter_id: chapter_id,
      question_id: nil,
      granularity: "chapter",
      span_hours: span_hours,
      decay_event_count: 0,
      trend: trend,
      previous_span_hours: previous,
      calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    do_upsert(attrs, [:user_role_id, :granularity, :chapter_id], :memory_spans_user_chapter_idx)
  end

  defp upsert_chapter_span(_user_role_id, _course_id, _chapter_id, {:insufficient_data, _}),
    do: :ok

  defp upsert_course_span(user_role_id, course_id, {:ok, span_hours}) do
    existing = get_course_span(user_role_id, course_id)
    trend = compute_trend(existing && existing.span_hours, span_hours)
    previous = existing && existing.span_hours

    attrs = %{
      user_role_id: user_role_id,
      course_id: course_id,
      chapter_id: nil,
      question_id: nil,
      granularity: "course",
      span_hours: span_hours,
      decay_event_count: 0,
      trend: trend,
      previous_span_hours: previous,
      calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    do_upsert(
      attrs,
      [:user_role_id, :granularity, :course_id],
      :memory_spans_user_course_idx
    )
  end

  defp upsert_course_span(_user_role_id, _course_id, {:insufficient_data, _}), do: :ok

  defp do_upsert(attrs, _conflict_target_fields, conflict_name) do
    changeset = Span.changeset(%Span{}, attrs)

    Repo.insert(changeset,
      on_conflict:
        {:replace,
         [
           :span_hours,
           :decay_event_count,
           :trend,
           :previous_span_hours,
           :calculated_at,
           :updated_at
         ]},
      conflict_target: {:constraint, conflict_name}
    )
  end

  defp compute_trend(nil, _new), do: "insufficient_data"
  defp compute_trend(_old, nil), do: "insufficient_data"

  defp compute_trend(old, new) do
    cond do
      new > old * 1.2 -> "improving"
      new < old * 0.8 -> "declining"
      true -> "stable"
    end
  end

  defp load_existing_question_span(user_role_id, question_id) do
    from(s in Span,
      where:
        s.user_role_id == ^user_role_id and
          s.question_id == ^question_id and
          s.granularity == "question"
    )
    |> Repo.one()
  end

  defp load_existing_chapter_span(user_role_id, chapter_id) do
    from(s in Span,
      where:
        s.user_role_id == ^user_role_id and
          s.chapter_id == ^chapter_id and
          s.granularity == "chapter"
    )
    |> Repo.one()
  end

  defp load_question_span_hours(user_role_id, question_id) do
    case load_existing_question_span(user_role_id, question_id) do
      %Span{span_hours: h} -> h
      nil -> nil
    end
  end

  defp load_all_chapter_span_hours(user_role_id, course_id) do
    from(s in Span,
      where:
        s.user_role_id == ^user_role_id and
          s.course_id == ^course_id and
          s.granularity == "chapter",
      select: s.span_hours
    )
    |> Repo.all()
  end
end
