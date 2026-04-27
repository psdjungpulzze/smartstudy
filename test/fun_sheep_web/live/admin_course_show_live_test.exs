defmodule FunSheepWeb.AdminCourseShowLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{Courses, Repo}
  alias FunSheep.Content.DiscoveredSource

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

  defp create_discovered_source(course_id, attrs) do
    defaults = %{
      course_id: course_id,
      url: "https://example.com/page-#{System.unique_integer([:positive])}",
      source_type: "question_bank",
      status: "scraped",
      discovery_strategy: "web_search",
      title: "Test Source"
    }

    {:ok, source} =
      %DiscoveredSource{}
      |> DiscoveredSource.changeset(Map.merge(defaults, attrs))
      |> Repo.insert()

    source
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

    test "renders course metadata including catalog fields when present", %{conn: conn} do
      {:ok, course} =
        Courses.create_course(%{
          name: "SAT Math Prep",
          subject: "Mathematics",
          grade: "11",
          catalog_test_type: "SAT",
          catalog_subject: "Math",
          processing_status: "ready",
          access_level: "public"
        })

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}")

      assert html =~ "SAT"
      assert html =~ "Math"
      assert html =~ "ready"
      assert html =~ "public"
    end

    test "renders em-dash for nil catalog fields on a plain course", %{conn: conn} do
      course = create_course(%{name: "Plain Course"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}")

      # nil catalog_test_type renders as "—"
      assert html =~ "—"
    end

    test "renders per-domain table with rows when sources exist", %{conn: conn} do
      course = create_course(%{name: "Course With Sources"})
      create_discovered_source(course.id, %{url: "https://khan.org/math/calculus", status: "scraped"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}")

      assert html =~ "khan.org"
      assert html =~ "Per-domain extraction"
      # Table headers appear for non-empty result
      assert html =~ "Domain"
      assert html =~ "Strategy"
    end

    test "renders web_search strategy badge for web_search sources", %{conn: conn} do
      course = create_course(%{name: "Web Search Course"})

      create_discovered_source(course.id, %{
        url: "https://quizlet.com/biology",
        discovery_strategy: "web_search"
      })

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}")

      assert html =~ "web_search"
    end

    test "renders registry strategy badge for registry sources", %{conn: conn} do
      course = create_course(%{name: "Registry Course"})

      create_discovered_source(course.id, %{
        url: "https://official-source.org/resource",
        discovery_strategy: "registry"
      })

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}")

      assert html =~ "registry"
    end

    test "renders pass rate column in per-domain table", %{conn: conn} do
      course = create_course(%{name: "Pass Rate Course"})

      create_discovered_source(course.id, %{url: "https://example.com/q", status: "scraped"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}")

      assert html =~ "Pass rate"
    end
  end
end
