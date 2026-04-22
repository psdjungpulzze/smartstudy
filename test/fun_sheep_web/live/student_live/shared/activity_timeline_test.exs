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
  end
end
