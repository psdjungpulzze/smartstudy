defmodule FunSheep.MemorySpan.Calculator do
  @moduledoc """
  Pure calculation module for memory span computation.

  Computes how long a student's memory lasts for a given question or topic by
  analyzing the gap between correct answers and subsequent incorrect answers
  ("decay events").

  No side effects — all functions are pure and testable without a database.
  """

  # Cap decay gaps at 90 days to avoid summer-break skew inflating spans.
  @max_gap_hours 90 * 24

  @doc """
  Computes the memory span for a single question based on attempt history.

  `attempts` must be a list of maps with `:is_correct` (boolean) and
  `:inserted_at` (DateTime), sorted ascending by inserted_at.

  Returns `{:ok, span_hours}` when at least one decay event is found, or
  `{:insufficient_data, reason}` when there is not enough signal.

  ## Algorithm

  Walk the attempts tracking `last_correct_at`:
  - When correct: set `last_correct_at`
  - When incorrect and `last_correct_at` is set: record the gap (capped at
    90 days), reset `last_correct_at`

  The returned span is the median of all recorded decay gaps.
  """
  @spec compute_question_span([%{is_correct: boolean(), inserted_at: DateTime.t()}]) ::
          {:ok, non_neg_integer()} | {:insufficient_data, atom()}
  def compute_question_span([]), do: {:insufficient_data, :no_decay_events}

  def compute_question_span(attempts) do
    sorted = Enum.sort_by(attempts, & &1.inserted_at, DateTime)

    {decay_gaps, _last_correct_at} =
      Enum.reduce(sorted, {[], nil}, fn attempt, {gaps, last_correct_at} ->
        if attempt.is_correct do
          {gaps, attempt.inserted_at}
        else
          case last_correct_at do
            nil ->
              {gaps, nil}

            correct_at ->
              gap = DateTime.diff(attempt.inserted_at, correct_at, :second) |> div(3600)

              if gap > 0 do
                capped = min(gap, @max_gap_hours)
                {[capped | gaps], nil}
              else
                {gaps, nil}
              end
          end
        end
      end)

    if decay_gaps == [] do
      {:insufficient_data, :no_decay_events}
    else
      {:ok, median(decay_gaps)}
    end
  end

  @doc """
  Computes the aggregate memory span for a topic (chapter or course) from
  a list of question-level span_hours values.

  `spans` is a list of integers (span_hours for each contributing question).
  Nils are filtered out. Returns `{:ok, median_span_hours}` or
  `{:insufficient_data, :no_question_spans}`.
  """
  @spec compute_topic_span([integer() | nil]) ::
          {:ok, non_neg_integer()} | {:insufficient_data, atom()}
  def compute_topic_span(spans) do
    valid = Enum.reject(spans, &is_nil/1)

    if valid == [] do
      {:insufficient_data, :no_question_spans}
    else
      {:ok, median(valid)}
    end
  end

  @doc """
  Returns the median of a list of numbers.

  For even-length lists, returns the average of the two middle values
  (integer division to keep return type as integer).

  Raises `ArgumentError` on an empty list.
  """
  @spec median([number()]) :: number()
  def median([]), do: raise(ArgumentError, "cannot compute median of empty list")

  def median(list) do
    sorted = Enum.sort(list)
    count = length(sorted)
    mid = div(count, 2)

    if rem(count, 2) == 0 do
      div(Enum.at(sorted, mid - 1) + Enum.at(sorted, mid), 2)
    else
      Enum.at(sorted, mid)
    end
  end
end
