defmodule FunSheepWeb.TestScheduleLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{Assessments, ContentFixtures}

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

  defp create_schedule(user_role, course, attrs \\ %{}) do
    defaults = %{
      name: "Test Schedule",
      test_date: Date.add(Date.utc_today(), 10),
      scope: %{"chapter_ids" => []},
      user_role_id: user_role.id,
      course_id: course.id
    }

    {:ok, schedule} = Assessments.create_test_schedule(Map.merge(defaults, attrs))
    schedule
  end

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter} =
      FunSheep.Courses.create_chapter(%{
        name: "Chapter 1",
        position: 1,
        course_id: course.id
      })

    %{user_role: user_role, course: course, chapter: chapter}
  end

  describe "index" do
    test "renders test list page", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests")

      assert html =~ "Assessments"
      assert html =~ "New Test"
    end

    test "displays scheduled tests", %{conn: conn, user_role: ur, course: c, chapter: ch} do
      {:ok, _schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Biology Midterm",
          test_date: Date.add(Date.utc_today(), 5),
          scope: %{"chapter_ids" => [ch.id]},
          user_role_id: ur.id,
          course_id: c.id
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests")

      assert html =~ "Biology Midterm"
      assert html =~ c.name
    end

    test "shows empty state when no tests", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests")

      assert html =~ "No tests yet"
    end

    test "shows scope chapters in the schedule card", %{
      conn: conn,
      user_role: ur,
      course: c,
      chapter: ch
    } do
      create_schedule(ur, c, %{
        name: "Scoped Exam",
        scope: %{"chapter_ids" => [ch.id]}
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests")

      assert html =~ "Scoped Exam"
      assert html =~ "Chapter 1"
    end

    test "shows days remaining for upcoming tests", %{conn: conn, user_role: ur, course: c} do
      create_schedule(ur, c, %{name: "Future Test", test_date: Date.add(Date.utc_today(), 15)})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests")

      assert html =~ "15"
      assert html =~ "days left"
    end

    test "shows urgency color for test within 3 days", %{conn: conn, user_role: ur, course: c} do
      create_schedule(ur, c, %{name: "Urgent Test", test_date: Date.add(Date.utc_today(), 2)})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests")

      # Red urgency color class
      assert html =~ "FF3B30"
    end

    test "shows yellow urgency color for test within 7 days", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      create_schedule(ur, c, %{name: "Soon Test", test_date: Date.add(Date.utc_today(), 5)})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests")

      assert html =~ "FFCC00"
    end

    test "shows green urgency color for test more than 7 days away", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      create_schedule(ur, c, %{name: "Far Test", test_date: Date.add(Date.utc_today(), 20)})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests")

      assert html =~ "4CD964"
    end

    test "shows action buttons for each schedule", %{conn: conn, user_role: ur, course: c} do
      create_schedule(ur, c, %{name: "Actionable Test"})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests")

      assert html =~ "View Readiness"
      assert html =~ "Assess"
    end

    test "shows readiness score for a test schedule (computed live)", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      create_schedule(ur, c, %{name: "Readiness Test"})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests")

      # Readiness is computed live and always shown (even if 0%)
      assert html =~ "readiness"
    end

    test "shows negative days for past tests", %{conn: conn, user_role: ur, course: c} do
      create_schedule(ur, c, %{name: "Past Exam", test_date: Date.add(Date.utc_today(), -3)})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests")

      assert html =~ "Past Exam"
      assert html =~ "-3"
    end
  end

  describe "delete" do
    test "deletes a test schedule and removes it from the list", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      schedule = create_schedule(ur, c, %{name: "Schedule To Delete"})
      conn = auth_conn(conn, ur)
      {:ok, view, html} = live(conn, ~p"/courses/#{c.id}/tests")

      assert html =~ "Schedule To Delete"

      view
      |> element("button[phx-click='delete'][phx-value-id='#{schedule.id}']")
      |> render_click()

      html = render(view)
      refute html =~ "Schedule To Delete"
    end

    test "shows empty state after deleting the only schedule", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      schedule = create_schedule(ur, c, %{name: "Only Schedule"})
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests")

      view
      |> element("button[phx-click='delete'][phx-value-id='#{schedule.id}']")
      |> render_click()

      html = render(view)
      assert html =~ "No tests yet"
    end
  end

  describe "new test form" do
    test "renders schedule form", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      assert html =~ "New Test"
      assert html =~ "Test Name"
      assert html =~ "Course"
      assert html =~ "Test Date"
    end

    test "shows chapters on page load", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      assert html =~ "Chapter 1"
      assert html =~ "Test Scope"
    end
  end
end
