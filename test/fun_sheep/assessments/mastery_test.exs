defmodule FunSheep.Assessments.MasteryTest do
  @moduledoc """
  Pure-function tests for the mastery rule defined in North Star I-9:
  N correct in a row at or above medium difficulty.
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

  describe "mastered?/2" do
    test "true when the last 3 are all correct at medium+" do
      attempts = [
        attempt(false, :easy, 0),
        attempt(true, :easy, 1),
        attempt(true, :medium, 2),
        attempt(true, :medium, 3),
        attempt(true, :hard, 4)
      ]

      assert Mastery.mastered?(attempts)
    end

    test "false when the last 3 contain an easy correct" do
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

    test "false with fewer than N attempts — no mastery on thin evidence (I-15)" do
      attempts = [attempt(true, :medium, 0), attempt(true, :medium, 1)]
      refute Mastery.mastered?(attempts)
    end

    test "works with string difficulty (DB representation)" do
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

    test "honors tunable streak length" do
      attempts = [
        attempt(true, :medium, 0),
        attempt(true, :medium, 1)
      ]

      refute Mastery.mastered?(attempts, 3)
      assert Mastery.mastered?(attempts, 2)
    end
  end

  describe "status/2" do
    test "insufficient_data when <2 attempts" do
      assert Mastery.status([]) == :insufficient_data
      assert Mastery.status([attempt(true, :medium)]) == :insufficient_data
    end

    test "weak when correct ratio is below default 0.4" do
      attempts =
        Enum.map(0..4, fn i -> attempt(i == 0, :medium, i) end)

      # 1/5 correct = 20%, < 40% threshold
      assert Mastery.status(attempts) == :weak
    end

    test "mastered when streak satisfied" do
      attempts =
        Enum.map(0..2, fn i -> attempt(true, :medium, i) end)

      assert Mastery.status(attempts) == :mastered
    end

    test "probing when neither weak nor mastered" do
      attempts = [
        attempt(true, :medium, 0),
        attempt(false, :medium, 1),
        attempt(true, :easy, 2)
      ]

      assert Mastery.status(attempts) == :probing
    end
  end
end
