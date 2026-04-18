defmodule StudySmartWeb.CourseSearchLiveTest do
  use StudySmartWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StudySmart.Courses

  defp auth_conn(conn) do
    conn
    |> init_test_session(%{
      dev_user_id: "test_student",
      dev_user: %{
        "id" => "test_student",
        "role" => "student",
        "email" => "test@test.com",
        "display_name" => "Test Student"
      }
    })
  end

  describe "course search page" do
    test "renders search form", %{conn: conn} do
      conn = auth_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses")

      assert html =~ "My Courses"
      assert html =~ "Subject"
      assert html =~ "Grade"
      assert html =~ "Search"
      assert html =~ "Add New Course"
    end

    test "search with results", %{conn: conn} do
      {:ok, _course} =
        Courses.create_course(%{name: "Algebra 1", subject: "Mathematics", grade: "9"})

      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses")

      html = render_submit(view, "search", %{subject: "math", grade: "", school_id: ""})

      assert html =~ "Algebra 1"
      assert html =~ "Mathematics"
      assert html =~ "Grade 9"
      assert html =~ "Open"
    end

    test "empty search results", %{conn: conn} do
      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses")

      html =
        render_submit(view, "search", %{subject: "nonexistent", grade: "", school_id: ""})

      assert html =~ "No matches found"
    end

    test "clear search resets results", %{conn: conn} do
      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses")

      render_submit(view, "search", %{subject: "test", grade: "", school_id: ""})
      html = render_click(view, "clear_search")

      refute html =~ "No matches found"
      refute html =~ "Found"
    end
  end
end
