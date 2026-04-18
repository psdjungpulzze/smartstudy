defmodule StudySmartWeb.TestScheduleLiveTest do
  use StudySmartWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StudySmart.ContentFixtures

  defp auth_conn(conn, user_role) do
    conn
    |> init_test_session(%{
      dev_user_id: user_role.interactor_user_id,
      dev_user: %{
        "id" => user_role.interactor_user_id,
        "role" => "student",
        "email" => user_role.email,
        "display_name" => user_role.display_name,
        "user_role_id" => user_role.id
      }
    })
  end

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter} =
      StudySmart.Courses.create_chapter(%{
        name: "Chapter 1",
        position: 1,
        course_id: course.id
      })

    %{user_role: user_role, course: course, chapter: chapter}
  end

  describe "index" do
    test "renders test list page", %{conn: conn, user_role: ur} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/tests")

      assert html =~ "My Tests"
      assert html =~ "Schedule New Test"
    end

    test "displays scheduled tests", %{conn: conn, user_role: ur, course: c, chapter: ch} do
      {:ok, _schedule} =
        StudySmart.Assessments.create_test_schedule(%{
          name: "Biology Midterm",
          test_date: Date.add(Date.utc_today(), 5),
          scope: %{"chapter_ids" => [ch.id]},
          user_role_id: ur.id,
          course_id: c.id
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/tests")

      assert html =~ "Biology Midterm"
      assert html =~ c.name
    end

    test "shows empty state when no tests", %{conn: conn, user_role: ur} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/tests")

      assert html =~ "No tests scheduled yet"
    end
  end

  describe "new test form" do
    test "renders schedule form", %{conn: conn, user_role: ur} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/tests/new")

      assert html =~ "Schedule New Test"
      assert html =~ "Test Name"
      assert html =~ "Course"
      assert html =~ "Test Date"
    end

    test "shows chapters when course selected", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/tests/new")

      html = render_click(view, "select_course", %{"course_id" => c.id})

      assert html =~ "Chapter 1"
      assert html =~ "Test Scope"
    end
  end
end
