defmodule StudySmart.Assessments.QuickTestEngine do
  @moduledoc """
  Quick test engine for Tinder-style card-based study sessions.

  Supports four actions per card: "I Know This", "I Don't Know",
  "Answer" (with correctness check), and "Skip".
  """

  alias StudySmart.Questions

  @doc """
  Starts a quick test session.

  ## Options
    * `:course_id` - filter to a specific course
    * `:limit` - maximum number of cards (default 20)
  """
  def start_session(user_role_id, opts \\ %{}) do
    questions = load_questions(user_role_id, opts)

    %{
      user_role_id: user_role_id,
      questions: questions,
      current_index: 0,
      results: [],
      status: :in_progress
    }
  end

  @doc """
  Returns the current card or signals completion.

  Returns:
    * `{:card, question, state}` - a card to present
    * `{:complete, state}` - all cards processed
  """
  def current_card(state) do
    case Enum.at(state.questions, state.current_index) do
      nil -> {:complete, %{state | status: :complete}}
      q -> {:card, q, state}
    end
  end

  @doc """
  Marks the current question as known (user is confident).
  Records as correct and advances.
  """
  def mark_known(state, question_id) do
    record_result(state, question_id, :know, true)
  end

  @doc """
  Marks the current question as unknown (user doesn't know).
  Records as incorrect and advances.
  """
  def mark_unknown(state, question_id) do
    record_result(state, question_id, :dont_know, false)
  end

  @doc """
  Records an answered question with correctness result.
  """
  def mark_answered(state, question_id, is_correct) do
    record_result(state, question_id, :answered, is_correct)
  end

  @doc """
  Skips the current question without recording a result.
  """
  def skip(state, _question_id) do
    %{state | current_index: state.current_index + 1}
  end

  @doc """
  Returns a summary of the quick test session.
  """
  def summary(state) do
    known = Enum.count(state.results, &(&1.action == :know))
    unknown = Enum.count(state.results, &(&1.action == :dont_know))

    answered_correct =
      Enum.count(state.results, &(&1.action == :answered and &1.is_correct))

    answered_wrong =
      Enum.count(state.results, &(&1.action == :answered and not &1.is_correct))

    skipped = length(state.questions) - length(state.results) - remaining(state)

    %{
      total: length(state.questions),
      known: known,
      unknown: unknown,
      answered_correct: answered_correct,
      answered_wrong: answered_wrong,
      skipped: max(skipped, 0),
      score: calculate_score(state.results)
    }
  end

  defp record_result(state, question_id, action, is_correct) do
    result = %{question_id: question_id, action: action, is_correct: is_correct}

    %{
      state
      | results: state.results ++ [result],
        current_index: state.current_index + 1
    }
  end

  defp remaining(state), do: max(0, length(state.questions) - state.current_index)

  defp load_questions(user_role_id, opts) do
    course_id = Map.get(opts, :course_id)
    limit = Map.get(opts, :limit, 20)

    Questions.list_questions_for_quick_test(user_role_id, course_id, limit)
  end

  defp calculate_score(results) do
    correct = Enum.count(results, & &1.is_correct)
    total = length(results)
    if total > 0, do: Float.round(correct / total * 100, 1), else: 0.0
  end
end
