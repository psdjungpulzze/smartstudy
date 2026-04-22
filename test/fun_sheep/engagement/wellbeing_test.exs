defmodule FunSheep.Engagement.WellbeingTest do
  @moduledoc """
  Covers the wellbeing classifier (spec §5.4).

  Only uses real, observable signals — `study_sessions`, upcoming tests,
  streak. No mocked scores.
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.{Assessments, Gamification, Repo}
  alias FunSheep.ContentFixtures
  alias FunSheep.Engagement.{StudySession, Wellbeing}

  defp insert_session!(user_role, attrs) do
    defaults = %{
      session_type: "practice",
      time_window: "morning",
      questions_attempted: 10,
      questions_correct: 8,
      duration_seconds: 600,
      user_role_id: user_role.id,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    {:ok, session} =
      %StudySession{}
      |> StudySession.changeset(Map.merge(defaults, attrs))
      |> Repo.insert()

    session
  end

  defp bump_streak!(user_role, streak) do
    {:ok, %{} = s} = Gamification.get_or_create_streak(user_role.id)

    {:ok, _} =
      s
      |> Ecto.Changeset.change(%{current_streak: streak, longest_streak: streak})
      |> Repo.update()
  end

  defp ago(days), do: DateTime.add(DateTime.utc_now(), -days, :day)

  setup do
    %{student: ContentFixtures.create_user_role(%{role: :student})}
  end

  test "insufficient_data when no sessions anywhere", %{student: s} do
    assert %{signal: :insufficient_data} = Wellbeing.classify(s.id)
  end

  test "disengaged: no sessions in last 5 days, broken streak, imminent test", ctx do
    %{student: s} = ctx
    course = ContentFixtures.create_course()

    {:ok, _schedule} =
      Assessments.create_test_schedule(%{
        name: "Soon",
        test_date: Date.add(Date.utc_today(), 10),
        scope: %{"chapter_ids" => []},
        user_role_id: s.id,
        course_id: course.id
      })

    # A session outside the disengaged window so the classifier isn't in insufficient_data
    insert_session!(s, %{completed_at: ago(10)})

    assert %{signal: :disengaged, reasons: reasons} = Wellbeing.classify(s.id)
    assert :test_imminent in reasons
  end

  test "thriving: streak ≥ 7, accuracy up, ≥ 3 windows", %{student: s} do
    bump_streak!(s, 8)

    # Prior week: moderate accuracy
    insert_session!(s, %{
      completed_at: ago(10),
      time_window: "morning",
      questions_attempted: 10,
      questions_correct: 6
    })

    # Recent week: higher accuracy, 3 windows
    insert_session!(s, %{
      completed_at: ago(2),
      time_window: "morning",
      questions_attempted: 10,
      questions_correct: 9
    })

    insert_session!(s, %{
      completed_at: ago(1),
      time_window: "afternoon",
      questions_attempted: 10,
      questions_correct: 9
    })

    insert_session!(s, %{
      completed_at: ago(0),
      time_window: "evening",
      questions_attempted: 10,
      questions_correct: 9
    })

    assert %{signal: :thriving} = Wellbeing.classify(s.id)
  end

  test "under_pressure: late-night spike + accuracy drop while minutes up", %{student: s} do
    # Prior week: daytime, high accuracy, low minutes
    insert_session!(s, %{
      completed_at: ago(10),
      time_window: "afternoon",
      questions_attempted: 10,
      questions_correct: 9,
      duration_seconds: 600
    })

    # Recent week: night sessions, lower accuracy, more minutes
    for offset <- [3, 2, 1] do
      insert_session!(s, %{
        completed_at: ago(offset),
        time_window: "night",
        questions_attempted: 20,
        questions_correct: 10,
        duration_seconds: 1200
      })
    end

    assert %{signal: :under_pressure, reasons: reasons} = Wellbeing.classify(s.id)
    assert :late_night_spike in reasons
  end

  test "steady: falls through to default", %{student: s} do
    for offset <- [1, 2, 3] do
      insert_session!(s, %{
        completed_at: ago(offset),
        time_window: "afternoon",
        questions_attempted: 10,
        questions_correct: 7
      })
    end

    assert %{signal: :steady} = Wellbeing.classify(s.id)
  end
end
