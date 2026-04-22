defmodule FunSheepWeb.DashboardLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{Accounts, Assessments, Courses}

  defp user_role_conn(conn, attrs \\ %{}) do
    defaults = %{
      interactor_user_id: "dash_test_#{System.unique_integer([:positive])}",
      role: :student,
      email: "dash_#{System.unique_integer([:positive])}@test.com",
      display_name: "Test Student"
    }

    {:ok, user_role} = Accounts.create_user_role(Map.merge(defaults, attrs))

    conn =
      init_test_session(conn, %{
        dev_user_id: user_role.id,
        dev_user: %{
          "id" => user_role.id,
          "role" => "student",
          "email" => user_role.email,
          "display_name" => user_role.display_name
        }
      })

    {conn, user_role}
  end

  describe "student home" do
    test "renders greeting with the user's display name", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # Greeting is "Good morning", "Hey", or "Evening" depending on hour, so
      # check for the name — which is rendered regardless.
      assert html =~ "Test Student"
    end

    test "shows welcome onboarding when the user has no courses and no tests", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Welcome to Fun Sheep!"
      assert html =~ "Add a Course"
    end

    test "shows 'no upcoming tests' empty state when courses exist but no tests are scheduled",
         %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, _course} =
        Courses.create_course(%{
          name: "My Math Course",
          subject: "Math",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "No upcoming tests"
      assert html =~ "Go to Courses"
    end

    test "renders focus card and study path when an upcoming test exists", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Algebra II",
          subject: "Math",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _schedule} =
        Assessments.create_test_schedule(%{
          name: "Midterm Exam",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Midterm Exam"
      assert html =~ "Your Study Path"
      assert html =~ "Readiness"
    end
  end
end
