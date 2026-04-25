defmodule FunSheep.Questions.MatchingGraderTest do
  use ExUnit.Case, async: true

  alias FunSheep.Questions.MatchingGrader

  defp question(answer_map) do
    %{answer: Jason.encode!(answer_map)}
  end

  defp given(answer_map), do: Jason.encode!(answer_map)

  describe "grade/2" do
    test "all pairs correct returns correct: true and score: 10.0" do
      q = question(%{"A" => "2", "B" => "3", "C" => "1"})

      assert {:ok, %{correct: true, score: 10.0, score_max: 10.0}} =
               MatchingGrader.grade(q, given(%{"A" => "2", "B" => "3", "C" => "1"}))
    end

    test "some pairs correct gives proportional partial credit" do
      # 2 of 3 correct = 6.666...
      q = question(%{"A" => "1", "B" => "2", "C" => "3"})

      {:ok, result} = MatchingGrader.grade(q, given(%{"A" => "1", "B" => "2", "C" => "X"}))
      refute result.correct
      assert_in_delta result.score, 20.0 / 3.0, 0.001
    end

    test "no pairs correct returns score: 0.0" do
      q = question(%{"A" => "1", "B" => "2"})

      assert {:ok, %{correct: false, score: 0.0}} =
               MatchingGrader.grade(q, given(%{"A" => "X", "B" => "Y"}))
    end

    test "single pair, correct returns correct: true" do
      q = question(%{"A" => "1"})

      assert {:ok, %{correct: true, score: 10.0}} =
               MatchingGrader.grade(q, given(%{"A" => "1"}))
    end

    test "single pair, wrong returns correct: false" do
      q = question(%{"A" => "1"})

      assert {:ok, %{correct: false, score: 0.0}} =
               MatchingGrader.grade(q, given(%{"A" => "2"}))
    end

    test "invalid JSON in correct answer returns error" do
      assert {:error, :invalid_answer_format} =
               MatchingGrader.grade(%{answer: "not-json"}, given(%{"A" => "1"}))
    end

    test "invalid JSON in student answer returns error" do
      q = question(%{"A" => "1"})
      assert {:error, :invalid_answer_format} = MatchingGrader.grade(q, "not-json")
    end

    test "feedback field is nil" do
      q = question(%{"A" => "1"})
      assert {:ok, %{feedback: nil}} = MatchingGrader.grade(q, given(%{"A" => "1"}))
    end

    test "score_max is 10.0" do
      q = question(%{"A" => "1", "B" => "2"})

      assert {:ok, %{score_max: 10.0}} =
               MatchingGrader.grade(q, given(%{"A" => "1", "B" => "2"}))
    end

    test "matching is case-sensitive for pair values" do
      q = question(%{"A" => "answer"})

      assert {:ok, %{correct: false}} =
               MatchingGrader.grade(q, given(%{"A" => "Answer"}))
    end
  end
end
