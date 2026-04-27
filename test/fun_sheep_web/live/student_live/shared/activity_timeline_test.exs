defmodule FunSheepWeb.StudentLive.Shared.ActivityTimelineTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.Engagement.StudySession
  alias FunSheepWeb.StudentLive.Shared.ActivityTimeline

  defp session(attrs) do
    struct(
      StudySession,
      Map.merge(
        %{
          session_type: "practice",
          time_window: "morning",
          questions_attempted: 10,
          questions_correct: 8,
          duration_seconds: 600,
          completed_at: DateTime.utc_now(),
          xp_earned: 15
        },
        attrs
      )
    )
  end

  test "shows empty-state copy when fewer than 3 sessions" do
    html = render_component(&ActivityTimeline.timeline/1, sessions: [session(%{})])
    assert html =~ "Not enough activity yet"
  end

  test "renders rows for 3+ sessions" do
    sessions =
      for i <- 1..3 do
        session(%{completed_at: DateTime.add(DateTime.utc_now(), -i, :day)})
      end

    html = render_component(&ActivityTimeline.timeline/1, sessions: sessions)
    refute html =~ "Not enough activity yet"
    assert html =~ "Practice"
    assert html =~ "Morning"
  end

  describe "interpretation/3" do
    test "flags strong sessions when accuracy is well above rolling" do
      s = session(%{questions_attempted: 10, questions_correct: 10})
      assert ActivityTimeline.interpretation(s, 70.0, 600) =~ "Strong"
    end

    test "flags below-usual sessions" do
      s = session(%{questions_attempted: 10, questions_correct: 3})
      assert ActivityTimeline.interpretation(s, 70.0, 600) =~ "Below their usual"
    end

    test "flags short sessions" do
      s = session(%{questions_attempted: 10, questions_correct: 7, duration_seconds: 60})
      assert ActivityTimeline.interpretation(s, 70.0, 1000) =~ "Short session"
    end

    test "falls back gracefully on zero attempts" do
      s = session(%{questions_attempted: 0, questions_correct: 0})
      assert ActivityTimeline.interpretation(s, nil, nil) =~ "No questions attempted"
    end

    test "excellent accuracy absolute fallback when no rolling baseline" do
      s = session(%{questions_attempted: 10, questions_correct: 10})
      result = ActivityTimeline.interpretation(s, nil, nil)
      assert result =~ "Excellent"
    end

    test "solid accuracy absolute fallback (70-89%)" do
      s = session(%{questions_attempted: 10, questions_correct: 7})
      result = ActivityTimeline.interpretation(s, nil, nil)
      assert result =~ "Solid"
    end

    test "mixed result absolute fallback below 70%" do
      s = session(%{questions_attempted: 10, questions_correct: 5})
      result = ActivityTimeline.interpretation(s, nil, nil)
      assert result =~ "Mixed result"
    end

    test "returns session recorded for non-StudySession" do
      result = ActivityTimeline.interpretation(%{}, nil, nil)
      assert result =~ "Session recorded"
    end

    test "within normal range of rolling — no relative interpretation" do
      # accuracy is 75%, rolling is 70%, diff is +5 — within ±10 range
      s = session(%{questions_attempted: 100, questions_correct: 75})
      # Should not get strong or below-usual; falls through to duration or absolute
      result = ActivityTimeline.interpretation(s, 70.0, 600)
      # duration is 600 which is median — no short session message
      # absolute: 75% = solid
      assert result =~ "Solid"
    end
  end

  describe "timeline/1 — additional render paths" do
    test "renders empty state for 0 sessions" do
      html = render_component(&ActivityTimeline.timeline/1, sessions: [])
      assert html =~ "Not enough activity yet"
    end

    test "renders afternoon window pill" do
      sessions =
        for i <- 1..3 do
          session(%{
            time_window: "afternoon",
            completed_at: DateTime.add(DateTime.utc_now(), -i * 3600, :second)
          })
        end

      html = render_component(&ActivityTimeline.timeline/1, sessions: sessions)
      assert html =~ "Afternoon"
    end

    test "renders evening window pill" do
      sessions =
        for i <- 1..3 do
          session(%{time_window: "evening", completed_at: DateTime.add(DateTime.utc_now(), -i * 3600, :second)})
        end

      html = render_component(&ActivityTimeline.timeline/1, sessions: sessions)
      assert html =~ "Evening"
    end

    test "renders night (late night) window pill" do
      sessions =
        for i <- 1..3 do
          session(%{time_window: "night", completed_at: DateTime.add(DateTime.utc_now(), -i * 3600, :second)})
        end

      html = render_component(&ActivityTimeline.timeline/1, sessions: sessions)
      assert html =~ "Late night"
    end

    test "renders unknown window as generic session pill" do
      sessions =
        for i <- 1..3 do
          session(%{time_window: "cosmic", completed_at: DateTime.add(DateTime.utc_now(), -i * 3600, :second)})
        end

      html = render_component(&ActivityTimeline.timeline/1, sessions: sessions)
      assert html =~ "Session"
    end

    test "renders duration in seconds for short sessions < 60s" do
      sessions =
        for i <- 1..3 do
          session(%{duration_seconds: 45, completed_at: DateTime.add(DateTime.utc_now(), -i * 3600, :second)})
        end

      html = render_component(&ActivityTimeline.timeline/1, sessions: sessions)
      assert html =~ "45 s"
    end

    test "renders '0 min' for nil duration" do
      sessions =
        for i <- 1..3 do
          session(%{duration_seconds: nil, completed_at: DateTime.add(DateTime.utc_now(), -i * 3600, :second)})
        end

      html = render_component(&ActivityTimeline.timeline/1, sessions: sessions)
      assert html =~ "0 min"
    end

    test "renders XP when earned" do
      sessions =
        for i <- 1..3 do
          session(%{xp_earned: 50, completed_at: DateTime.add(DateTime.utc_now(), -i * 3600, :second)})
        end

      html = render_component(&ActivityTimeline.timeline/1, sessions: sessions)
      assert html =~ "50 XP"
    end

    test "renders different session types" do
      session_types = ["review", "assessment", "quick_test", "daily_challenge", "just_this", "custom_type"]

      for type <- session_types do
        sessions =
          for i <- 1..3 do
            session(%{session_type: type, completed_at: DateTime.add(DateTime.utc_now(), -i * 3600, :second)})
          end

        html = render_component(&ActivityTimeline.timeline/1, sessions: sessions)
        # Should render without error
        assert is_binary(html)
      end
    end

    test "groups sessions from yesterday" do
      sessions =
        for i <- 1..3 do
          session(%{
            completed_at: DateTime.add(DateTime.utc_now(), -(i + 24) * 3600, :second)
          })
        end

      html = render_component(&ActivityTimeline.timeline/1, sessions: sessions)
      assert html =~ "Yesterday"
    end

    test "handles nil completed_at gracefully" do
      sessions =
        for _ <- 1..3 do
          session(%{completed_at: nil})
        end

      html = render_component(&ActivityTimeline.timeline/1, sessions: sessions)
      assert html =~ "--:--"
    end

    test "renders 'Today' label for sessions completed today" do
      sessions =
        for i <- 1..3 do
          session(%{completed_at: DateTime.add(DateTime.utc_now(), -i * 600, :second)})
        end

      html = render_component(&ActivityTimeline.timeline/1, sessions: sessions)
      assert html =~ "Today"
    end

    test "renders date for sessions older than 7 days" do
      old_date = Date.add(Date.utc_today(), -10)

      sessions =
        for i <- 1..3 do
          dt =
            DateTime.new!(old_date, ~T[10:00:00], "Etc/UTC")
            |> DateTime.add(-i * 600, :second)

          session(%{completed_at: dt})
        end

      html = render_component(&ActivityTimeline.timeline/1, sessions: sessions)
      assert html =~ Date.to_string(old_date)
    end

    test "renders session label with course name" do
      sessions =
        for i <- 1..3 do
          session(%{
            session_type: "review",
            course: %{name: "Biology 101"},
            completed_at: DateTime.add(DateTime.utc_now(), -i * 600, :second)
          })
        end

      html = render_component(&ActivityTimeline.timeline/1, sessions: sessions)
      assert html =~ "Biology 101"
      assert html =~ "Review"
    end

    test "renders session label with nil session_type" do
      sessions =
        for i <- 1..3 do
          session(%{
            session_type: nil,
            completed_at: DateTime.add(DateTime.utc_now(), -i * 600, :second)
          })
        end

      html = render_component(&ActivityTimeline.timeline/1, sessions: sessions)
      assert html =~ "Study session"
    end
  end
end
