defmodule FunSheep.Questions.NumericGraderTest do
  use ExUnit.Case, async: true

  alias FunSheep.Questions.NumericGrader

  defp question(answer, opts \\ %{}), do: %{answer: answer, options: opts}

  describe "grade/2" do
    test "exact match is correct with score 10.0" do
      assert {:ok, %{correct: true, score: 10.0, score_max: 10.0}} =
               NumericGrader.grade(question("126"), "126")
    end

    test "exact match with float strings" do
      assert {:ok, %{correct: true, score: 10.0}} =
               NumericGrader.grade(question("3.14"), "3.14")
    end

    test "within tolerance is correct" do
      # 1% tolerance: 126 ± 1.26
      assert {:ok, %{correct: true}} =
               NumericGrader.grade(question("126", %{"tolerance_pct" => 1}), "127")
    end

    test "just outside tolerance is incorrect" do
      # 1% tolerance: 126 ± 1.26, so 128 is outside
      assert {:ok, %{correct: false, score: 0.0}} =
               NumericGrader.grade(question("126", %{"tolerance_pct" => 1}), "128")
    end

    test "zero correct answer: only zero is correct" do
      assert {:ok, %{correct: true}} =
               NumericGrader.grade(question("0"), "0")
    end

    test "zero correct answer: nonzero is incorrect regardless of tolerance" do
      assert {:ok, %{correct: false}} =
               NumericGrader.grade(question("0", %{"tolerance_pct" => 10}), "1")
    end

    test "incorrect answer returns score: 0.0" do
      assert {:ok, %{correct: false, score: 0.0}} =
               NumericGrader.grade(question("100"), "50")
    end

    test "non-numeric correct answer returns error" do
      assert {:error, :invalid_number_format} =
               NumericGrader.grade(question("not-a-number"), "42")
    end

    test "non-numeric student answer returns error" do
      assert {:error, :invalid_number_format} =
               NumericGrader.grade(question("42"), "not-a-number")
    end

    test "works without options field (no tolerance)" do
      assert {:ok, %{correct: true}} =
               NumericGrader.grade(%{answer: "42"}, "42")
    end

    test "feedback is nil" do
      assert {:ok, %{feedback: nil}} = NumericGrader.grade(question("1"), "1")
    end
  end
end
