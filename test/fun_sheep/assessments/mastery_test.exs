defmodule FunSheep.Assessments.MasteryTest do
  @moduledoc """
  Tests the N-correct-in-a-row-at-medium+ mastery rule (I-9) and
  the confidence-based streak restriction (I-17).
  """

  use ExUnit.Case, async: true

  alias FunSheep.Assessments.Mastery

  defp attempt(is_correct, difficulty, minute_offset \\ 0) do
    %{
      is_correct: is_correct,
      difficulty: difficulty,
      inserted_at: DateTime.add(~U[2026-04-21 00:00:00Z], minute_offset, :minute)
    }
  end

  defp attempt_c(is_correct, difficulty, confidence, minute_offset \\ 0) do
    %{
      is_correct: is_correct,
      difficulty: difficulty,
      confidence: confidence,
      inserted_at: DateTime.add(~U[2026-04-21 00:00:00Z], minute_offset, :minute)
    }
  end

  describe "mastered?/2" do
    test "true when the last 3 are correct at medium+" do
      attempts = [
        attempt(false, :easy, 0),
        attempt(true, :easy, 1),
        attempt(true, :medium, 2),
        attempt(true, :medium, 3),
        attempt(true, :hard, 4)
      ]

      assert Mastery.mastered?(attempts)
    end

    test "false when any of the last 3 is easy" do
      attempts = [
        attempt(true, :medium, 0),
        attempt(true, :easy, 1),
        attempt(true, :medium, 2)
      ]

      refute Mastery.mastered?(attempts)
    end

    test "false when any of the last 3 is wrong" do
      attempts = [
        attempt(true, :medium, 0),
        attempt(true, :medium, 1),
        attempt(false, :medium, 2)
      ]

      refute Mastery.mastered?(attempts)
    end

    test "false with fewer than N attempts" do
      refute Mastery.mastered?([attempt(true, :medium, 0), attempt(true, :medium, 1)])
    end

    test "works with DB string difficulty" do
      attempts = [
        %{
          is_correct: true,
          difficulty_at_attempt: "medium",
          inserted_at: ~U[2026-04-21 00:00:00Z]
        },
        %{is_correct: true, difficulty_at_attempt: "hard", inserted_at: ~U[2026-04-21 00:01:00Z]},
        %{
          is_correct: true,
          difficulty_at_attempt: "medium",
          inserted_at: ~U[2026-04-21 00:02:00Z]
        }
      ]

      assert Mastery.mastered?(attempts)
    end

    test "honors tunable streak" do
      attempts = [attempt(true, :medium, 0), attempt(true, :medium, 1)]
      refute Mastery.mastered?(attempts, 3)
      assert Mastery.mastered?(attempts, 2)
    end
  end

  describe "mastered?/2 — confidence (I-17)" do
    test "correct + i_know counts toward mastery streak" do
      attempts = [
        attempt_c(true, :medium, :i_know, 0),
        attempt_c(true, :medium, :i_know, 1),
        attempt_c(true, :hard, :i_know, 2)
      ]

      assert Mastery.mastered?(attempts)
    end

    test "correct + not_sure does NOT count toward mastery streak" do
      attempts = [
        attempt_c(true, :medium, :i_know, 0),
        attempt_c(true, :medium, :i_know, 1),
        attempt_c(true, :hard, :not_sure, 2)
      ]

      refute Mastery.mastered?(attempts)
    end

    test "correct + dont_know (lucky guess) does NOT count toward mastery streak" do
      attempts = [
        attempt_c(true, :medium, :i_know, 0),
        attempt_c(true, :medium, :i_know, 1),
        attempt_c(true, :hard, :dont_know, 2)
      ]

      refute Mastery.mastered?(attempts)
    end

    test "nil confidence (legacy) falls back to is_correct for streak" do
      attempts = [
        attempt_c(true, :medium, nil, 0),
        attempt_c(true, :medium, nil, 1),
        attempt_c(true, :hard, nil, 2)
      ]

      assert Mastery.mastered?(attempts)
    end

    test "mixed legacy and confident — trailing i_know streak qualifies" do
      attempts = [
        attempt(true, :medium, 0),
        attempt_c(true, :medium, :i_know, 1),
        attempt_c(true, :hard, :i_know, 2),
        attempt_c(true, :medium, :i_know, 3)
      ]

      assert Mastery.mastered?(attempts)
    end
  end

  describe "effective_correctness/2" do
    test "correct + i_know is :strong" do
      assert Mastery.effective_correctness(true, :i_know) == :strong
    end

    test "correct + not_sure is :partial" do
      assert Mastery.effective_correctness(true, :not_sure) == :partial
    end

    test "correct + dont_know is :lucky_guess" do
      assert Mastery.effective_correctness(true, :dont_know) == :lucky_guess
    end

    test "incorrect + i_know is :overconfident" do
      assert Mastery.effective_correctness(false, :i_know) == :overconfident
    end

    test "incorrect + not_sure is :weak" do
      assert Mastery.effective_correctness(false, :not_sure) == :weak
    end

    test "incorrect + dont_know is :weak" do
      assert Mastery.effective_correctness(false, :dont_know) == :weak
    end

    test "any correctness + nil confidence is :binary (legacy path)" do
      assert Mastery.effective_correctness(true, nil) == :binary
      assert Mastery.effective_correctness(false, nil) == :binary
    end
  end

  describe "status/2" do
    test "insufficient_data when <2 attempts" do
      assert Mastery.status([]) == :insufficient_data
      assert Mastery.status([attempt(true, :medium)]) == :insufficient_data
    end

    test "weak when correct ratio below threshold" do
      attempts = Enum.map(0..4, fn i -> attempt(i == 0, :medium, i) end)
      assert Mastery.status(attempts) == :weak
    end

    test "mastered when streak satisfied" do
      attempts = Enum.map(0..2, fn i -> attempt(true, :medium, i) end)
      assert Mastery.status(attempts) == :mastered
    end

    test "probing otherwise" do
      attempts = [
        attempt(true, :medium, 0),
        attempt(false, :medium, 1),
        attempt(true, :easy, 2)
      ]

      assert Mastery.status(attempts) == :probing
    end

    test "not mastered when streak correct but confidence is not_sure (I-17)" do
      attempts = [
        attempt_c(true, :medium, :not_sure, 0),
        attempt_c(true, :medium, :not_sure, 1),
        attempt_c(true, :hard, :not_sure, 2)
      ]

      refute Mastery.status(attempts) == :mastered
    end
  end
end
