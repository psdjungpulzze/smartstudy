defmodule FunSheep.Assessments.Mastery do
  @moduledoc """
  Per-skill mastery check — North Star I-9.

  A skill is mastered when the student has produced **N correct answers in a
  row at or above medium difficulty** (default N = 3). A single-session
  streak at easy difficulty does not count.

  Works with DB QuestionAttempt rows (question preloaded) and bare maps
  with `is_correct` + `difficulty` + `inserted_at` — usable from both the
  readiness calculator and the assessment engine.
  """

  @default_streak 3
  @medium_or_harder [:medium, :hard, "medium", "hard"]

  def mastered?(attempts, streak \\ @default_streak) when is_list(attempts) do
    ordered = Enum.sort_by(attempts, &attempt_timestamp/1, {:asc, DateTime})
    tail = Enum.take(ordered, -streak)
    length(tail) >= streak and Enum.all?(tail, &qualifying?/1)
  end

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

  defp qualifying?(%{is_correct: true} = a), do: difficulty_at_medium_plus?(extract_difficulty(a))
  defp qualifying?(_), do: false

  defp extract_difficulty(%{difficulty_at_attempt: d}) when not is_nil(d), do: d
  defp extract_difficulty(%{difficulty: d}) when not is_nil(d), do: d
  defp extract_difficulty(%{question: %{difficulty: d}}) when not is_nil(d), do: d
  defp extract_difficulty(_), do: nil

  defp difficulty_at_medium_plus?(d), do: d in @medium_or_harder

  defp attempt_timestamp(%{inserted_at: ts}) when not is_nil(ts), do: ts
  defp attempt_timestamp(_), do: ~U[1970-01-01 00:00:00Z]

  defp correct_ratio([]), do: 0.0

  defp correct_ratio(attempts) do
    correct = Enum.count(attempts, & &1.is_correct)
    correct / length(attempts)
  end
end
