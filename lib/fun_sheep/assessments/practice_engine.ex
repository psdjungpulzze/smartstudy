defmodule FunSheep.Assessments.PracticeEngine do
  @moduledoc """
  Weak-topic practice engine. North Star invariants I-5/I-6/I-7.

  * **I-5** weighted selection — candidates sampled weighted by per-skill
    deficit (1 - correct/total) multiplied by a per-question difficulty
    factor derived from `QuestionStats.difficulty_score` (crowd-sourced
    p-value), so weaker skills *and* items students historically struggle
    with appear more often. Unknown difficulty defaults to neutral (0.5),
    preserving pure-deficit behavior on fresh questions.
  * **I-6** deliberate interleaving — a configurable fraction (default 25%)
    drawn from mastered-ish skills for spaced retention, also sampled with
    harder-bias so retention checks land on items that discriminate.
  * **I-7** mid-session re-rank — on each answer, deficits update and the
    unserved tail is re-composed with the fresh weights.

  Empty session when no weak skills exist — we don't invent practice.
  """

  alias FunSheep.Questions

  @default_limit 20
  @default_interleave_ratio 0.25
  @default_review_floor 0.3

  def start_practice(user_role_id, course_id, opts \\ %{}) do
    opts = merge_opts(opts)
    chapter_ids = opts.chapter_ids || []

    deficits = Questions.skill_deficits(user_role_id, course_id, chapter_ids: chapter_ids)

    weak_pool =
      Questions.list_weak_questions(
        user_role_id,
        course_id,
        opts.chapter_id,
        opts.limit * 3,
        chapter_ids: chapter_ids
      )

    if weak_pool == [] do
      empty_state(user_role_id, course_id, opts, deficits)
    else
      review_pool =
        Questions.list_review_candidates(user_role_id, course_id,
          limit: opts.limit,
          review_floor: opts.review_floor
        )

      questions =
        compose_session(
          weak_pool,
          review_pool,
          opts.limit,
          opts.interleave_ratio,
          deficits,
          MapSet.new()
        )

      # Snapshot "previously wrong" IDs for every question that could enter
      # this session. Used in `summary/1` to compute `improved` as real
      # wrong→right transitions — the teacher's priority fix #6.
      pool_ids = Enum.map(weak_pool ++ review_pool, & &1.id)

      previously_wrong_ids =
        Questions.previously_wrong_question_ids(user_role_id, pool_ids)

      %{
        user_role_id: user_role_id,
        course_id: course_id,
        test_schedule_id: opts.test_schedule_id,
        questions: questions,
        current_index: 0,
        attempts: [],
        status: :in_progress,
        opts: opts,
        skill_deficits: deficits,
        weak_pool: weak_pool,
        review_pool: review_pool,
        served_ids: MapSet.new(),
        previously_wrong_ids: previously_wrong_ids
      }
    end
  end

  def current_question(state) do
    case Enum.at(state.questions, state.current_index) do
      nil -> {:complete, %{state | status: :complete}}
      q -> {:question, q, state}
    end
  end

  def record_answer(state, question_id, answer, is_correct) do
    attempt = %{question_id: question_id, answer: answer, is_correct: is_correct}
    new_attempts = state.attempts ++ [attempt]
    new_served = MapSet.put(state.served_ids, question_id)

    new_deficits =
      update_deficit(
        state.skill_deficits,
        state.weak_pool ++ state.review_pool,
        question_id,
        is_correct
      )

    served_len = state.current_index + 1
    served = Enum.take(state.questions, served_len)
    remaining = max(length(state.questions) - served_len, 0)

    new_tail =
      if remaining > 0 and Map.has_key?(state, :opts) do
        compose_session(
          state.weak_pool,
          state.review_pool,
          remaining,
          state.opts.interleave_ratio,
          new_deficits,
          new_served
        )
      else
        []
      end

    %{
      state
      | attempts: new_attempts,
        current_index: state.current_index + 1,
        questions: served ++ new_tail,
        served_ids: new_served,
        skill_deficits: new_deficits
    }
  end

  def summary(state) do
    total = length(state.attempts)
    correct = Enum.count(state.attempts, & &1.is_correct)
    previously_wrong = Map.get(state, :previously_wrong_ids, MapSet.new())

    # Improved = attempts in this session that were correct AND the student
    # had previously answered the same question wrong (before session start).
    # Replaces the old meaningless `improved: correct`.
    improved =
      Enum.count(state.attempts, fn a ->
        a.is_correct and MapSet.member?(previously_wrong, a.question_id)
      end)

    %{
      total: total,
      correct: correct,
      incorrect: total - correct,
      score: if(total > 0, do: Float.round(correct / total * 100, 1), else: 0.0),
      improved: improved
    }
  end

  defp merge_opts(opts) do
    %{
      limit: Map.get(opts, :limit, @default_limit),
      interleave_ratio: Map.get(opts, :interleave_ratio, @default_interleave_ratio),
      review_floor: Map.get(opts, :review_floor, @default_review_floor),
      chapter_id: Map.get(opts, :chapter_id),
      chapter_ids: Map.get(opts, :chapter_ids),
      test_schedule_id: Map.get(opts, :test_schedule_id)
    }
  end

  defp empty_state(user_role_id, course_id, opts, deficits) do
    %{
      user_role_id: user_role_id,
      course_id: course_id,
      test_schedule_id: opts.test_schedule_id,
      questions: [],
      current_index: 0,
      attempts: [],
      status: :in_progress,
      opts: opts,
      skill_deficits: deficits,
      weak_pool: [],
      review_pool: [],
      served_ids: MapSet.new(),
      previously_wrong_ids: MapSet.new()
    }
  end

  defp compose_session(weak_pool, review_pool, limit, ratio, deficits, exclude) do
    weak_available = Enum.reject(weak_pool, &MapSet.member?(exclude, &1.id))
    review_available = Enum.reject(review_pool, &MapSet.member?(exclude, &1.id))

    review_slots =
      if review_available != [] and limit > 0,
        do: min(round(limit * ratio), length(review_available)),
        else: 0

    weak_slots = min(limit - review_slots, length(weak_available))

    weak_sample = weighted_sample(weak_available, weak_slots, deficits)
    review_sample = weighted_sample(review_available, review_slots, deficits)
    interleave(weak_sample, review_sample, ratio)
  end

  defp weighted_sample(_qs, 0, _d), do: []

  defp weighted_sample(questions, count, deficits) do
    questions
    |> Enum.map(fn q ->
      weight = selection_weight(q, deficits)
      key = :math.log(max(:rand.uniform(), 1.0e-9)) / weight
      {q, key}
    end)
    |> Enum.sort_by(fn {_q, k} -> -k end)
    |> Enum.take(count)
    |> Enum.map(fn {q, _} -> q end)
  end

  # Combines per-skill deficit (I-5 base) with per-question difficulty_score
  # so harder items within the same skill are more likely to be drawn.
  # `difficulty_score` ∈ [0.0, 1.0]; multiplier ∈ [0.5, 1.5]; neutral (0.5)
  # leaves the weight equal to the skill deficit, matching pre-wiring behavior.
  defp selection_weight(question, deficits) do
    deficit = get_in(deficits, [question.section_id, :deficit]) || 0.5
    difficulty = question_difficulty(question)
    max(deficit * (0.5 + difficulty), 0.05)
  end

  defp question_difficulty(%{stats: %{difficulty_score: score}}) when is_float(score), do: score
  defp question_difficulty(_), do: 0.5

  defp interleave(weak, [], _r), do: weak
  defp interleave([], review, _r), do: review

  defp interleave(weak, review, ratio) do
    stride = if ratio > 0, do: max(round(1 / ratio), 2), else: length(weak) + length(review) + 1
    do_interleave(weak, review, stride, [], 0)
  end

  defp do_interleave([], review, _s, acc, _i), do: Enum.reverse(acc) ++ review
  defp do_interleave(weak, [], _s, acc, _i), do: Enum.reverse(acc) ++ weak

  defp do_interleave([w | rest_w] = weak, [r | rest_r] = review, stride, acc, i) do
    if rem(i + 1, stride) == 0 do
      do_interleave(weak, rest_r, stride, [r | acc], i + 1)
    else
      do_interleave(rest_w, review, stride, [w | acc], i + 1)
    end
  end

  defp update_deficit(deficits, pool, question_id, is_correct) do
    case Enum.find(pool, &(&1.id == question_id)) do
      nil ->
        deficits

      %{section_id: nil} ->
        deficits

      %{section_id: section_id} ->
        existing = Map.get(deficits, section_id, %{correct: 0, total: 0, deficit: 0.5})
        new_correct = existing.correct + if(is_correct, do: 1, else: 0)
        new_total = existing.total + 1
        new_deficit = Float.round(1.0 - new_correct / new_total, 4)

        Map.put(deficits, section_id, %{
          correct: new_correct,
          total: new_total,
          deficit: new_deficit
        })
    end
  end
end
