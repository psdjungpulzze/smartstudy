defmodule FunSheep.Questions.OrderingGraderTest do
  use ExUnit.Case, async: true

  alias FunSheep.Questions.OrderingGrader

  defp question(answer), do: %{answer: answer}

  describe "grade/2" do
    test "perfect order returns correct: true and score: 10.0" do
      assert {:ok, %{correct: true, score: 10.0, score_max: 10.0}} =
               OrderingGrader.grade(question("A,B,C,D,E"), "A,B,C,D,E")
    end

    test "one adjacent swap returns correct: false and score > 0" do
      {:ok, result} = OrderingGrader.grade(question("A,B,C,D"), "A,C,B,D")
      refute result.correct
      assert result.score > 0.0
    end

    test "completely reversed order returns correct: false with LCS-based score" do
      # LCS of [A,B,C,D] and [D,C,B,A] is 1 (any single element)
      {:ok, result} = OrderingGrader.grade(question("A,B,C,D"), "D,C,B,A")
      refute result.correct
      # LCS = 1, total = 4, so score = 1/4 * 10 = 2.5
      assert_in_delta result.score, 2.5, 0.001
    end

    test "single element, correct" do
      assert {:ok, %{correct: true, score: 10.0}} =
               OrderingGrader.grade(question("A"), "A")
    end

    test "single element, wrong" do
      assert {:ok, %{correct: false, score: 0.0}} =
               OrderingGrader.grade(question("A"), "B")
    end

    test "score_max is 10.0" do
      assert {:ok, %{score_max: 10.0}} = OrderingGrader.grade(question("A,B"), "A,B")
    end

    test "feedback field is nil" do
      assert {:ok, %{feedback: nil}} = OrderingGrader.grade(question("A,B"), "A,B")
    end

    test "trims whitespace around elements" do
      assert {:ok, %{correct: true}} =
               OrderingGrader.grade(question("A, B, C"), " A , B , C ")
    end
  end
end
