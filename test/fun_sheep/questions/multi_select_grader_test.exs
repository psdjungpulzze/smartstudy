defmodule FunSheep.Questions.MultiSelectGraderTest do
  use ExUnit.Case, async: true

  alias FunSheep.Questions.MultiSelectGrader

  defp question(answer), do: %{answer: answer}

  describe "grade/2" do
    test "exact match returns correct: true and score: 10.0" do
      assert {:ok, %{correct: true, score: 10.0, score_max: 10.0}} =
               MultiSelectGrader.grade(question("a,b,c"), "a,b,c")
    end

    test "order-independent: same selections in different order is correct" do
      assert {:ok, %{correct: true, score: 10.0}} =
               MultiSelectGrader.grade(question("a,c"), "c,a")
    end

    test "partial match returns correct: false and proportional score" do
      # 2 of 4 correct = 5.0
      assert {:ok, %{correct: false, score: 5.0}} =
               MultiSelectGrader.grade(question("a,b,c,d"), "a,b,x,y")
    end

    test "no match returns correct: false and score: 0.0" do
      assert {:ok, %{correct: false, score: 0.0}} =
               MultiSelectGrader.grade(question("a,b"), "x,y")
    end

    test "single correct option: full credit when exact" do
      assert {:ok, %{correct: true, score: 10.0}} =
               MultiSelectGrader.grade(question("a"), "a")
    end

    test "single correct option: no credit when wrong" do
      assert {:ok, %{correct: false, score: 0.0}} =
               MultiSelectGrader.grade(question("a"), "b")
    end

    test "feedback field is nil" do
      assert {:ok, %{feedback: nil}} = MultiSelectGrader.grade(question("a"), "a")
    end

    test "trims whitespace around comma-separated values" do
      assert {:ok, %{correct: true}} =
               MultiSelectGrader.grade(question("a, b, c"), " a , b ,c ")
    end
  end
end
