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
      # Chapter management is behind a toggle; the "Question Bank" action link
      # is always visible, so use that to confirm the detail shell rendered.
      assert html =~ "Question Bank"
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

      # Chapter management panel is collapsed by default; open it first so the
      # section markup is actually rendered for the assertion.
      render_click(view, "toggle_chapters")
      render_click(view, "toggle_chapter", %{id: chapter.id})
      render_click(view, "show_add_section", %{"chapter-id" => chapter.id})

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

    test "renders textbook missing banner when no textbook is attached", %{conn: conn} do
      course = create_course()
      conn = auth_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}")

      assert html =~ "Upload the textbook to power this course",
             "Expected the missing-textbook banner to render on the detail page"

      assert html =~ "Upload Textbook"
    end

    test "hides textbook banner when a :complete textbook is attached", %{conn: conn} do
      course = create_course()
      user_role = FunSheep.ContentFixtures.create_user_role()

      {:ok, _material} =
        %FunSheep.Content.UploadedMaterial{}
        |> FunSheep.Content.UploadedMaterial.changeset(%{
          file_path: "tmp/x.pdf",
          file_name: "book.pdf",
          file_type: "application/pdf",
          file_size: 100,
          user_role_id: user_role.id,
          course_id: course.id,
          material_kind: :textbook,
          ocr_status: :completed,
          completeness_score: 0.95
        })
        |> FunSheep.Repo.insert()

      conn = auth_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}")

      refute html =~ "Upload the textbook to power this course"
    end
  end
end
