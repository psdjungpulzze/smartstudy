defmodule FunSheep.Assessments.PracticeEngine do
  @moduledoc """
  Weak-topic practice engine. Implements North Star invariants:

    * **I-5 Weighted selection** — candidates are sampled weighted by their
      skill's deficit (`1 - correct/total` per section), so a student weak in
      fractions gets mostly fraction drills, not a uniform random mix.
    * **I-6 Deliberate interleaving** — a configurable fraction (default 25%)
      of the session is drawn from mastered skills for spaced retention.
    * **I-7 Mid-session re-rank** — after each answer, skill deficits are
      recomputed and the unserved tail is re-composed with updated weights,
      so a tanking student shifts toward easier/more-foundational skills.

  If no weak skills exist, the session is empty — we don't invent practice.
  """

  alias FunSheep.Questions

  @default_limit 20
  @default_interleave_ratio 0.25
  @default_review_floor 0.3

  @doc """
  Starts a practice session for a user in a course.

  ## Options (all optional)
    * `:chapter_id` — focus on a specific chapter
    * `:limit` — total questions in the session (default 20)
    * `:interleave_ratio` — fraction drawn from mastered skills (default 0.25)
    * `:review_floor` — deficit ceiling for a skill to count as "mastered"
      for interleaving (default 0.3)
  """
  def start_practice(user_role_id, course_id, opts \\ %{}) do
    opts = merge_opts(opts)
    deficits = Questions.skill_deficits(user_role_id, course_id)

    weak_pool =
      Questions.list_weak_questions(
        user_role_id,
        course_id,
        opts.chapter_id,
        opts.limit * 3
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

      %{
        user_role_id: user_role_id,
        course_id: course_id,
        questions: questions,
        current_index: 0,
        attempts: [],
        status: :in_progress,
        opts: opts,
        skill_deficits: deficits,
        weak_pool: weak_pool,
        review_pool: review_pool,
        served_ids: MapSet.new()
      }
    end
  end

  @doc """
  Returns the current question or signals completion.
  """
  def current_question(state) do
    case Enum.at(state.questions, state.current_index) do
      nil -> {:complete, %{state | status: :complete}}
      question -> {:question, question, state}
    end
  end

  @doc """
  Records an answer, recomputes the answered skill's deficit, and re-composes
  the unserved tail of the session with the updated weights (I-7).
  """
  def record_answer(state, question_id, answer_given, is_correct) do
    attempt = %{question_id: question_id, answer: answer_given, is_correct: is_correct}
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

  @doc """
  Returns a summary of the practice session results.
  """
  def summary(state) do
    total = length(state.attempts)
    correct = Enum.count(state.attempts, & &1.is_correct)

    %{
      total: total,
      correct: correct,
      incorrect: total - correct,
      score: if(total > 0, do: Float.round(correct / total * 100, 1), else: 0.0),
      # "improved" preserved for backward compat — counts correct answers in
      # the session (each correct on a previously-wrong question is an
      # improvement).
      improved: correct
    }
  end

  # --- Private ---

  defp merge_opts(opts) do
    %{
      limit: Map.get(opts, :limit, @default_limit),
      interleave_ratio: Map.get(opts, :interleave_ratio, @default_interleave_ratio),
      review_floor: Map.get(opts, :review_floor, @default_review_floor),
      chapter_id: Map.get(opts, :chapter_id)
    }
  end

  defp empty_state(user_role_id, course_id, opts, deficits) do
    %{
      user_role_id: user_role_id,
      course_id: course_id,
      questions: [],
      current_index: 0,
      attempts: [],
      status: :in_progress,
      opts: opts,
      skill_deficits: deficits,
      weak_pool: [],
      review_pool: [],
      served_ids: MapSet.new()
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

    weak_sample = weighted_sample_by_deficit(weak_available, weak_slots, deficits)
    review_sample = Enum.take(Enum.shuffle(review_available), review_slots)

    interleave(weak_sample, review_sample, ratio)
  end

  defp weighted_sample_by_deficit(_questions, 0, _deficits), do: []

  defp weighted_sample_by_deficit(questions, count, deficits) do
    # Efraimidis-Spirakis weighted reservoir sampling: key = log(U) / weight.
    # Higher weight → higher expected key → more likely to be picked when we
    # take the top `count` sorted DESC.
    questions
    |> Enum.map(fn q ->
      deficit = get_in(deficits, [q.section_id, :deficit]) || 0.5
      # Floor prevents 0-deficit skills from being completely excluded.
      weight = max(deficit, 0.05)
      key = :math.log(max(:rand.uniform(), 1.0e-9)) / weight
      {q, key}
    end)
    |> Enum.sort_by(fn {_q, key} -> -key end)
    |> Enum.take(count)
    |> Enum.map(fn {q, _} -> q end)
  end

  defp interleave(weak, [], _ratio), do: weak
  defp interleave([], review, _ratio), do: review

  defp interleave(weak, review, ratio) do
    stride = if ratio > 0, do: max(round(1 / ratio), 2), else: length(weak) + length(review) + 1
    do_interleave(weak, review, stride, [], 0)
  end

  defp do_interleave([], review, _stride, acc, _i), do: Enum.reverse(acc) ++ review
  defp do_interleave(weak, [], _stride, acc, _i), do: Enum.reverse(acc) ++ weak

  defp do_interleave([w | rest_w] = weak, [r | rest_r] = review, stride, acc, i) do
    if rem(i + 1, stride) == 0 do
      do_interleave(weak, rest_r, stride, [r | acc], i + 1)
    else
      do_interleave(rest_w, review, stride, [w | acc], i + 1)
    end
  end

  # Fold a new answer into the in-memory deficit map. We look up the answered
  # question's section from the pools we already have — no DB round-trip.
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
