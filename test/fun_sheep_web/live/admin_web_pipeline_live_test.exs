defmodule FunSheepWeb.AdminWebPipelineLiveTest do
  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts
  alias FunSheep.Courses
  alias FunSheep.Questions
  alias FunSheep.Repo
  alias FunSheep.Content.DiscoveredSource

  defp admin_conn(conn) do
    {:ok, admin} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: :admin,
        email: "admin-pipeline-#{System.unique_integer()}@test.com",
        display_name: "Test Admin"
      })

    conn
    |> init_test_session(%{
      dev_user_id: admin.id,
      dev_user: %{
        "id" => admin.id,
        "user_role_id" => admin.id,
        "interactor_user_id" => admin.interactor_user_id,
        "role" => "admin",
        "email" => admin.email,
        "display_name" => admin.display_name
      }
    })
  end

  defp create_course(attrs) do
    {:ok, course} =
      Courses.create_course(
        Map.merge(
          %{
            name: "SAT Math Test #{System.unique_integer()}",
            subject: "Mathematics",
            processing_status: "ready"
          },
          attrs
        )
      )

    course
  end

  describe "/admin/web-pipeline" do
    test "renders page heading and course selector", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/web-pipeline")

      assert html =~ "Web Pipeline"
      assert html =~ "select a course"
    end

    test "shows empty state when no course is selected", %{conn: conn} do
      # No courses in db — selector has no options except the placeholder
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/web-pipeline")

      assert html =~ "select a course"
    end

    test "auto-selects first course and shows three-criteria cards", %{conn: conn} do
      course = create_course(%{catalog_test_type: "sat_math"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/web-pipeline")

      assert html =~ course.name
      assert html =~ "Criterion 1"
      assert html =~ "Criterion 2"
      assert html =~ "Criterion 3"
    end

    test "shows zero counts for a fresh course with no questions", %{conn: conn} do
      create_course(%{catalog_test_type: "sat_math"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/web-pipeline")

      assert html =~ "No web-scraped questions yet"
    end

    test "switching courses re-loads stats", %{conn: conn} do
      course_a = create_course(%{name: "Course Alpha #{System.unique_integer()}"})
      course_b = create_course(%{name: "Course Beta #{System.unique_integer()}"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/web-pipeline")

      # Selecting course_b should render the Three-Criteria panel for it.
      # Both course names may appear in the <option> list, so we only assert
      # that course_b shows up (as the selected option) rather than refuting course_a.
      html =
        view
        |> element("select[name=course_id]")
        |> render_change(%{course_id: course_b.id})

      assert html =~ "Three-Criteria Check"
      assert html =~ course_b.name
    end

    test "shows discovered sources stats when sources exist", %{conn: conn} do
      course = create_course(%{catalog_test_type: "sat_math"})

      Repo.insert!(%DiscoveredSource{
        course_id: course.id,
        url: "https://khanacademy.org/sat/math/q1",
        source_type: "question_bank",
        title: "Khan Academy SAT Math",
        status: "processed"
      })

      Repo.insert!(%DiscoveredSource{
        course_id: course.id,
        url: "https://collegeboard.org/practice/q2",
        source_type: "practice_test",
        title: "College Board Practice",
        status: "failed"
      })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/web-pipeline")

      # switch to the course we just seeded
      html =
        view
        |> element("select[name=course_id]")
        |> render_change(%{course_id: course.id})

      # 2 sources total, 1 scraped, 1 failed
      assert html =~ "Sources discovered"
      assert html =~ "Sources scraped"
      assert html =~ "Sources failed"
    end

    test "three-criteria criterion 1 shows domain count from top_domains", %{conn: conn} do
      course = create_course(%{catalog_test_type: "sat_math"})

      # Insert a web_scraped question with a source_url so the domain shows up
      {:ok, _q} =
        Questions.create_question(%{
          course_id: course.id,
          content: "Which of the following is a prime number greater than 10?",
          answer: "A",
          question_type: :multiple_choice,
          options: %{"A" => "11", "B" => "9", "C" => "4", "D" => "6"},
          difficulty: :medium,
          source_type: :web_scraped,
          source_url: "https://khanacademy.org/math/sat",
          validation_status: :passed
        })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/web-pipeline")

      html =
        view
        |> element("select[name=course_id]")
        |> render_change(%{course_id: course.id})

      assert html =~ "khanacademy.org"
    end
  end
end
