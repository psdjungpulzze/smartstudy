defmodule FunSheep.Assessments.Engine do
  @moduledoc """
  Adaptive assessment engine.

  Layered model (see `docs/PRODUCT_NORTH_STAR.md`):

    * **Topic = chapter.** Topics are iterated in order; we move on when a
      topic is mastered or exhausted.
    * **Skill = section.** Every adaptive-eligible question carries a
      `section_id`; diagnostic decisions ("is this student weak in X?") are
      made per-skill, not per-topic.

  The engine keeps per-skill state in `skill_states` and honors two rules the
  product goal depends on:

    * **I-2 Confirm on wrong** — a wrong answer sets `pending: :confirm` on
      the skill. The next question MUST come from the same section at or
      below the current difficulty. A second wrong confirms weakness; a
      correct confirmation clears the flag.
    * **I-3 Depth probe on correct-at-target** — once a skill has surface
      competence at medium+ difficulty, the engine may fire one harder
      question on the same section to probe ceiling. Failure of the probe
      does NOT write `:weak` — it just reverts to `:probing`.

  `:weak` is written only from a confirmed-wrong path (I-4). Skills with <2
  attempts stay `:insufficient_data` (I-15) rather than getting labeled on
  thin evidence.
  """

  alias FunSheep.{Questions, Courses}
  alias FunSheep.Workers.AIQuestionGenerationWorker

  @min_questions_per_topic 3
  @mastery_threshold 0.7
  @max_attempts_per_topic 6

  # How much to shift the target difficulty on each answer
  @difficulty_step 0.15
  # How close a question's difficulty must be to the target to be considered
  @difficulty_tolerance 0.25
  # Depth probes must be at least this much harder than the current target.
  @depth_probe_gap 0.1

  @doc """
  Initializes an assessment state from a test schedule.

  Options:
  - source_material_ids: list of material IDs to confine questions to (nil = all)
  """
  def start_assessment(test_schedule, opts \\ []) do
    topics = extract_topics(test_schedule)

    %{
      schedule_id: test_schedule.id,
      course_id: test_schedule.course_id,
      scope: test_schedule.scope,
      current_topic_index: 0,
      topics: topics,
      # Start at medium difficulty (0.5 on the crowd-sourced scale)
      target_difficulty: 0.5,
      current_difficulty: :medium,
      topic_attempts: %{},
      # Per-skill (section_id) state. See moduledoc.
      skill_states: %{},
      # When non-nil, the next question must come from this skill because a
      # confirmation or depth-probe is pending.
      active_skill_id: nil,
      status: :in_progress,
      # Question set confinement — only use questions from these materials
      source_material_ids: opts[:source_material_ids]
    }
  end

  @doc """
  Returns the next question or signals completion.

  Returns:
  - `{:question, question, state}` - a question to present
  - `{:generate_needed, topic, state}` - need to generate questions for this topic
  - `{:complete, state}` - assessment is done
  """
  def next_question(state) do
    case select_pending_question(state) do
      {:ok, question} ->
        {:question, question, state}

      :fallback ->
        # No same-section candidate exists for this confirm/probe. We don't
        # fabricate one — clear the pending flag so future answers aren't
        # misattributed to a probe that never ran, then fall through to
        # normal topic flow.
        next_topic_question(clear_pending(state))
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

  # Normal topic-based flow — unchanged from the pre-adaptive-skill logic.
  defp next_topic_question(state) do
    topic = Enum.at(state.topics, state.current_topic_index)

    if topic == nil do
      {:complete, %{state | status: :complete}}
    else
      attempts = Map.get(state.topic_attempts, topic.id, [])

      if topic_mastered?(attempts) or length(attempts) >= @max_attempts_per_topic do
        next_question(%{state | current_topic_index: state.current_topic_index + 1})
      else
        case select_question_by_difficulty(
               state.course_id,
               topic.id,
               state.target_difficulty,
               attempts,
               state.source_material_ids
             ) do
          {:ok, question} ->
            {:question, question, state}

          :no_more ->
            # Trigger AI generation for this topic so more questions appear next time
            AIQuestionGenerationWorker.enqueue(state.course_id,
              chapter_id: topic.id,
              count: 10,
              mode: "from_material"
            )

            # Move to next topic for now
            next_question(%{state | current_topic_index: state.current_topic_index + 1})
        end
      end
    end
  end

  # If a skill has a pending confirmation or depth probe, try to serve its
  # follow-up question from the same section. Returns `:fallback` when no
  # same-section candidate exists — we never fabricate a confirm/probe, so
  # the pending flag is left to be cleared by the caller path if needed.
  defp select_pending_question(%{active_skill_id: nil}), do: :fallback

  defp select_pending_question(%{active_skill_id: section_id} = state) do
    case Map.get(state.skill_states, section_id) do
      %{pending: :confirm} = skill ->
        # Same section, difficulty at-or-below target (don't escalate a wrong).
        select_skill_targeted(state, section_id, skill, max: state.target_difficulty)

      %{pending: :depth_probe} = skill ->
        # Same section, strictly harder than current target.
        min_difficulty = min(state.target_difficulty + @depth_probe_gap, 1.0)
        select_skill_targeted(state, section_id, skill, min: min_difficulty)

      _ ->
        :fallback
    end
  end

  defp select_skill_targeted(state, section_id, skill, bounds) do
    attempted_ids = Enum.map(skill.attempts, & &1.question_id)

    filters = %{chapter_id: skill.chapter_id, section_id: section_id}

    filters =
      if state.source_material_ids do
        Map.put(filters, :source_material_ids, state.source_material_ids)
      else
        filters
      end

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

  # Crowd-sourced difficulty when available; otherwise fall back to the
  # question's authored difficulty enum. Prevents missing stats from
  # breaking confirm/probe selection.
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

  @doc """
  Records an answer and updates both topic- and skill-level state.

  The per-skill state machine (see moduledoc) decides whether to:
  - set `pending: :confirm` (first wrong) or mark the skill `:weak` (second wrong),
  - fire `pending: :depth_probe` (correct at target with surface competence),
  - or clear pending and revert to `:probing`.
  """
  def record_answer(state, question_id, answer, is_correct) do
    topic = Enum.at(state.topics, state.current_topic_index)
    attempts = Map.get(state.topic_attempts, topic.id, [])

    new_attempt = %{
      question_id: question_id,
      answer: answer,
      is_correct: is_correct
    }

    new_attempts = attempts ++ [new_attempt]

    # Target difficulty only shifts on "fresh" answers, not during a
    # confirmation or depth-probe response — otherwise we double-penalize a
    # wrong that already moved the dial, or double-promote a correct that
    # was an easy confirmation.
    was_pending = state.active_skill_id != nil

    new_target =
      if was_pending,
        do: state.target_difficulty,
        else: adjust_target_difficulty(state.target_difficulty, is_correct)

    {new_skill_states, new_active_skill_id} =
      advance_skill_state(state, question_id, is_correct)

    %{
      state
      | topic_attempts: Map.put(state.topic_attempts, topic.id, new_attempts),
        target_difficulty: new_target,
        current_difficulty: score_to_label(new_target),
        skill_states: new_skill_states,
        active_skill_id: new_active_skill_id
    }
  end

  # Pull the question's section_id (and chapter_id) so skill_states can be
  # keyed correctly. We avoid a DB round-trip by reading from the adaptive
  # pool; if the question isn't found (e.g. an old unclassified row, which
  # shouldn't happen since adaptive selection excludes them), we skip the
  # skill update rather than fabricate one.
  defp advance_skill_state(state, question_id, is_correct) do
    case Questions.get_question(question_id) do
      nil ->
        {state.skill_states, state.active_skill_id}

      %{section_id: nil} ->
        # Not adaptive-eligible — honesty gate. Don't build a skill signal
        # on untagged evidence.
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
              [
                %{
                  question_id: question_id,
                  is_correct: is_correct,
                  difficulty: difficulty
                }
              ]
          )
          |> transition_skill(is_correct, state.target_difficulty, difficulty)

        new_states = Map.put(state.skill_states, section_id, updated_skill)

        new_active =
          case updated_skill.pending do
            nil -> nil
            _ -> section_id
          end

        {new_states, new_active}
    end
  end

  # State transitions. See moduledoc I-2/I-3/I-4.
  defp transition_skill(%{pending: :confirm} = skill, false = _is_correct, _tgt, _diff) do
    # Confirmed wrong on same skill → weak (I-4).
    %{skill | status: :weak, pending: nil}
  end

  defp transition_skill(%{pending: :confirm} = skill, true = _is_correct, _tgt, _diff) do
    # Confirm came back correct — one wrong, one right. Not weak, not mastered.
    %{skill | status: :probing, pending: nil}
  end

  defp transition_skill(%{pending: :depth_probe} = skill, true = _is_correct, _tgt, _diff) do
    # Passed the probe. Still requires more data for mastery (see I-9, Task #5).
    %{skill | status: :probing, pending: nil}
  end

  defp transition_skill(%{pending: :depth_probe} = skill, false = _is_correct, _tgt, _diff) do
    # Ceiling found — NOT weak, just revert.
    %{skill | status: :probing, pending: nil}
  end

  defp transition_skill(skill, false = _is_correct, _tgt, _diff) do
    # First wrong on this skill — trigger confirmation. Don't label weak yet (I-4).
    %{skill | pending: :confirm, status: holding_status(skill)}
  end

  defp transition_skill(skill, true = _is_correct, target, difficulty) do
    # Correct. Maybe fire depth probe if we've already shown surface competence
    # at medium+ difficulty AND this was at or above the current target.
    if should_fire_depth_probe?(skill, target, difficulty) do
      %{skill | pending: :depth_probe, status: :probing}
    else
      %{skill | status: promote_status(skill), pending: nil}
    end
  end

  # Keep the honest `:insufficient_data` label until we have at least 2
  # attempts to reason from — per I-15.
  defp holding_status(%{attempts: attempts}) when length(attempts) < 2, do: :insufficient_data
  defp holding_status(%{status: status}), do: status

  defp promote_status(%{attempts: attempts}) when length(attempts) < 2, do: :insufficient_data
  defp promote_status(_), do: :probing

  defp should_fire_depth_probe?(%{status: :weak}, _target, _difficulty), do: false
  defp should_fire_depth_probe?(%{status: :mastered}, _target, _difficulty), do: false

  defp should_fire_depth_probe?(%{attempts: attempts}, target, difficulty)
       when length(attempts) >= 2 do
    # Only probe once the student shows they're operating at medium+ and
    # the current question matched or exceeded target. Keeps the assessment
    # bounded.
    target >= 0.5 and difficulty_at_or_above?(difficulty, :medium)
  end

  defp should_fire_depth_probe?(_skill, _target, _difficulty), do: false

  defp difficulty_at_or_above?(:medium, :medium), do: true
  defp difficulty_at_or_above?(:hard, :medium), do: true
  defp difficulty_at_or_above?(:hard, :hard), do: true
  defp difficulty_at_or_above?(_, _), do: false

  @doc """
  Returns a summary of the assessment results, including per-skill state.
  """
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

  # --- Private ---

  # Select a question whose crowd-sourced difficulty is close to the target.
  # Falls back to any available question if nothing is within tolerance.
  defp select_question_by_difficulty(
         course_id,
         chapter_id,
         target_difficulty,
         previous_attempts,
         source_material_ids
       ) do
    attempted_ids = Enum.map(previous_attempts, & &1.question_id)

    filters = %{chapter_id: chapter_id}

    filters =
      if source_material_ids do
        Map.put(filters, :source_material_ids, source_material_ids)
      else
        filters
      end

    all_questions =
      Questions.list_questions_with_stats(course_id, filters)
      |> Enum.reject(&(&1.id in attempted_ids))

    if all_questions == [] do
      :no_more
    else
      # Score each question by how close its difficulty is to the target
      scored =
        all_questions
        |> Enum.map(fn q ->
          q_difficulty = question_difficulty_score(q)
          distance = abs(q_difficulty - target_difficulty)
          {q, distance}
        end)
        |> Enum.sort_by(fn {_q, dist} -> dist end)

      # Pick from the closest questions (within tolerance), with some randomness
      candidates =
        scored
        |> Enum.filter(fn {_q, dist} -> dist <= @difficulty_tolerance end)

      # If no candidates within tolerance, take the 3 closest
      candidates = if candidates == [], do: Enum.take(scored, 3), else: candidates

      {question, _dist} = Enum.random(candidates)
      {:ok, question}
    end
  end

  defp adjust_target_difficulty(current, _is_correct = true) do
    # Got it right → make it harder (increase target)
    min(current + @difficulty_step, 1.0) |> Float.round(4)
  end

  defp adjust_target_difficulty(current, _is_correct = false) do
    # Got it wrong → make it easier (decrease target)
    max(current - @difficulty_step, 0.0) |> Float.round(4)
  end

  defp score_to_label(score) when score < 0.33, do: :easy
  defp score_to_label(score) when score < 0.66, do: :medium
  defp score_to_label(_score), do: :hard

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
