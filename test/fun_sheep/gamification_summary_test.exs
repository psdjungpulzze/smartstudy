defmodule FunSheep.GamificationSummaryTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.{ContentFixtures, Gamification}

  setup do
    user_role = ContentFixtures.create_user_role()
    {:ok, user_role: user_role}
  end

  describe "streak_summary/1" do
    test "returns a 30-cell heatmap with no activity for a new user", %{user_role: ur} do
      summary = Gamification.streak_summary(ur.id)

      assert summary.current_streak == 0
      assert summary.longest_streak == 0
      assert summary.status == :no_streak
      assert length(summary.heatmap) == 30
      assert Enum.all?(summary.heatmap, &(&1.active == false))
      assert summary.next_milestone == 3
    end

    test "marks today as active after an XP event today", %{user_role: ur} do
      {:ok, _} = Gamification.award_xp(ur.id, 10, "practice")
      {:ok, _} = Gamification.record_activity(ur.id)

      summary = Gamification.streak_summary(ur.id)
      today = Date.utc_today()
      today_cell = Enum.find(summary.heatmap, &(&1.date == today))

      assert today_cell.active
      assert summary.studied_today
      assert summary.status == :safe
      assert summary.current_streak >= 1
    end

    test "returns empty summary for an invalid user_role_id" do
      summary = Gamification.streak_summary("not-a-uuid")
      assert summary.current_streak == 0
      assert length(summary.heatmap) == 30
    end
  end

  describe "fp_summary/1" do
    test "returns zeroed summary for a new user", %{user_role: ur} do
      summary = Gamification.fp_summary(ur.id)

      assert summary.total_xp == 0
      assert summary.xp_today == 0
      assert summary.xp_this_week == 0
      assert length(summary.week_chart) == 7
      assert summary.source_breakdown == []
      assert summary.recent_events == []
      assert summary.level.level == 1
      assert is_list(summary.earn_more) and summary.earn_more != []
    end

    test "aggregates real XP events by source and day", %{user_role: ur} do
      {:ok, _} = Gamification.award_xp(ur.id, 10, "practice")
      {:ok, _} = Gamification.award_xp(ur.id, 10, "practice")
      {:ok, _} = Gamification.award_xp(ur.id, 25, "quick_test")

      summary = Gamification.fp_summary(ur.id)

      assert summary.total_xp == 45
      assert summary.xp_today == 45

      breakdown = Map.new(summary.source_breakdown, &{&1.source, &1})
      assert breakdown["practice"].amount == 20
      assert breakdown["practice"].count == 2
      assert breakdown["quick_test"].amount == 25
      assert breakdown["quick_test"].count == 1

      today = Date.utc_today()
      today_bar = Enum.find(summary.week_chart, &(&1.date == today))
      assert today_bar.amount == 45

      assert length(summary.recent_events) == 3
    end

    test "level reflects total XP", %{user_role: ur} do
      {:ok, _} = Gamification.award_xp(ur.id, 100, "practice")
      summary = Gamification.fp_summary(ur.id)
      assert summary.level.level == 2
    end

    test "returns empty summary for invalid id" do
      summary = Gamification.fp_summary("nope")
      assert summary.total_xp == 0
      assert length(summary.week_chart) == 7
    end
  end

  describe "daily_xp/2" do
    test "fills missing days with zero", %{user_role: ur} do
      {:ok, _} = Gamification.award_xp(ur.id, 30, "practice")

      chart = Gamification.daily_xp(ur.id, 7)
      assert length(chart) == 7

      today = Date.utc_today()
      assert Enum.find(chart, &(&1.date == today)).amount == 30
      assert Enum.count(chart, &(&1.amount == 0)) == 6
    end
  end

  describe "review and study_session XP events now persist" do
    # Regression test for the @valid_sources gap that was fixed alongside the
    # streak/FP modal feature — these two sources used to be silently dropped.
    test "review source is accepted", %{user_role: ur} do
      assert {:ok, _} = Gamification.award_xp(ur.id, 10, "review")
    end

    test "study_session source is accepted", %{user_role: ur} do
      assert {:ok, _} = Gamification.award_xp(ur.id, 25, "study_session")
    end
  end
end
