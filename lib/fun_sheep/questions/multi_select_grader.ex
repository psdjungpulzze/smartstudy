defmodule FunSheep.Questions.MultiSelectGrader do
  @moduledoc """
  Grades multi-select questions where students choose one or more correct options.

  Correct answer and student answer are both comma-separated option strings.
  Partial credit is awarded proportionally: correct selections / total correct options.
  Order of selections does not matter.
  """

  @score_max 10.0

  @doc """
  Grades a multi-select question.

  Returns `{:ok, %{correct: bool, score: float, score_max: float, feedback: nil}}`.

  `question` must have an `answer` field containing comma-separated correct options.
  `answer_given` is a comma-separated string of the student's selections.
  """
  def grade(%{answer: correct_answer}, answer_given) do
    correct_set =
      correct_answer |> String.split(",") |> Enum.map(&String.trim/1) |> MapSet.new()

    given_set =
      answer_given |> String.split(",") |> Enum.map(&String.trim/1) |> MapSet.new()

    is_correct = MapSet.equal?(correct_set, given_set)
    score = if is_correct, do: @score_max, else: calculate_partial_score(correct_set, given_set)

    {:ok, %{correct: is_correct, score: score, score_max: @score_max, feedback: nil}}
  end

  defp calculate_partial_score(correct_set, given_set) do
    correct_count = correct_set |> MapSet.intersection(given_set) |> MapSet.size()
    total_correct = MapSet.size(correct_set)

    if total_correct > 0, do: correct_count / total_correct * @score_max, else: 0.0
  end
end
