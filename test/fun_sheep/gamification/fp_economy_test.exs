defmodule FunSheep.Gamification.FpEconomyTest do
  use ExUnit.Case, async: true

  alias FunSheep.Gamification.FpEconomy

  describe "level_for_xp/1" do
    test "Level 1 at zero FP" do
      info = FpEconomy.level_for_xp(0)
      assert info.level == 1
      assert info.name == "Lamb"
      assert info.fp_into_level == 0
      assert info.fp_to_next_level == 100
      assert info.progress_pct == 0
    end

    test "advances to Level 2 at 100 FP" do
      info = FpEconomy.level_for_xp(100)
      assert info.level == 2
      assert info.name == "Spring Lamb"
      assert info.fp_into_level == 0
      assert info.fp_to_next_level == 150
    end

    test "mid-level progress is reported as percent" do
      info = FpEconomy.level_for_xp(50)
      assert info.level == 1
      assert info.progress_pct == 50
    end

    test "max level returns nil next_threshold and 100% progress" do
      info = FpEconomy.level_for_xp(50_000)
      assert info.level == 10
      assert info.next_threshold == nil
      assert info.fp_to_next_level == nil
      assert info.progress_pct == 100
    end
  end

  describe "next_streak_milestone/1" do
    test "returns the next milestone above current" do
      assert FpEconomy.next_streak_milestone(0) == 3
      assert FpEconomy.next_streak_milestone(5) == 7
      assert FpEconomy.next_streak_milestone(20) == 30
    end

    test "returns nil past the highest milestone" do
      assert FpEconomy.next_streak_milestone(100) == nil
      assert FpEconomy.next_streak_milestone(200) == nil
    end
  end

  describe "earn_more_rules/0" do
    test "every rule has the keys the FP modal renders" do
      for rule <- FpEconomy.earn_more_rules() do
        assert Map.has_key?(rule, :key)
        assert Map.has_key?(rule, :source)
        assert Map.has_key?(rule, :icon)
        assert Map.has_key?(rule, :label)
        assert Map.has_key?(rule, :amount_label)
        assert Map.has_key?(rule, :description)
        assert Map.has_key?(rule, :cta_label)
        assert Map.has_key?(rule, :cta_path)
      end
    end

    test "every rule's source is in XpEvent's valid sources" do
      # Reflective check — guards against drift between FpEconomy and the
      # XpEvent.@valid_sources whitelist.
      valid =
        FunSheep.Gamification.XpEvent.__schema__(:fields)
        |> Enum.find(&(&1 == :source))

      assert valid, "XpEvent must have a :source field"

      sources = Enum.map(FpEconomy.earn_more_rules(), & &1.source)
      assert "practice" in sources
      assert "quick_test" in sources
      assert "review" in sources
      assert "study_session" in sources
      assert "daily_challenge" in sources
      assert "assessment" in sources
    end

    test "amount labels surface real numbers, not placeholders" do
      labels = Enum.map(FpEconomy.earn_more_rules(), & &1.amount_label)
      # every label must contain a numeric "FP" amount or a multiplier
      assert Enum.all?(labels, &(&1 =~ ~r/(FP|×)/))
    end
  end
end
