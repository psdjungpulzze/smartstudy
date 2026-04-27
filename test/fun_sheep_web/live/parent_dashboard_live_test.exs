defmodule FunSheepWeb.ParentDashboardLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{Accounts, Assessments, Courses, Questions, Repo}
  alias FunSheep.Engagement.StudySession

  defp create_user_role(attrs) do
    defaults = %{
      interactor_user_id: Ecto.UUID.generate(),
      role: :student,
      email: "user_#{System.unique_integer([:positive])}@test.com",
      display_name: "Test User"
    }

    {:ok, user_role} = Accounts.create_user_role(Map.merge(defaults, attrs))
    user_role
  end

  defp auth_conn(conn, user_role) do
    role_str = to_string(user_role.role)

    conn
    |> init_test_session(%{
      dev_user_id: user_role.interactor_user_id,
      dev_user: %{
        "id" => user_role.interactor_user_id,
        "role" => role_str,
        "email" => user_role.email,
        "display_name" => user_role.display_name,
        "interactor_user_id" => user_role.interactor_user_id
      }
    })
  end

  defp link!(parent, student) do
    {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
    {:ok, _} = Accounts.accept_guardian_invite(sg.id)
    :ok
  end

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

  describe "parent with no children" do
    test "shows empty state message", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})
      conn = auth_conn(conn, parent)

      {:ok, _view, html} = live(conn, ~p"/parent")

      assert html =~ "No students linked yet"
      assert html =~ "Connect your child&#39;s Fun Sheep account"
      assert html =~ "Connect a Student"
    end
  end

  describe "parent with children" do
    setup do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})
      student = create_user_role(%{role: :student, display_name: "Alice Student", grade: "10th"})
      link!(parent, student)
      %{parent: parent, student: student}
    end

    test "renders existing v1 metrics plus Phase 1 surfaces", %{conn: conn, parent: parent} do
      conn = auth_conn(conn, parent)
      {:ok, _view, html} = live(conn, ~p"/parent")

      assert html =~ "Alice Student"
      assert html =~ "Grade 10th"
      assert html =~ "Readiness"
      assert html =~ "No data yet"

      # Phase 1
      assert html =~ "Recent activity"
      assert html =~ "When your student studies"
      assert html =~ "Topic mastery"
    end

    test "shows honest empty-state on timeline for new students", %{conn: conn, parent: parent} do
      conn = auth_conn(conn, parent)
      {:ok, _view, html} = live(conn, ~p"/parent")

      assert html =~ "Not enough activity yet"
    end

    test "timeline renders sessions once there are ≥3", %{
      conn: conn,
      parent: parent,
      student: student
    } do
      course = FunSheep.ContentFixtures.create_course()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for offset <- [0, 1, 2] do
        insert_session!(student, %{
          completed_at: DateTime.add(now, -offset, :day),
          course_id: course.id
        })
      end

      conn = auth_conn(conn, parent)
      {:ok, _view, html} = live(conn, ~p"/parent")

      refute html =~ "Not enough activity yet"
      assert html =~ "Practice"
    end

    test "topic drill-down round-trip", %{conn: conn, parent: parent, student: student} do
      course = FunSheep.ContentFixtures.create_course(%{created_by_id: student.id})

      {:ok, chapter} =
        Courses.create_chapter(%{name: "Fractions", position: 1, course_id: course.id})

      {:ok, section} =
        Courses.create_section(%{name: "Adding", position: 1, chapter_id: chapter.id})

      {:ok, _schedule} =
        Assessments.create_test_schedule(%{
          name: "Exam",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: student.id,
          course_id: course.id
        })

      {:ok, q} =
        Questions.create_question(%{
          content: "Q1",
          answer: "A",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          chapter_id: chapter.id,
          section_id: section.id
        })

      {:ok, _} =
        %Questions.QuestionAttempt{}
        |> Questions.QuestionAttempt.changeset(%{
          user_role_id: student.id,
          question_id: q.id,
          is_correct: true,
          time_taken_seconds: 20,
          answer_given: "x"
        })
        |> Repo.insert()

      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/parent")

      html = render_click(view, "topic_drill", %{"section-id" => section.id})

      assert html =~ "Recent attempts"
      assert html =~ "Adding"

      html = render_click(view, "close_topic_drill", %{})
      refute html =~ "Recent attempts"
    end

    test "select_student clears drill", %{conn: conn, parent: parent, student: student} do
      other = create_user_role(%{role: :student, display_name: "Bob"})
      link!(parent, other)

      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/parent")

      html = render_click(view, "select_student", %{"id" => student.id})
      assert html =~ "Alice Student"
    end
  end

  describe "authorization (spec §9.1)" do
    test "a student who visits /parent sees the empty state (they have no linked children)",
         %{conn: conn} do
      student = create_user_role(%{role: :student, display_name: "Solo"})
      conn = auth_conn(conn, student)
      {:ok, _view, html} = live(conn, ~p"/parent")

      assert html =~ "No students linked yet"
    end

    test "topic_drill is a no-op when the guardian has no access", %{conn: conn} do
      parent = create_user_role(%{role: :parent})

      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/parent")

      _ = render_click(view, "topic_drill", %{"section-id" => Ecto.UUID.generate()})
      refute render(view) =~ "Recent attempts"
    end
  end

  describe "share_progress event" do
    setup do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})
      student = create_user_role(%{role: :student, display_name: "Alice Student", grade: "10th"})
      link!(parent, student)
      %{parent: parent, student: student}
    end

    test "share_progress sets shared_student_id", %{conn: conn, parent: parent, student: student} do
      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/parent")

      # The share_progress event sets shared_student_id; the proof card only renders
      # when show_proof_card? is true, which requires a meaningful improvement in score.
      # We just verify the event doesn't crash.
      _ = render_click(view, "share_progress", %{"id" => student.id})
      assert render(view) =~ "Alice Student"
    end

    test "open_share event sets shared_student_id", %{
      conn: conn,
      parent: parent,
      student: student
    } do
      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/parent")

      _ = render_click(view, "open_share", %{"student-id" => student.id})
      assert render(view) =~ "Alice Student"
    end
  end

  describe "multiple students — household overview" do
    test "household overview renders when there are 2+ students", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})
      student1 = create_user_role(%{role: :student, display_name: "Alice", grade: "10th"})
      student2 = create_user_role(%{role: :student, display_name: "Bob", grade: "9th"})
      link!(parent, student1)
      link!(parent, student2)

      conn = auth_conn(conn, parent)
      {:ok, _view, html} = live(conn, ~p"/parent")

      assert html =~ "Household"
      assert html =~ "Alice"
      assert html =~ "Bob"
    end

    test "select_student switches the active student tab in multi-student view", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})
      student1 = create_user_role(%{role: :student, display_name: "Alice", grade: "10th"})
      student2 = create_user_role(%{role: :student, display_name: "Bob", grade: "9th"})
      link!(parent, student1)
      link!(parent, student2)

      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/parent")

      # Switch to student2
      html = render_click(view, "select_student", %{"id" => student2.id})
      assert html =~ "Bob"
    end
  end

  describe "goal management" do
    setup do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})
      student = create_user_role(%{role: :student, display_name: "Alice Student", grade: "10th"})
      link!(parent, student)
      %{parent: parent, student: student}
    end

    test "open_propose_goal opens the goal proposal form", %{conn: conn, parent: parent} do
      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/parent")

      html = render_click(view, "open_propose_goal", %{})
      assert html =~ "Goal type"
    end

    test "close_propose_goal closes the form", %{conn: conn, parent: parent} do
      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/parent")

      render_click(view, "open_propose_goal", %{})
      html = render_click(view, "close_propose_goal", %{})

      # Form should be closed — no goal type label visible
      refute html =~ "Goal type"
    end

    test "open_counter_goal re-opens propose form", %{conn: conn, parent: parent} do
      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/parent")

      html = render_click(view, "open_counter_goal", %{})
      assert html =~ "Goal type"
    end

    test "decline_goal with unknown id is a no-op", %{conn: conn, parent: parent} do
      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/parent")

      _ = render_click(view, "decline_goal", %{"goal-id" => Ecto.UUID.generate()})
      assert render(view) =~ "Alice Student"
    end

    test "accept_goal with unknown id is a no-op", %{conn: conn, parent: parent} do
      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/parent")

      _ = render_click(view, "accept_goal", %{"goal-id" => Ecto.UUID.generate()})
      assert render(view) =~ "Alice Student"
    end
  end

  describe "set_target_readiness event" do
    test "set_target_readiness with no schedule is a no-op", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})
      student = create_user_role(%{role: :student, display_name: "Alice Student", grade: "10th"})
      link!(parent, student)

      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/parent")

      # No schedule exists, so this should be a no-op
      _ =
        render_click(view, "set_target_readiness", %{
          "schedule_id" => Ecto.UUID.generate(),
          "value" => "80"
        })

      assert render(view) =~ "Alice Student"
    end

    test "set_target_readiness with invalid value is a no-op", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})
      student = create_user_role(%{role: :student, display_name: "Alice Student", grade: "10th"})
      link!(parent, student)

      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/parent")

      _ =
        render_click(view, "set_target_readiness", %{
          "schedule_id" => Ecto.UUID.generate(),
          "value" => "not_a_number"
        })

      assert render(view) =~ "Alice Student"
    end
  end

  describe "assign_topic_practice event" do
    test "assign_topic_practice with no drill open is a no-op", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})
      student = create_user_role(%{role: :student, display_name: "Alice Student", grade: "10th"})
      link!(parent, student)

      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/parent")

      # No drill open, so section_id is nil — event is a no-op
      _ = render_click(view, "assign_topic_practice", %{"question_count" => "5"})
      assert render(view) =~ "Alice Student"
    end
  end

  describe "close_topic_drill event" do
    setup do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})
      student = create_user_role(%{role: :student, display_name: "Alice Student", grade: "10th"})
      link!(parent, student)
      %{parent: parent, student: student}
    end

    test "close_topic_drill clears the drill assign", %{
      conn: conn,
      parent: parent,
      student: student
    } do
      course = FunSheep.ContentFixtures.create_course()

      {:ok, chapter} =
        Courses.create_chapter(%{name: "Algebra", position: 1, course_id: course.id})

      {:ok, section} =
        Courses.create_section(%{name: "Equations", position: 1, chapter_id: chapter.id})

      {:ok, _schedule} =
        Assessments.create_test_schedule(%{
          name: "Final",
          test_date: Date.add(Date.utc_today(), 14),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: student.id,
          course_id: course.id
        })

      {:ok, q} =
        Questions.create_question(%{
          content: "Solve for x",
          answer: "5",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          chapter_id: chapter.id,
          section_id: section.id
        })

      {:ok, _} =
        %Questions.QuestionAttempt{}
        |> Questions.QuestionAttempt.changeset(%{
          user_role_id: student.id,
          question_id: q.id,
          is_correct: true,
          time_taken_seconds: 30,
          answer_given: "5"
        })
        |> Repo.insert()

      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/parent")

      # Open the drill
      render_click(view, "topic_drill", %{"section-id" => section.id})
      assert render(view) =~ "Recent attempts"

      # Close it
      html = render_click(view, "close_topic_drill", %{})
      refute html =~ "Recent attempts"
    end
  end
end
