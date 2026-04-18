defmodule StudySmart.Assessments.PracticeEngine do
  @moduledoc """
  Practice engine focused on questions the student scored lower on.
  Repetitive cycle: test -> show results -> provide learning materials -> re-test.
  """

  alias StudySmart.Questions

  @doc """
  Starts a practice session for a user in a course.

  ## Options
    * `:chapter_id` - focus on a specific chapter
    * `:limit` - maximum number of questions (default 20)
  """
  def start_practice(user_role_id, course_id, opts \\ %{}) do
    weak_questions = get_weak_questions(user_role_id, course_id, opts)

    %{
      user_role_id: user_role_id,
      course_id: course_id,
      questions: weak_questions,
      current_index: 0,
      attempts: [],
      status: :in_progress
    }
  end

  @doc """
  Returns the current question or signals completion.

  Returns:
    * `{:question, question, state}` - a question to present
    * `{:complete, state}` - all questions answered
  """
  def current_question(state) do
    case Enum.at(state.questions, state.current_index) do
      nil -> {:complete, %{state | status: :complete}}
      question -> {:question, question, state}
    end
  end

  @doc """
  Records an answer and advances to the next question.
  """
  def record_answer(state, question_id, answer_given, is_correct) do
    attempt = %{question_id: question_id, answer: answer_given, is_correct: is_correct}

    %{
      state
      | attempts: state.attempts ++ [attempt],
        current_index: state.current_index + 1
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
      improved:
        Enum.count(state.attempts, fn a ->
          # Count questions answered correctly (improvements over previous wrong answers)
          a.is_correct
        end)
    }
  end

  defp get_weak_questions(user_role_id, course_id, opts) do
    chapter_id = Map.get(opts, :chapter_id)
    limit = Map.get(opts, :limit, 20)

    Questions.list_weak_questions(user_role_id, course_id, chapter_id, limit)
  end
end
