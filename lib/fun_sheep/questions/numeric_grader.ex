defmodule FunSheep.Questions.NumericGrader do
  @moduledoc """
  Grades numeric questions where the student enters a number.

  The correct answer is stored as a string (e.g. `"126"`). An optional
  `"tolerance_pct"` key in the question's `options` map allows for a percentage
  band around the correct answer (e.g. `1` means ±1%).

  For a correct answer of `0`, only an exact match of `0` is accepted regardless
  of tolerance.
  """

  @score_max 10.0

  @doc """
  Grades a numeric question.

  Returns `{:ok, %{correct: bool, score: float, score_max: float, feedback: nil}}` on
  success, or `{:error, :invalid_number_format}` if either value cannot be parsed.

  `question` must have:
    * `answer` — the correct numeric value as a string, e.g. `"126"`
    * `options` — (optional) map that may contain `"tolerance_pct"` (integer or float)

  `answer_given` is the student's input as a string.
  """
  def grade(%{answer: correct_answer, options: options}, answer_given) do
    with {correct, ""} <- Float.parse(correct_answer),
         {given, ""} <- Float.parse(answer_given) do
      tolerance = get_in(options, ["tolerance_pct"]) || 0

      is_correct =
        if correct == 0.0 do
          given == 0.0
        else
          abs(given - correct) / abs(correct) <= tolerance / 100.0
        end

      score = if is_correct, do: @score_max, else: 0.0

      {:ok, %{correct: is_correct, score: score, score_max: @score_max, feedback: nil}}
    else
      _ -> {:error, :invalid_number_format}
    end
  end

  def grade(%{answer: correct_answer}, answer_given) do
    grade(%{answer: correct_answer, options: %{}}, answer_given)
  end
end
