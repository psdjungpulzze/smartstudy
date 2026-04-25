defmodule FunSheep.Questions.OrderingGrader do
  @moduledoc """
  Grades ordering questions where students arrange items in the correct sequence.

  Both the correct answer and the student's answer are comma-separated strings
  listing items in order, e.g. `"A,B,C,D,E"`.

  Full credit requires an exact match. Partial credit is computed using the
  longest common subsequence (LCS) length as a proxy for how close the
  student's ordering is: `score = lcs_length / total_items * 10`.
  """

  @score_max 10.0

  @doc """
  Grades an ordering question.

  Returns `{:ok, %{correct: bool, score: float, score_max: float, feedback: nil}}`.

  `question` must have an `answer` field with comma-separated correct order.
  `answer_given` is the student's comma-separated ordering.
  """
  def grade(%{answer: correct_answer}, answer_given) do
    correct_seq = correct_answer |> String.split(",") |> Enum.map(&String.trim/1)
    given_seq = answer_given |> String.split(",") |> Enum.map(&String.trim/1)

    is_correct = correct_seq == given_seq
    total = length(correct_seq)
    lcs_len = lcs_length(correct_seq, given_seq)
    score = if total > 0, do: lcs_len / total * @score_max, else: 0.0

    {:ok, %{correct: is_correct, score: score, score_max: @score_max, feedback: nil}}
  end

  # Computes the longest common subsequence length via dynamic programming.
  defp lcs_length(a, b) do
    m = length(a)
    n = length(b)
    a_arr = List.to_tuple(a)
    b_arr = List.to_tuple(b)

    # Build m+1 rows, each a tuple of n+1 zeros.
    dp =
      for _ <- 0..m do
        Tuple.duplicate(0, n + 1)
      end

    dp =
      Enum.reduce(1..m, dp, fn i, dp ->
        Enum.reduce(1..n, dp, fn j, dp ->
          val =
            if elem(a_arr, i - 1) == elem(b_arr, j - 1) do
              elem(Enum.at(dp, i - 1), j - 1) + 1
            else
              max(elem(Enum.at(dp, i - 1), j), elem(Enum.at(dp, i), j - 1))
            end

          updated_row =
            dp
            |> Enum.at(i)
            |> Tuple.delete_at(j)
            |> Tuple.insert_at(j, val)

          List.replace_at(dp, i, updated_row)
        end)
      end)

    elem(Enum.at(dp, m), n)
  end
end
