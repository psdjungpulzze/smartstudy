defmodule FunSheepWeb.CourseSearchLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.Courses
  alias FunSheep.ContentFixtures

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

  defp auth_conn_with_role(conn, user_role) do
    conn
    |> init_test_session(%{
      dev_user_id: user_role.id,
      dev_user: %{
        "id" => user_role.id,
        "role" => "student",
        "email" => user_role.email,
        "display_name" => user_role.display_name
      }
    })
  end

  describe "course search page" do
    test "renders page shell with My Courses heading and add-course CTA", %{conn: conn} do
      conn = auth_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses")

      assert html =~ "My Courses"
      assert html =~ "Add New Course"
      assert html =~ "Find More Courses"
    end

    test "expanding the collapsible search panel reveals the search form", %{conn: conn} do
      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses")

      html = render_click(view, "toggle_search")

      assert html =~ "Subject"
      assert html =~ "Grade"
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

    test "schools are not loaded on initial mount (lazy load)", %{conn: conn} do
      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses")

      assert view |> element("select[name='school_id']") |> has_element?() == false
    end

    test "schools are loaded when search panel is opened", %{conn: conn} do
      ContentFixtures.create_school()
      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses")

      html = render_click(view, "toggle_search")

      assert html =~ "All Schools"
      assert html =~ "Test School"
    end

    test "closing and reopening search panel does not reload schools", %{conn: conn} do
      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses")

      render_click(view, "toggle_search")
      render_click(view, "toggle_search")
      html = render_click(view, "toggle_search")

      assert html =~ "All Schools"
    end

    test "toggle_course expands and collapses a course row", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()

      {:ok, course} =
        Courses.create_course(%{
          name: "Biology 101",
          subject: "Biology",
          grade: "10",
          created_by_id: user_role.id
        })

      conn = auth_conn_with_role(conn, user_role)
      {:ok, view, _html} = live(conn, ~p"/courses")

      html = render_click(view, "toggle_course", %{"id" => course.id})
      assert html =~ "Schedule Test"
      assert html =~ "Open Course"

      html = render_click(view, "toggle_course", %{"id" => course.id})
      refute html =~ "Schedule Test"
    end

    test "confirm_delete shows delete confirmation overlay", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()

      {:ok, course} =
        Courses.create_course(%{
          name: "Chemistry 101",
          subject: "Chemistry",
          grade: "11",
          created_by_id: user_role.id
        })

      conn = auth_conn_with_role(conn, user_role)
      {:ok, view, _html} = live(conn, ~p"/courses")

      html = render_click(view, "confirm_delete", %{"id" => course.id})
      assert html =~ "This cannot be undone"
    end

    test "cancel_delete dismisses the confirmation overlay", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()

      {:ok, course} =
        Courses.create_course(%{
          name: "Physics 101",
          subject: "Physics",
          grade: "12",
          created_by_id: user_role.id
        })

      conn = auth_conn_with_role(conn, user_role)
      {:ok, view, _html} = live(conn, ~p"/courses")

      render_click(view, "confirm_delete", %{"id" => course.id})
      html = render_click(view, "cancel_delete", %{})

      refute html =~ "This cannot be undone"
    end

    test "delete_course removes the course from the list", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()

      {:ok, course} =
        Courses.create_course(%{
          name: "History 101",
          subject: "History",
          grade: "9",
          created_by_id: user_role.id
        })

      conn = auth_conn_with_role(conn, user_role)
      {:ok, view, _html} = live(conn, ~p"/courses")

      render_click(view, "confirm_delete", %{"id" => course.id})
      html = render_click(view, "delete_course", %{"id" => course.id})

      refute html =~ "History 101"
    end
  end
end
