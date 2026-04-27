defmodule FunSheepWeb.StudentLive.Shared.Phase2ComponentsTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheepWeb.StudentLive.Shared.{ForecastCard, PeerComparison, PercentileTrend}

  describe "PercentileTrend.trend/1" do
    test "renders empty state when fewer than 2 snapshots" do
      html = render_component(&PercentileTrend.trend/1, history: [])
      assert html =~ "Check back next week"
    end

    test "renders sparkline and target" do
      history =
        for i <- 1..4,
            do: %{
              week_start: Date.add(Date.utc_today(), -7 * (5 - i)),
              percentile: 40 + i * 10,
              score: 60 + i,
              rank: 5,
              total: 25
            }

      html =
        render_component(&PercentileTrend.trend/1,
          history: history,
          current_percentile: 80,
          target_readiness: 85,
          days_to_test: 14
        )

      refute html =~ "Check back next week"
      assert html =~ "polyline"
      assert html =~ "85%"
      assert html =~ "14"
    end
  end

  describe "ForecastCard.card/1" do
    test "renders :no_target empty state" do
      html =
        render_component(&ForecastCard.card/1,
          forecast: %{status: :insufficient_data, reason: :no_target}
        )

      assert html =~ "Set a target score"
    end

    test "renders projection and minute delta when status is :ok" do
      html =
        render_component(&ForecastCard.card/1,
          forecast: %{
            status: :ok,
            projected_readiness: 82.4,
            target: 90,
            gap: 7.6,
            days_to_test: 20,
            current_daily_minutes: 25,
            recommended_daily_minutes: 40,
            minutes_delta: 15,
            history_days: 21,
            confidence: :wide_range
          }
        )

      assert html =~ "82.4%"
      assert html =~ "90%"
      assert html =~ "+7.6"
      assert html =~ "15"
      assert html =~ "Wide range"
    end

    test "renders 'on track' when gap is negative" do
      html =
        render_component(&ForecastCard.card/1,
          forecast: %{
            status: :ok,
            projected_readiness: 92.0,
            target: 85,
            gap: -7.0,
            days_to_test: 10,
            current_daily_minutes: 30,
            recommended_daily_minutes: 30,
            minutes_delta: 0,
            history_days: 30,
            confidence: :wide_range
          }
        )

      assert html =~ "On track"
    end
  end

  describe "PeerComparison.card/1" do
    test "small cohort message" do
      html =
        render_component(&PeerComparison.card/1,
          bands: %{status: :small_cohort, size: 7},
          student_readiness: 60
        )

      assert html =~ "Small cohort"
      refute html =~ "P25"
    end

    test "full bands render with student's band highlighted at p75" do
      bands = %{status: :ok, size: 30, p25: 40.0, p50: 60.0, p75: 80.0, p90: 92.0}

      html =
        render_component(&PeerComparison.card/1, bands: bands, student_readiness: 82)

      assert html =~ "P25"
      assert html =~ "P50"
      assert html =~ "P75"
      assert html =~ "P90"
      assert html =~ "top 25%"
    end

    test "student readiness at p90 shows top 10% copy" do
      bands = %{status: :ok, size: 30, p25: 40.0, p50: 60.0, p75: 80.0, p90: 90.0}

      html =
        render_component(&PeerComparison.card/1, bands: bands, student_readiness: 95)

      assert html =~ "top 10%"
    end

    test "student readiness at p50 shows above median copy" do
      bands = %{status: :ok, size: 30, p25: 40.0, p50: 60.0, p75: 80.0, p90: 90.0}

      html =
        render_component(&PeerComparison.card/1, bands: bands, student_readiness: 65)

      assert html =~ "above the median"
    end

    test "student readiness at p25 shows above lower quartile copy" do
      bands = %{status: :ok, size: 30, p25: 40.0, p50: 60.0, p75: 80.0, p90: 90.0}

      html =
        render_component(&PeerComparison.card/1, bands: bands, student_readiness: 45)

      assert html =~ "above the lower quartile"
    end

    test "student readiness below p25 shows room to grow copy" do
      bands = %{status: :ok, size: 30, p25: 40.0, p50: 60.0, p75: 80.0, p90: 90.0}

      html =
        render_component(&PeerComparison.card/1, bands: bands, student_readiness: 30)

      assert html =~ "room to grow"
    end

    test "student_readiness nil suppresses mine copy" do
      bands = %{status: :ok, size: 30, p25: 40.0, p50: 60.0, p75: 80.0, p90: 90.0}

      html =
        render_component(&PeerComparison.card/1, bands: bands, student_readiness: nil)

      assert html =~ "P25"
      refute html =~ "top 10%"
      refute html =~ "above"
    end

    test "unknown status shows not ready copy" do
      html =
        render_component(&PeerComparison.card/1,
          bands: %{status: :loading},
          student_readiness: 70
        )

      assert html =~ "Peer comparison isn&#39;t ready yet"
    end
  end

  describe "ForecastCard.card/1 — additional states" do
    test "renders 'small push' copy when minutes_delta is zero and gap > 0" do
      html =
        render_component(&ForecastCard.card/1,
          forecast: %{
            status: :ok,
            projected_readiness: 80.0,
            target: 90,
            gap: 10.0,
            days_to_test: 15,
            current_daily_minutes: 30,
            recommended_daily_minutes: 30,
            minutes_delta: 0,
            history_days: 14,
            confidence: :tight
          }
        )

      assert html =~ "small daily push"
      assert html =~ "Tight range"
    end

    test "renders :no_readiness_history empty state" do
      html =
        render_component(&ForecastCard.card/1,
          forecast: %{status: :insufficient_data, reason: :no_readiness_history}
        )

      assert html =~ "Run an assessment"
    end

    test "renders :single_snapshot empty state" do
      html =
        render_component(&ForecastCard.card/1,
          forecast: %{status: :insufficient_data, reason: :single_snapshot}
        )

      assert html =~ "One readiness point"
    end

    test "renders :short_history empty state" do
      html =
        render_component(&ForecastCard.card/1,
          forecast: %{status: :insufficient_data, reason: :short_history}
        )

      assert html =~ "Fewer than two weeks"
    end

    test "renders :test_in_past empty state" do
      html =
        render_component(&ForecastCard.card/1,
          forecast: %{status: :insufficient_data, reason: :test_in_past}
        )

      assert html =~ "test date has already passed"
    end

    test "renders :no_schedule empty state" do
      html =
        render_component(&ForecastCard.card/1,
          forecast: %{status: :insufficient_data, reason: :no_schedule}
        )

      assert html =~ "No upcoming test"
    end

    test "renders unknown reason with fallback copy" do
      html =
        render_component(&ForecastCard.card/1,
          forecast: %{status: :insufficient_data, reason: :something_else}
        )

      assert html =~ "Forecast not available yet"
    end

    test "renders unknown status fallback" do
      html =
        render_component(&ForecastCard.card/1,
          forecast: %{status: :unknown}
        )

      assert html =~ "Forecast not available yet"
    end

    test "renders negative gap as green" do
      html =
        render_component(&ForecastCard.card/1,
          forecast: %{
            status: :ok,
            projected_readiness: 95.0,
            target: 85,
            gap: -10.0,
            days_to_test: 5,
            current_daily_minutes: 40,
            recommended_daily_minutes: 30,
            minutes_delta: -10,
            history_days: 28,
            confidence: :tight
          }
        )

      assert html =~ "-10"
      assert html =~ "On track"
    end

    test "unknown confidence renders without confidence text" do
      html =
        render_component(&ForecastCard.card/1,
          forecast: %{
            status: :ok,
            projected_readiness: 80.0,
            target: 90,
            gap: 10.0,
            days_to_test: 30,
            current_daily_minutes: 20,
            recommended_daily_minutes: 40,
            minutes_delta: 20,
            history_days: 7,
            confidence: :unknown_confidence
          }
        )

      assert html =~ "80.0%"
      # confidence_copy returns empty string for unknown confidence
      refute html =~ "Tight range"
      refute html =~ "Wide range"
    end
  end
end
