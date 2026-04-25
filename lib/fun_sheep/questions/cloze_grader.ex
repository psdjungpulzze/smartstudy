defmodule FunSheep.Questions.ClozeGrader do
  @moduledoc """
  Grades cloze (fill-in-the-blank) questions.

  Both the correct answer and the student's answer are JSON-encoded maps where
  keys are blank identifiers (e.g. `"1"`, `"2"`) and values are the expected
  fill-in strings.

  Comparison is case-insensitive. Partial credit is awarded proportionally:
  correctly-filled blanks / total blanks.
  """

  @score_max 10.0

  @doc """
  Grades a cloze question.

  Returns `{:ok, %{correct: bool, score: float, score_max: float, feedback: nil}}` on
  success, or `{:error, :invalid_answer_format}` if either answer cannot be decoded.

  `question` must have an `answer` field containing a JSON-encoded map, e.g.:
      `~s({"1":"photosynthesis","2":"chlorophyll"})`

  `answer_given` must follow the same shape.
  """
  def grade(%{answer: correct_answer}, answer_given) do
    with {:ok, correct_map} <- Jason.decode(correct_answer),
         {:ok, given_map} <- Jason.decode(answer_given) do
      total = map_size(correct_map)

      correct_count =
        Enum.count(correct_map, fn {k, v} ->
          String.downcase(given_map[k] || "") == String.downcase(v)
        end)

      is_correct = correct_count == total
      score = if total > 0, do: correct_count / total * @score_max, else: 0.0

      {:ok, %{correct: is_correct, score: score, score_max: @score_max, feedback: nil}}
    else
      _ -> {:error, :invalid_answer_format}
    end
  end
end
