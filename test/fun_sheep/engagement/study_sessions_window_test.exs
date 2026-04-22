defmodule FunSheep.Engagement.StudySessionsWindowTest do
  @moduledoc """
  Covers the parent-facing queries added for spec §5.1 / §5.2 in
  `FunSheep.Engagement.StudySessions`.
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.ContentFixtures
  alias FunSheep.Engagement.StudySession
  alias FunSheep.Engagement.StudySessions
  alias FunSheep.Repo

  defp insert_session!(user_role, attrs) do
    defaults = %{
      session_type: "practice",
      time_window: "morning",
      questions_attempted: 10,
      questions_correct: 7,
      duration_seconds: 600,
      user_role_id: user_role.id
    }

    {:ok, session} =
      %StudySession{}
      |> StudySession.changeset(Map.merge(defaults, attrs))
      |> Repo.insert()

    session
  end

  describe "list_for_student_in_window/2" do
    setup do
      %{student: ContentFixtures.create_user_role(%{role: :student})}
    end

    test "returns only completed sessions in the window, newest first", %{student: s} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      _incomplete =
        insert_session!(s, %{
          completed_at: nil
        })

      old =
        insert_session!(s, %{
          completed_at: DateTime.add(now, -40, :day)
        })

      recent =
        insert_session!(s, %{
          completed_at: DateTime.add(now, -2, :day)
        })

      newest =
        insert_session!(s, %{
          completed_at: now
        })

      result = StudySessions.list_for_student_in_window(s.id, 30)

      ids = Enum.map(result, & &1.id)
      assert ids == [newest.id, recent.id]
      refute old.id in ids
    end

    test "preloads course to avoid N+1", %{student: s} do
      course = ContentFixtures.create_course()

      insert_session!(s, %{
        completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        course_id: course.id
      })

      [loaded] = StudySessions.list_for_student_in_window(s.id, 7)
      assert %FunSheep.Courses.Course{} = loaded.course
      assert loaded.course.id == course.id
    end

    test "returns [] when no sessions in window", %{student: s} do
      assert StudySessions.list_for_student_in_window(s.id, 7) == []
    end
  end

  describe "study_heatmap/3" do
    setup do
      %{student: ContentFixtures.create_user_role(%{role: :student})}
    end

    test "aggregates minutes by {day_of_week, time_window}", %{student: s} do
      # Monday (dow=1)
      ts = ~U[2026-04-20 09:00:00Z]

      insert_session!(s, %{
        completed_at: ts,
        time_window: "morning",
        duration_seconds: 600
      })

      insert_session!(s, %{
        completed_at: ts,
        time_window: "morning",
        duration_seconds: 300
      })

      insert_session!(s, %{
        completed_at: DateTime.add(ts, 6, :hour),
        time_window: "afternoon",
        duration_seconds: 1200
      })

      grid = StudySessions.study_heatmap(s.id, 4)
      assert grid[{1, "morning"}] == 15
      assert grid[{1, "afternoon"}] == 20
    end

    test "excludes sessions older than the lookback window", %{student: s} do
      insert_session!(s, %{
        completed_at: DateTime.add(DateTime.utc_now(), -40, :day),
        time_window: "morning",
        duration_seconds: 600
      })

      assert StudySessions.study_heatmap(s.id, 4) == %{}
    end
  end
end
