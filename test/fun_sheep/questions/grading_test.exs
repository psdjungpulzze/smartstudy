defmodule FunSheep.Questions.GradingTest do
  @moduledoc """
  Pinpoint coverage for the grading regression that, before this fix, marked
  every correctly-selected multiple-choice answer as INCORRECT in production
  (LiveViews submit the option *key* like "c"; the grader compared it as a
  string against the option *text*). Verified the bug end-to-end on dev.
  See `FunSheep.Questions.Grading` moduledoc for the I-9 / I-15 implications.
  """

  use ExUnit.Case, async: true

  alias FunSheep.Questions.Grading

  defp mc_question do
    %{
      question_type: :multiple_choice,
      answer: "Mitochondria",
      options: %{
        "a" => "Nucleus",
        "b" => "Mitochondria",
        "c" => "Ribosome",
        "d" => "Golgi"
      }
    }
  end

  describe "multiple choice" do
    test "selecting the option KEY whose text matches the answer is correct" do
      # The pre-fix bug: this returned false because "b" != "Mitochondria"
      assert Grading.correct?(mc_question(), "b")
    end

    test "selecting the option TEXT (matching the answer) is correct" do
      assert Grading.correct?(mc_question(), "Mitochondria")
    end

    test "case and whitespace insensitive on text" do
      assert Grading.correct?(mc_question(), "  mitochondria  ")
    end

    test "wrong key is incorrect" do
      refute Grading.correct?(mc_question(), "a")
    end

    test "wrong text is incorrect" do
      refute Grading.correct?(mc_question(), "Nucleus")
    end

    test "key not in options is incorrect (no random promotion)" do
      refute Grading.correct?(mc_question(), "z")
    end

    test "answer-stored-as-key shape: question.answer is the key, user submits the key" do
      # Some questions may be authored with the answer as the option key.
      # Both the key and the text must work for the user.
      q = %{
        question_type: :multiple_choice,
        answer: "b",
        options: %{"a" => "Nucleus", "b" => "Mitochondria"}
      }

      assert Grading.correct?(q, "b")
    end
  end

  describe "true/false" do
    test "case-insensitive direct match" do
      q = %{question_type: :true_false, answer: "True", options: %{}}
      assert Grading.correct?(q, "true")
      assert Grading.correct?(q, "TRUE")
      refute Grading.correct?(q, "false")
    end
  end

  describe "short answer / free response" do
    test "trim + downcase comparison" do
      q = %{question_type: :short_answer, answer: "Glycolysis"}
      assert Grading.correct?(q, "glycolysis")
      assert Grading.correct?(q, "  Glycolysis ")
      refute Grading.correct?(q, "Krebs cycle")
    end
  end

  describe "edge cases" do
    test "nil submission is never correct" do
      refute Grading.correct?(mc_question(), nil)
    end

    test "empty string submission is never correct" do
      refute Grading.correct?(mc_question(), "")
    end

    test "MC question with nil options falls back to plain string compare" do
      q = %{question_type: :multiple_choice, answer: "Mitochondria", options: nil}
      assert Grading.correct?(q, "Mitochondria")
      refute Grading.correct?(q, "b")
    end
  end
end
