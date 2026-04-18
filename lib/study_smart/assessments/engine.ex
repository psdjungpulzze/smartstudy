defmodule StudySmart.Assessments.Engine do
  @moduledoc """
  Adaptive assessment engine.

  - Min 3 questions per topic
  - Progressive difficulty (easy -> medium -> hard)
  - Re-test on incorrect answers to verify gaps
  """

  alias StudySmart.{Questions, Courses}

  @min_questions_per_topic 3
  @mastery_threshold 0.7
  @max_attempts_per_topic 6

  @doc """
  Initializes an assessment state from a test schedule.
  """
  def start_assessment(test_schedule) do
    topics = extract_topics(test_schedule)

    %{
      schedule_id: test_schedule.id,
      course_id: test_schedule.course_id,
      scope: test_schedule.scope,
      current_topic_index: 0,
      topics: topics,
      current_difficulty: :easy,
      topic_attempts: %{},
      status: :in_progress
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
        case select_question(state.course_id, topic.id, state.current_difficulty, attempts) do
          {:ok, question} ->
            {:question, question, state}

          :no_more ->
            # No more questions available for this topic/difficulty, try other difficulties
            case try_other_difficulties(state, topic, attempts) do
              {:ok, question, new_state} ->
                {:question, question, new_state}

              :exhausted ->
                next_question(%{state | current_topic_index: state.current_topic_index + 1})
            end
        end
      end
    end
  end

  @doc """
  Records an answer and adjusts difficulty.
  Returns the updated state.
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
    new_difficulty = adjust_difficulty(state.current_difficulty, is_correct)

    %{
      state
      | topic_attempts: Map.put(state.topic_attempts, topic.id, new_attempts),
        current_difficulty: new_difficulty
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

  # Private functions

  defp select_question(course_id, chapter_id, difficulty, previous_attempts) do
    attempted_ids = Enum.map(previous_attempts, & &1.question_id)

    question =
      Questions.list_questions_by_course(course_id, %{
        chapter_id: chapter_id,
        difficulty: difficulty
      })
      |> Enum.reject(&(&1.id in attempted_ids))
      |> List.first()

    case question do
      nil -> :no_more
      q -> {:ok, q}
    end
  end

  defp try_other_difficulties(state, topic, attempts) do
    other_difficulties =
      [:easy, :medium, :hard]
      |> Enum.reject(&(&1 == state.current_difficulty))

    Enum.reduce_while(other_difficulties, :exhausted, fn diff, _acc ->
      case select_question(state.course_id, topic.id, diff, attempts) do
        {:ok, question} ->
          {:halt, {:ok, question, %{state | current_difficulty: diff}}}

        :no_more ->
          {:cont, :exhausted}
      end
    end)
  end

  defp topic_mastered?(attempts) do
    if length(attempts) < @min_questions_per_topic do
      false
    else
      correct = Enum.count(attempts, & &1.is_correct)
      correct / length(attempts) >= @mastery_threshold
    end
  end

  defp adjust_difficulty(current, true) do
    case current do
      :easy -> :medium
      :medium -> :hard
      :hard -> :hard
    end
  end

  defp adjust_difficulty(current, false) do
    case current do
      :hard -> :medium
      :medium -> :easy
      :easy -> :easy
    end
  end

  defp extract_topics(schedule) do
    chapter_ids = get_in(schedule.scope, ["chapter_ids"]) || []
    Courses.list_chapters_by_ids(chapter_ids)
  end
end
