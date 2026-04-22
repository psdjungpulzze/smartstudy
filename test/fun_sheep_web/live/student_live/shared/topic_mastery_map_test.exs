defmodule FunSheepWeb.StudentLive.Shared.TopicMasteryMapTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheepWeb.StudentLive.Shared.TopicMasteryMap

  test "mastery_map empty when grid is empty" do
    html = render_component(&TopicMasteryMap.mastery_map/1, grid: [])
    assert html =~ "No upcoming test has chapter scope set yet"
  end

  test "mastery_map renders topic cells with accuracy and attempt count" do
    grid = [
      %{
        chapter_id: "ch-1",
        chapter_name: "Fractions",
        topics: [
          %{
            section_id: "s-1",
            section_name: "Adding",
            accuracy: 82.0,
            attempts_count: 11,
            correct_count: 9,
            status: :mastered
          }
        ]
      }
    ]

    html =
      render_component(&TopicMasteryMap.mastery_map/1,
        grid: grid,
        test_name: "Mid-term"
      )

    assert html =~ "Fractions"
    assert html =~ "Adding"
    assert html =~ "82%"
    assert html =~ "11"
    assert html =~ "Mid-term"
    assert html =~ "phx-click=\"topic_drill\""
    assert html =~ ~s(phx-value-section-id="s-1")
  end

  test "drill_modal renders attempts and trend" do
    attempt = %FunSheep.Questions.QuestionAttempt{
      is_correct: true,
      time_taken_seconds: 15,
      inserted_at: DateTime.utc_now(),
      question: %FunSheep.Questions.Question{content: "What is 2+2?"}
    }

    trend = [%{date: Date.utc_today(), accuracy: 85.0, attempts: 5}]

    html =
      render_component(&TopicMasteryMap.drill_modal/1,
        topic_name: "Adding",
        chapter_name: "Fractions",
        attempts: [attempt],
        trend: trend
      )

    assert html =~ "Adding"
    assert html =~ "Fractions"
    assert html =~ "What is 2+2?"
    assert html =~ "Correct"
    assert html =~ "Recent attempts"
    assert html =~ "Accuracy trend"
  end

  test "drill_modal falls back when attempts and trend are empty" do
    html =
      render_component(&TopicMasteryMap.drill_modal/1,
        topic_name: "Adding",
        attempts: [],
        trend: []
      )

    assert html =~ "No recent attempts on this topic"
    assert html =~ "Not enough attempts in the last 30 days"
  end
end
