defmodule FunSheepWeb.AdminCourseShowLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.Courses

  defp admin_conn(conn) do
    conn
    |> init_test_session(%{
      dev_user_id: "test_admin",
      dev_user: %{
        "id" => "test_admin",
        "role" => "admin",
        "email" => "admin@test.com",
        "display_name" => "Test Admin",
        "user_role_id" => "test_admin"
      }
    })
  end

  defp create_course(attrs) do
    {:ok, course} =
      Courses.create_course(
        Map.merge(%{name: "Biology 101", subject: "Biology", grade: "10"}, attrs)
      )

    course
  end

  describe "mount and render" do
    test "renders the course name in the page header", %{conn: conn} do
      course = create_course(%{name: "Advanced Physics"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}")

      assert html =~ "Advanced Physics"
    end

    test "renders pipeline audit stat cards", %{conn: conn} do
      course = create_course(%{name: "Chemistry 101"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}")

      assert html =~ "Sources discovered"
      assert html =~ "Questions extracted"
      assert html =~ "Passed validation"
    end

    test "renders the per-domain table even when no sources exist", %{conn: conn} do
      course = create_course(%{name: "Empty Course"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}")

      assert html =~ "Per-domain extraction"
      assert html =~ "No sources discovered yet for this course."
    end

    test "renders pipeline audit with zeroed counts for a new course", %{conn: conn} do
      course = create_course(%{name: "Fresh Course"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}")

      # All stats should be present; for a brand-new course they will be 0
      assert html =~ "Sources discovered"
      assert html =~ "Sources scraped"
      assert html =~ "Sources failed"
      assert html =~ "Needs review"
      assert html =~ "Failed validation"
    end

    test "renders breadcrumb link back to courses list", %{conn: conn} do
      course = create_course(%{name: "Breadcrumb Test Course"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}")

      assert html =~ "/admin/courses"
      assert html =~ "Courses"
    end
  end
end
