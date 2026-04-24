defmodule FunSheep.Questions.MatchingGrader do
  @moduledoc """
  Grades matching questions where students pair items from two columns.

  Both the correct answer and the student's answer are JSON-encoded maps where
  keys are left-column labels (e.g. `"A"`, `"B"`) and values are right-column
  labels (e.g. `"1"`, `"2"`).

  Partial credit is awarded proportionally: correct pairs / total pairs.
  """

  @score_max 10.0

  @doc """
  Grades a matching question.

  Returns `{:ok, %{correct: bool, score: float, score_max: float, feedback: nil}}` on
  success, or `{:error, :invalid_answer_format}` if either answer cannot be decoded.

  `question` must have an `answer` field containing a JSON-encoded map, e.g.:
      `~s({"A":"2","B":"3","C":"1"})`

  `answer_given` must follow the same shape.
  """
  def grade(%{answer: correct_answer}, answer_given) do
    with {:ok, correct_map} <- Jason.decode(correct_answer),
         {:ok, given_map} <- Jason.decode(answer_given) do
      total = map_size(correct_map)
      correct_count = Enum.count(correct_map, fn {k, v} -> given_map[k] == v end)
      is_correct = correct_count == total
      score = if total > 0, do: correct_count / total * @score_max, else: 0.0

      {:ok, %{correct: is_correct, score: score, score_max: @score_max, feedback: nil}}
    else
      _ -> {:error, :invalid_answer_format}
    end
  end
end
