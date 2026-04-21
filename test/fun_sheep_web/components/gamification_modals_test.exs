defmodule FunSheepWeb.GamificationModalsTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias FunSheepWeb.GamificationModals

  describe "streak_modal/1" do
    test "renders loading skeleton when summary is nil" do
      html = render_component(&GamificationModals.streak_modal/1, %{summary: nil})
      assert html =~ "Your Streak"
      assert html =~ "animate-pulse"
    end

    test "renders streak detail with heatmap and CTA when summary is provided" do
      summary = %{
        current_streak: 5,
        longest_streak: 12,
        wool_level: 2,
        last_activity_date: Date.utc_today(),
        streak_frozen_until: nil,
        status: :safe,
        studied_today: true,
        next_milestone: 7,
        milestones_hit: 1,
        milestones_total: 5,
        heatmap:
          for offset <- 29..0//-1 do
            %{date: Date.add(Date.utc_today(), -offset), active: rem(offset, 2) == 0}
          end
      }

      html = render_component(&GamificationModals.streak_modal/1, %{summary: summary})

      assert html =~ "Your Streak"
      assert html =~ "5"
      # personal best
      assert html =~ "12"
      # next milestone delta
      assert html =~ "🔥 7-day streak"
      # safe banner
      assert html =~ "Streak safe"
      # CTA
      assert html =~ "Keep going"
    end

    test "renders at-risk loss-aversion copy" do
      summary = %{
        current_streak: 3,
        longest_streak: 3,
        wool_level: 2,
        last_activity_date: Date.add(Date.utc_today(), -1),
        streak_frozen_until: nil,
        status: :at_risk,
        studied_today: false,
        next_milestone: 7,
        milestones_hit: 1,
        milestones_total: 5,
        heatmap:
          for(
            offset <- 29..0//-1,
            do: %{date: Date.add(Date.utc_today(), -offset), active: false}
          )
      }

      html = render_component(&GamificationModals.streak_modal/1, %{summary: summary})
      assert html =~ "Practice today or lose your 3-day streak"
      assert html =~ "Save your streak"
    end
  end

  describe "fp_modal/1" do
    test "renders loading skeleton when summary is nil" do
      html = render_component(&GamificationModals.fp_modal/1, %{summary: nil})
      assert html =~ "Fleece Points"
      assert html =~ "animate-pulse"
    end

    test "renders FP body with breakdown, recent events, and earn-more rules" do
      now = DateTime.utc_now()

      summary = %{
        total_xp: 250,
        xp_today: 30,
        xp_this_week: 80,
        week_chart:
          for offset <- 6..0//-1 do
            %{
              date: Date.add(Date.utc_today(), -offset),
              amount: if(offset == 0, do: 30, else: 10)
            }
          end,
        source_breakdown: [
          %{source: "practice", amount: 150, count: 15},
          %{source: "quick_test", amount: 100, count: 4}
        ],
        recent_events: [
          %FunSheep.Gamification.XpEvent{source: "practice", amount: 10, inserted_at: now},
          %FunSheep.Gamification.XpEvent{source: "quick_test", amount: 25, inserted_at: now}
        ],
        level: %{
          level: 3,
          name: "Yearling",
          current_threshold: 250,
          next_threshold: 500,
          fp_into_level: 0,
          fp_to_next_level: 250,
          progress_pct: 0
        },
        earn_more: FunSheep.Gamification.FpEconomy.earn_more_rules(),
        today: Date.utc_today()
      }

      html = render_component(&GamificationModals.fp_modal/1, %{summary: summary})

      assert html =~ "250"
      assert html =~ "Yearling"
      assert html =~ "Level 3"
      assert html =~ "Where your FP came from"
      assert html =~ "Practice"
      assert html =~ "Quick Test"
      assert html =~ "Earn more FP"
      # Rules carry real amount labels (no placeholders)
      assert html =~ "+10 FP per correct"
    end
  end

  describe "open_*_modal_js/0" do
    test "open_streak_modal_js returns a JS chain pushing the right event" do
      js = GamificationModals.open_streak_modal_js()
      assert is_struct(js, Phoenix.LiveView.JS)
      json = Jason.encode!(js.ops)
      assert json =~ "open_streak_detail"
      assert json =~ "#streak-modal"
    end

    test "open_fp_modal_js returns a JS chain pushing the right event" do
      js = GamificationModals.open_fp_modal_js()
      json = Jason.encode!(js.ops)
      assert json =~ "open_fp_detail"
      assert json =~ "#fp-modal"
    end
  end
end
