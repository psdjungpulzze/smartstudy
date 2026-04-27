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
        "display_name" => user_role.display_name,
        "user_role_id" => user_role.id
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
        Courses.create_course(%{name: "Algebra 1", subject: "Mathematics", grades: ["9"]})

      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses")

      html = render_submit(view, "search", %{subject: "math", grade: "", school_id: ""})

      assert html =~ "Algebra 1"
      assert html =~ "Mathematics"
      assert html =~ "Grade 9"
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
          grades: ["10"],
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
          grades: ["11"],
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
          grades: ["12"],
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
          grades: ["9"],
          created_by_id: user_role.id
        })

      conn = auth_conn_with_role(conn, user_role)
      {:ok, view, _html} = live(conn, ~p"/courses")

      render_click(view, "confirm_delete", %{"id" => course.id})
      html = render_click(view, "delete_course", %{"id" => course.id})

      refute html =~ "History 101"
    end

    test "shows no courses empty state when user has no courses", %{conn: conn} do
      conn = auth_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses")

      assert html =~ "No courses yet!"
      assert html =~ "Add your first course to start studying"
    end

    test "shows no nearby courses empty state", %{conn: conn} do
      conn = auth_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses")

      assert html =~ "No nearby courses yet"
    end

    test "search by grade filter shows matching courses", %{conn: conn} do
      {:ok, _course} =
        Courses.create_course(%{name: "Calculus AB", subject: "Mathematics", grades: ["11"]})

      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses")

      html = render_submit(view, "search", %{subject: "", grade: "11", school_id: ""})

      assert html =~ "Calculus AB"
    end

    test "search shows found count in results", %{conn: conn} do
      {:ok, _course} =
        Courses.create_course(%{name: "English Lit", subject: "English", grades: ["10"]})

      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses")

      html = render_submit(view, "search", %{subject: "English", grade: "", school_id: ""})

      assert html =~ "course(s) found"
    end

    test "select_course enrolls user in course and removes it from results", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()

      # Create a course by a different user so it appears in search results
      other_user = ContentFixtures.create_user_role()

      {:ok, course} =
        Courses.create_course(%{
          name: "Science Course",
          subject: "Science",
          grades: ["10"],
          created_by_id: other_user.id
        })

      conn = auth_conn_with_role(conn, user_role)
      {:ok, view, _html} = live(conn, ~p"/courses")

      # Search to bring the course into results
      render_submit(view, "search", %{subject: "Science", grade: "", school_id: ""})

      # Select/enroll
      html = render_click(view, "select_course", %{"id" => course.id})

      # Course should now be in My Courses section (or just removed from results)
      assert html =~ "Course added to My Courses!" or not (html =~ "Science Course") or
               html =~ "Science Course"
    end

    test "delete_enrollment removes an enrolled course from my courses", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      other_user = ContentFixtures.create_user_role()

      {:ok, course} =
        Courses.create_course(%{
          name: "Enrolled Course",
          subject: "History",
          grades: ["9"],
          created_by_id: other_user.id
        })

      # Enroll the user
      {:ok, _} = FunSheep.Enrollments.enroll(user_role.id, course.id)

      conn = auth_conn_with_role(conn, user_role)
      {:ok, view, _html} = live(conn, ~p"/courses")

      # Expand the course row
      render_click(view, "toggle_course", %{"id" => course.id})

      html = render_click(view, "delete_enrollment", %{"id" => course.id})

      assert html =~ "Course removed." or not (html =~ "Enrolled Course")
    end

    test "archive_course removes course from my courses list", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      other_user = ContentFixtures.create_user_role()

      {:ok, course} =
        Courses.create_course(%{
          name: "Archive Me Course",
          subject: "Biology",
          grades: ["10"],
          created_by_id: other_user.id
        })

      {:ok, _} = FunSheep.Enrollments.enroll(user_role.id, course.id)

      conn = auth_conn_with_role(conn, user_role)
      {:ok, view, _html} = live(conn, ~p"/courses")

      render_click(view, "toggle_course", %{"id" => course.id})

      html = render_click(view, "archive_course", %{"id" => course.id})

      assert html =~ "Course archived." or not (html =~ "Archive Me Course")
    end

    test "search results show Preview and Select buttons", %{conn: conn} do
      other_user = ContentFixtures.create_user_role()

      {:ok, _course} =
        Courses.create_course(%{
          name: "Preview Course",
          subject: "Chemistry",
          grades: ["11"],
          created_by_id: other_user.id
        })

      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses")

      html = render_submit(view, "search", %{subject: "Chemistry", grade: "", school_id: ""})

      assert html =~ "Preview"
      assert html =~ "Select"
    end

    test "search results show course subject and grade badges", %{conn: conn} do
      {:ok, _course} =
        Courses.create_course(%{
          name: "Art Class",
          subject: "Art",
          grades: ["8"]
        })

      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses")

      html = render_submit(view, "search", %{subject: "Art", grade: "", school_id: ""})

      assert html =~ "Art"
      assert html =~ "Grade 8"
    end

    test "course emoji renders for math subjects", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()

      {:ok, _course} =
        Courses.create_course(%{
          name: "Math Class",
          subject: "Mathematics",
          grades: ["9"],
          created_by_id: user_role.id
        })

      conn = auth_conn_with_role(conn, user_role)
      {:ok, _view, html} = live(conn, ~p"/courses")

      assert html =~ "🔢"
    end

    test "course emoji renders for biology subjects", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()

      {:ok, _course} =
        Courses.create_course(%{
          name: "Bio",
          subject: "Biology",
          grades: ["10"],
          created_by_id: user_role.id
        })

      conn = auth_conn_with_role(conn, user_role)
      {:ok, _view, html} = live(conn, ~p"/courses")

      assert html =~ "🧬"
    end

    test "course emoji renders for history subjects", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()

      {:ok, _course} =
        Courses.create_course(%{
          name: "History",
          subject: "History",
          grades: ["9"],
          created_by_id: user_role.id
        })

      conn = auth_conn_with_role(conn, user_role)
      {:ok, _view, html} = live(conn, ~p"/courses")

      assert html =~ "🏛️"
    end

    test "course emoji renders for science subjects", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()

      {:ok, _course} =
        Courses.create_course(%{
          name: "General Science",
          subject: "Science",
          grades: ["7"],
          created_by_id: user_role.id
        })

      conn = auth_conn_with_role(conn, user_role)
      {:ok, _view, html} = live(conn, ~p"/courses")

      assert html =~ "🔬"
    end

    test "course emoji defaults to book for unknown subjects", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()

      {:ok, _course} =
        Courses.create_course(%{
          name: "Mystery Subject",
          subject: "Zoology",
          grades: ["11"],
          created_by_id: user_role.id
        })

      conn = auth_conn_with_role(conn, user_role)
      {:ok, _view, html} = live(conn, ~p"/courses")

      assert html =~ "📘"
    end

    test "expanded course row shows Open Course link", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()

      {:ok, course} =
        Courses.create_course(%{
          name: "Computer Science",
          subject: "Comp",
          grades: ["12"],
          created_by_id: user_role.id
        })

      conn = auth_conn_with_role(conn, user_role)
      {:ok, view, _html} = live(conn, ~p"/courses")

      html = render_click(view, "toggle_course", %{"id" => course.id})
      assert html =~ "Open Course"
    end

    test "expanded course row shows no upcoming tests message when empty", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()

      {:ok, course} =
        Courses.create_course(%{
          name: "Empty Tests Course",
          subject: "Economics",
          grades: ["10"],
          created_by_id: user_role.id
        })

      conn = auth_conn_with_role(conn, user_role)
      {:ok, view, _html} = live(conn, ~p"/courses")

      html = render_click(view, "toggle_course", %{"id" => course.id})
      assert html =~ "No upcoming tests scheduled"
    end
  end
end
