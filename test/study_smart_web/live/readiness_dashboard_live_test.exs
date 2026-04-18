defmodule StudySmartWeb.ReadinessDashboardLiveTest do
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

    {:ok, schedule} =
      StudySmart.Assessments.create_test_schedule(%{
        name: "Biology Midterm",
        test_date: Date.add(Date.utc_today(), 5),
        scope: %{"chapter_ids" => [chapter.id]},
        user_role_id: user_role.id,
        course_id: course.id
      })

    %{user_role: user_role, course: course, chapter: chapter, schedule: schedule}
  end

  describe "readiness dashboard" do
    test "renders with test info", %{conn: conn, user_role: ur, schedule: schedule, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/tests/#{schedule.id}/readiness")

      assert html =~ "Biology Midterm"
      assert html =~ c.name
      assert html =~ "days left"
    end

    test "shows chapter breakdown", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/tests/#{schedule.id}/readiness")

      assert html =~ "Chapter Breakdown"
      assert html =~ "Chapter 1"
    end

    test "shows aggregate score", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/tests/#{schedule.id}/readiness")

      # Default score is 0%
      assert html =~ "0%"
    end

    test "shows action buttons", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/tests/#{schedule.id}/readiness")

      assert html =~ "Start Assessment"
      assert html =~ "Generate Study Guide"
      assert html =~ "Recalculate Readiness"
    end

    test "recalculate readiness creates score", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/tests/#{schedule.id}/readiness")

      render_click(view, "calculate_readiness")

      # Verify score was created in the database
      assert StudySmart.Assessments.latest_readiness(ur.id, schedule.id) != nil

      # Flash is rendered in the layout; verify the view still renders
      html = render(view)
      assert html =~ "Score History"
    end
  end
end
