defmodule FunSheep.Assessments.Engine do
  @moduledoc """
  Adaptive assessment engine.

  Uses crowd-sourced difficulty scores (0.0 = easy, 1.0 = hard) to select
  questions at the student's current performance level.

  - Min 3 questions per topic before mastery can be declared
  - Progressive difficulty: gets harder on correct answers, easier on wrong
  - Difficulty is based on how many students across the platform get each question right/wrong
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

  @doc """
  Records an answer and adjusts difficulty.

  - Correct answer → target_difficulty increases (harder questions next)
  - Wrong answer → target_difficulty decreases or stays (confirm the gap)
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
    new_target = adjust_target_difficulty(state.target_difficulty, is_correct)

    %{
      state
      | topic_attempts: Map.put(state.topic_attempts, topic.id, new_attempts),
        target_difficulty: new_target,
        current_difficulty: score_to_label(new_target)
    }
  end

  @doc """
  Returns a summary of the assessment results.
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

    %{
      topic_results: topic_results,
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
          q_difficulty = if q.stats, do: q.stats.difficulty_score, else: 0.5
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
