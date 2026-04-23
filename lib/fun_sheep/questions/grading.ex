defmodule FunSheep.Questions.Grading do
  @moduledoc """
  Single source of truth for grading a student's answer against a question.

  Multiple LiveViews (`assessment_live`, `practice_live`, `quick_test_live`,
  `quick_practice_live`, `daily_challenge_live`, `format_test_live`) used to
  inline `check_answer/2` as `String.downcase(trim(answer)) ==
  String.downcase(trim(question.answer))`. That fails for the most common
  question type — multiple choice — because the UI submits the option *key*
  (e.g. `"c"`) while `question.answer` stores the option *text* (e.g.
  `"Oxidative phosphorylation"`). Selected-correct answers were graded as
  incorrect, breaking I-9 (honest feedback) and silently corrupting
  weak-topic detection.

  This module resolves multiple-choice keys to their option text before
  comparison, while keeping plain string equality for short-answer /
  free-response / true-false. Trims and lowercases to absorb cosmetic
  whitespace and case differences, but preserves the semantics: never
  promote a fundamentally different answer to "correct".
  """

  @doc """
  Returns `true` iff `submitted` is a correct answer to `question`.

  - Multiple choice: `submitted` is treated as either an option key (looked
    up against `question.options`) or, as a fallback, the literal text the
    user typed/sent. Either path must match `question.answer` after
    trim+downcase.
  - True/false, short-answer, free-response: trim+downcase string compare.
  """
  @spec correct?(map() | struct(), term()) :: boolean()
  def correct?(_question, nil), do: false
  def correct?(_question, ""), do: false

  def correct?(%{question_type: :multiple_choice, options: options} = question, submitted)
      when is_map(options) do
    expected = normalize(question.answer)

    submitted
    |> candidate_strings(options)
    |> Enum.any?(fn candidate -> normalize(candidate) == expected end)
  end

  def correct?(question, submitted) when is_binary(submitted) do
    normalize(submitted) == normalize(question.answer)
  end

  def correct?(_, _), do: false

  # Returns every plausible string form of `submitted` for comparison: the
  # raw value, the option text under that key, and (if the LLM stored the
  # answer as a key like "c") the key itself. We accept a match against any
  # form so the grader is tolerant to either storage convention.
  defp candidate_strings(submitted, options) when is_binary(submitted) do
    text_via_key = Map.get(options, submitted)

    [submitted, text_via_key]
    |> Enum.reject(&is_nil/1)
  end

  defp candidate_strings(submitted, _options), do: [to_string(submitted)]

  defp normalize(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize(value), do: value |> to_string() |> normalize()
end
