defmodule FunSheep.Assessments.Mastery do
  @moduledoc """
  Per-skill mastery check — North Star invariant I-9.

  A skill is considered mastered when the student has produced
  **N correct answers in a row at or above medium difficulty**
  (default N = 3, tunable). A single-session winning streak at easy
  difficulty does NOT count, to prevent cheap wins from closing out
  the adaptive loop.

  Works with both `%FunSheep.Questions.QuestionAttempt{}` records
  (DB rows, where the preloaded question carries the `difficulty`
  enum) and bare maps with `is_correct`, `difficulty`, and
  `inserted_at` — so it's usable inside the assessment engine and
  from the readiness calculator.
  """

  @default_streak 3
  @medium_or_harder [:medium, :hard, "medium", "hard"]

  @doc """
  Returns true when the last `streak` attempts (chronologically) are
  all correct and all at ≥medium difficulty.

  If the attempts list has fewer than `streak` entries, returns false
  — we don't pretend to know from insufficient data (I-15).
  """
  def mastered?(attempts, streak \\ @default_streak) when is_list(attempts) do
    ordered = Enum.sort_by(attempts, &attempt_timestamp/1, {:asc, DateTime})
    tail = Enum.take(ordered, -streak)

    length(tail) >= streak and Enum.all?(tail, &qualifying?/1)
  end

  @doc """
  Classifies a skill into `:insufficient_data | :probing | :weak | :mastered`
  based on its attempt history. Deliberate about not labeling on thin
  evidence (I-4, I-15).
  """
  def status(attempts, opts \\ []) do
    streak = Keyword.get(opts, :streak, @default_streak)
    weak_threshold = Keyword.get(opts, :weak_threshold, 0.4)

    cond do
      length(attempts) < 2 -> :insufficient_data
      mastered?(attempts, streak) -> :mastered
      correct_ratio(attempts) < weak_threshold -> :weak
      true -> :probing
    end
  end

  # --- private ---

  defp qualifying?(%{is_correct: true} = a) do
    difficulty_at_medium_plus?(extract_difficulty(a))
  end

  defp qualifying?(_), do: false

  defp extract_difficulty(%{difficulty_at_attempt: d}) when not is_nil(d), do: d
  defp extract_difficulty(%{difficulty: d}) when not is_nil(d), do: d
  # QuestionAttempt with preloaded question
  defp extract_difficulty(%{question: %{difficulty: d}}) when not is_nil(d), do: d
  defp extract_difficulty(_), do: nil

  defp difficulty_at_medium_plus?(d), do: d in @medium_or_harder

  defp attempt_timestamp(%{inserted_at: ts}) when not is_nil(ts), do: ts
  # Tests or engine states without timestamps — preserve insertion order.
  defp attempt_timestamp(_), do: ~U[1970-01-01 00:00:00Z]

  defp correct_ratio([]), do: 0.0

  defp correct_ratio(attempts) do
    correct = Enum.count(attempts, & &1.is_correct)
    correct / length(attempts)
  end
end
