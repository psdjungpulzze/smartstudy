defmodule FunSheepWeb.CourseDetailLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.Courses

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

  defp create_course do
    {:ok, course} =
      Courses.create_course(%{name: "Test Algebra", subject: "Mathematics", grade: "10"})

    course
  end

  describe "course detail page" do
    test "shows course info", %{conn: conn} do
      course = create_course()
      conn = auth_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}")

      assert html =~ "Test Algebra"
      assert html =~ "Mathematics"
      assert html =~ "Grade 10"
      assert html =~ "Chapters"
    end

    test "shows chapters", %{conn: conn} do
      course = create_course()

      {:ok, _ch} =
        Courses.create_chapter(%{name: "Introduction", position: 1, course_id: course.id})

      conn = auth_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}")

      assert html =~ "Introduction"
    end

    test "adding a chapter", %{conn: conn} do
      course = create_course()
      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}")

      # Show add form
      render_click(view, "show_add_chapter")

      # Submit the form
      html =
        render_submit(view, "save_chapter", %{chapter: %{name: "New Chapter"}})

      assert html =~ "New Chapter"
    end

    test "adding a section to a chapter", %{conn: conn} do
      course = create_course()

      {:ok, chapter} =
        Courses.create_chapter(%{name: "Chapter 1", position: 1, course_id: course.id})

      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}")

      # Expand chapter and show add section form
      render_click(view, "toggle_chapter", %{id: chapter.id})
      render_click(view, "show_add_section", %{"chapter-id" => chapter.id})

      # Submit the section form
      html = render_submit(view, "save_section", %{section: %{name: "New Section"}})

      assert html =~ "New Section"
    end

    test "deleting a chapter", %{conn: conn} do
      course = create_course()

      {:ok, chapter} =
        Courses.create_chapter(%{name: "To Delete", position: 1, course_id: course.id})

      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}")

      html = render_click(view, "delete_chapter", %{id: chapter.id})

      refute html =~ "To Delete"
    end
  end
end
