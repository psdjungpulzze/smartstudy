defmodule FunSheep.Assessments.Engine do
  @moduledoc """
  Adaptive assessment engine.

  Layered model (see `docs/PRODUCT_NORTH_STAR.md`):

    * **Topic = chapter.** Topics iterate in order; we advance when mastered
      or exhausted.
    * **Skill = section.** Every adaptive-eligible question carries
      `section_id`; diagnostic decisions are made per-skill.

  Invariants:

    * **I-2 Confirm on wrong** — a wrong answer sets `pending: :confirm` on
      the skill. The next question MUST come from the same section at or
      below the current difficulty. A second wrong -> `:weak`; correct ->
      `:probing`.
    * **I-3 Depth probe on correct-at-target** — with >=2 attempts and the
      latest at medium+, a correct answer triggers one harder probe on the
      same section. Probe failure reverts to `:probing` (NOT `:weak`).
    * **I-4** `:weak` is only written via a confirmed-wrong path.
    * **I-15** Skills with <2 attempts stay `:insufficient_data`.
  """

  alias FunSheep.{Questions, Courses}
  alias FunSheep.Workers.AIQuestionGenerationWorker

  @min_questions_per_topic 3
  @mastery_threshold 0.7
  @max_attempts_per_topic 6

  @difficulty_step 0.15
  @difficulty_tolerance 0.25
  @depth_probe_gap 0.1

  def start_assessment(test_schedule) do
    topics = extract_topics(test_schedule)

    %{
      schedule_id: test_schedule.id,
      course_id: test_schedule.course_id,
      scope: test_schedule.scope,
      current_topic_index: 0,
      topics: topics,
      target_difficulty: 0.5,
      current_difficulty: :medium,
      topic_attempts: %{},
      skill_states: %{},
      active_skill_id: nil,
      status: :in_progress
    }
  end

  def next_question(state) do
    case select_pending_question(state) do
      {:ok, question} -> {:question, question, state}
      :fallback -> next_topic_question(clear_pending(state))
    end
  end

  defp clear_pending(%{active_skill_id: nil} = state), do: state

  defp clear_pending(%{active_skill_id: section_id} = state) do
    case Map.get(state.skill_states, section_id) do
      nil ->
        %{state | active_skill_id: nil}

      skill ->
        cleared = Map.put(skill, :pending, nil)

        %{
          state
          | skill_states: Map.put(state.skill_states, section_id, cleared),
            active_skill_id: nil
        }
    end
  end

  defp next_topic_question(state) do
    topic = Enum.at(state.topics, state.current_topic_index)

    if topic == nil do
      if total_attempts(state) == 0 do
        {:no_questions_available, %{state | status: :no_questions_available}}
      else
        {:complete, %{state | status: :complete}}
      end
    else
      attempts = Map.get(state.topic_attempts, topic.id, [])

      if topic_mastered?(attempts) or length(attempts) >= @max_attempts_per_topic do
        next_question(%{state | current_topic_index: state.current_topic_index + 1})
      else
        case select_question_by_difficulty(
               state.course_id,
               topic.id,
               state.target_difficulty,
               attempts
             ) do
          {:ok, question} ->
            {:question, question, state}

          :no_more ->
            AIQuestionGenerationWorker.enqueue(state.course_id,
              chapter_id: topic.id,
              count: 10,
              mode: "from_material"
            )

            next_question(%{state | current_topic_index: state.current_topic_index + 1})
        end
      end
    end
  end

  defp select_pending_question(%{active_skill_id: nil}), do: :fallback

  defp select_pending_question(%{active_skill_id: section_id} = state) do
    case Map.get(state.skill_states, section_id) do
      %{pending: :confirm} = skill ->
        select_skill_targeted(state, section_id, skill, max: state.target_difficulty)

      %{pending: :depth_probe} = skill ->
        min_difficulty = min(state.target_difficulty + @depth_probe_gap, 1.0)
        select_skill_targeted(state, section_id, skill, min: min_difficulty)

      _ ->
        :fallback
    end
  end

  defp select_skill_targeted(state, section_id, skill, bounds) do
    attempted_ids = Enum.map(skill.attempts, & &1.question_id)
    filters = %{chapter_id: skill.chapter_id, section_id: section_id}

    candidates =
      Questions.list_questions_with_stats(state.course_id, filters)
      |> Enum.reject(&(&1.id in attempted_ids))
      |> Enum.filter(&difficulty_in_bounds?(&1, bounds))

    case candidates do
      [] -> :fallback
      list -> {:ok, Enum.random(list)}
    end
  end

  defp difficulty_in_bounds?(question, bounds) do
    score = question_difficulty_score(question)
    max_ok = Keyword.get(bounds, :max) |> then(&(is_nil(&1) or score <= &1))
    min_ok = Keyword.get(bounds, :min) |> then(&(is_nil(&1) or score >= &1))
    max_ok and min_ok
  end

  defp question_difficulty_score(q) do
    case q.stats do
      %FunSheep.Questions.QuestionStats{difficulty_score: s} when not is_nil(s) ->
        s

      _ ->
        case q.difficulty do
          :easy -> 0.25
          :medium -> 0.5
          :hard -> 0.85
          _ -> 0.5
        end
    end
  end

  def record_answer(state, question_id, answer, is_correct) do
    topic = Enum.at(state.topics, state.current_topic_index)
    attempts = Map.get(state.topic_attempts, topic.id, [])

    new_attempt = %{question_id: question_id, answer: answer, is_correct: is_correct}
    new_attempts = attempts ++ [new_attempt]

    was_pending = state.active_skill_id != nil

    new_target =
      if was_pending,
        do: state.target_difficulty,
        else: adjust_target_difficulty(state.target_difficulty, is_correct)

    {new_skill_states, new_active_skill_id} = advance_skill_state(state, question_id, is_correct)

    %{
      state
      | topic_attempts: Map.put(state.topic_attempts, topic.id, new_attempts),
        target_difficulty: new_target,
        current_difficulty: score_to_label(new_target),
        skill_states: new_skill_states,
        active_skill_id: new_active_skill_id
    }
  end

  defp advance_skill_state(state, question_id, is_correct) do
    case Questions.get_question(question_id) do
      nil ->
        {state.skill_states, state.active_skill_id}

      %{section_id: nil} ->
        {state.skill_states, state.active_skill_id}

      %{section_id: section_id, chapter_id: chapter_id, difficulty: difficulty} ->
        skill =
          Map.get(state.skill_states, section_id, %{
            attempts: [],
            status: :insufficient_data,
            pending: nil,
            chapter_id: chapter_id
          })

        updated_skill =
          skill
          |> Map.put(
            :attempts,
            skill.attempts ++
              [%{question_id: question_id, is_correct: is_correct, difficulty: difficulty}]
          )
          |> transition_skill(is_correct, state.target_difficulty, difficulty)

        new_states = Map.put(state.skill_states, section_id, updated_skill)
        new_active = if updated_skill.pending, do: section_id, else: nil
        {new_states, new_active}
    end
  end

  defp transition_skill(%{pending: :confirm} = skill, false, _t, _d),
    do: %{skill | status: :weak, pending: nil}

  defp transition_skill(%{pending: :confirm} = skill, true, _t, _d),
    do: %{skill | status: :probing, pending: nil}

  defp transition_skill(%{pending: :depth_probe} = skill, _c, _t, _d),
    do: %{skill | status: :probing, pending: nil}

  defp transition_skill(skill, false, _t, _d),
    do: %{skill | pending: :confirm, status: holding_status(skill)}

  defp transition_skill(skill, true, target, difficulty) do
    if should_fire_depth_probe?(skill, target, difficulty) do
      %{skill | pending: :depth_probe, status: :probing}
    else
      %{skill | status: promote_status(skill), pending: nil}
    end
  end

  defp holding_status(%{attempts: a}) when length(a) < 2, do: :insufficient_data
  defp holding_status(%{status: status}), do: status

  defp promote_status(%{attempts: a}) when length(a) < 2, do: :insufficient_data
  defp promote_status(_), do: :probing

  defp should_fire_depth_probe?(%{status: :weak}, _, _), do: false
  defp should_fire_depth_probe?(%{status: :mastered}, _, _), do: false

  defp should_fire_depth_probe?(%{attempts: a}, target, difficulty) when length(a) >= 2,
    do: target >= 0.5 and difficulty_at_or_above?(difficulty, :medium)

  defp should_fire_depth_probe?(_, _, _), do: false

  defp difficulty_at_or_above?(:medium, :medium), do: true
  defp difficulty_at_or_above?(:hard, :medium), do: true
  defp difficulty_at_or_above?(:hard, :hard), do: true
  defp difficulty_at_or_above?(_, _), do: false

  def summary(state) do
    topic_results =
      Enum.map(state.topics, fn topic ->
        attempts = Map.get(state.topic_attempts, topic.id, [])
        correct = Enum.count(attempts, & &1.is_correct)
        total = length(attempts)

        %{
          topic_id: topic.id,
          topic_name: topic.name,
          correct: correct,
          total: total,
          mastered: topic_mastered?(attempts),
          score: if(total > 0, do: Float.round(correct / total * 100, 1), else: 0.0)
        }
      end)

    total_correct = Enum.sum(Enum.map(topic_results, & &1.correct))
    total_questions = Enum.sum(Enum.map(topic_results, & &1.total))

    skill_results =
      Enum.map(state.skill_states, fn {section_id, s} ->
        %{
          section_id: section_id,
          status: s.status,
          attempts: length(s.attempts),
          correct: Enum.count(s.attempts, & &1.is_correct)
        }
      end)

    %{
      topic_results: topic_results,
      skill_results: skill_results,
      total_correct: total_correct,
      total_questions: total_questions,
      overall_score:
        if(total_questions > 0,
          do: Float.round(total_correct / total_questions * 100, 1),
          else: 0.0
        )
    }
  end

  defp select_question_by_difficulty(
         course_id,
         chapter_id,
         target_difficulty,
         previous_attempts
       ) do
    attempted_ids = Enum.map(previous_attempts, & &1.question_id)
    filters = %{chapter_id: chapter_id}

    all_questions =
      Questions.list_questions_with_stats(course_id, filters)
      |> Enum.reject(&(&1.id in attempted_ids))

    if all_questions == [] do
      :no_more
    else
      scored =
        all_questions
        |> Enum.map(fn q -> {q, abs(question_difficulty_score(q) - target_difficulty)} end)
        |> Enum.sort_by(fn {_q, d} -> d end)

      candidates = Enum.filter(scored, fn {_q, d} -> d <= @difficulty_tolerance end)
      candidates = if candidates == [], do: Enum.take(scored, 3), else: candidates
      {question, _} = Enum.random(candidates)
      {:ok, question}
    end
  end

  defp adjust_target_difficulty(c, true), do: min(c + @difficulty_step, 1.0) |> Float.round(4)
  defp adjust_target_difficulty(c, false), do: max(c - @difficulty_step, 0.0) |> Float.round(4)

  defp score_to_label(s) when s < 0.33, do: :easy
  defp score_to_label(s) when s < 0.66, do: :medium
  defp score_to_label(_), do: :hard

  defp total_attempts(state) do
    state.topic_attempts
    |> Map.values()
    |> Enum.map(&length/1)
    |> Enum.sum()
  end

  defp topic_mastered?(attempts) do
    if length(attempts) < @min_questions_per_topic do
      false
    else
      correct = Enum.count(attempts, & &1.is_correct)
      correct / length(attempts) >= @mastery_threshold
    end
  end

  defp extract_topics(schedule) do
    chapter_ids = get_in(schedule.scope, ["chapter_ids"]) || []
    Courses.list_chapters_by_ids(chapter_ids)
  end
end
