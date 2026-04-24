defmodule FunSheep.Questions.ClozeGraderTest do
  use ExUnit.Case, async: true

  alias FunSheep.Questions.ClozeGrader

  defp question(answer_map) do
    %{answer: Jason.encode!(answer_map)}
  end

  defp given(answer_map), do: Jason.encode!(answer_map)

  describe "grade/2" do
    test "all blanks correct returns correct: true and score: 10.0" do
      q = question(%{"1" => "photosynthesis", "2" => "chlorophyll"})

      assert {:ok, %{correct: true, score: 10.0, score_max: 10.0}} =
               ClozeGrader.grade(q, given(%{"1" => "photosynthesis", "2" => "chlorophyll"}))
    end

    test "some blanks correct gives proportional partial credit" do
      # 1 of 2 correct = 5.0
      q = question(%{"1" => "mitosis", "2" => "meiosis"})

      assert {:ok, %{correct: false, score: 5.0}} =
               ClozeGrader.grade(q, given(%{"1" => "mitosis", "2" => "wrong"}))
    end

    test "no blanks correct returns score: 0.0" do
      q = question(%{"1" => "nucleus", "2" => "ribosome"})

      assert {:ok, %{correct: false, score: 0.0}} =
               ClozeGrader.grade(q, given(%{"1" => "wrong1", "2" => "wrong2"}))
    end

    test "matching is case-insensitive" do
      q = question(%{"1" => "Photosynthesis"})

      assert {:ok, %{correct: true}} =
               ClozeGrader.grade(q, given(%{"1" => "photosynthesis"}))
    end

    test "case-insensitive both ways" do
      q = question(%{"1" => "chlorophyll"})

      assert {:ok, %{correct: true}} =
               ClozeGrader.grade(q, given(%{"1" => "CHLOROPHYLL"}))
    end

    test "invalid JSON in correct answer returns error" do
      assert {:error, :invalid_answer_format} =
               ClozeGrader.grade(%{answer: "not-json"}, given(%{"1" => "x"}))
    end

    test "invalid JSON in student answer returns error" do
      q = question(%{"1" => "x"})
      assert {:error, :invalid_answer_format} = ClozeGrader.grade(q, "not-json")
    end

    test "feedback field is nil" do
      q = question(%{"1" => "x"})
      assert {:ok, %{feedback: nil}} = ClozeGrader.grade(q, given(%{"1" => "x"}))
    end
  end
end
