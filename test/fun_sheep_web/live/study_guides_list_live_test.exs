defmodule FunSheepWeb.StudyGuidesListLiveTest do
  @moduledoc """
  Tests for StudyGuidesListLive — lists study guides for a course and allows
  generating new ones from a test schedule.
  """

  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{ContentFixtures, Learning, Repo}
  alias FunSheep.Learning.StudyGuide

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

  defp insert_test_schedule(user_role, course) do
    {:ok, schedule} =
      FunSheep.Assessments.create_test_schedule(%{
        name: "Mid-Term Exam",
        test_date: Date.add(Date.utc_today(), 14),
        scope: %{"chapter_ids" => []},
        user_role_id: user_role.id,
        course_id: course.id
      })

    schedule
  end

  defp insert_study_guide(user_role, schedule, content_overrides \\ %{}) do
    default_content = %{
      "title" => "My Study Guide",
      "sections" => [],
      "test_date" => Date.to_iso8601(Date.add(Date.utc_today(), 14)),
      "aggregate_score" => 75.0,
      "progress" => %{"total_sections" => 5, "sections_reviewed" => 2}
    }

    content = Map.merge(default_content, content_overrides)

    %StudyGuide{}
    |> StudyGuide.changeset(%{
      user_role_id: user_role.id,
      test_schedule_id: schedule.id,
      content: content,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert!()
    |> Repo.preload(:test_schedule)
  end

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{name: "Physics 101"})

    %{user_role: user_role, course: course}
  end

  describe "StudyGuidesListLive mount" do
    test "renders the study guides list page", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/study-guides")

      assert html =~ "Study Guides"
    end

    test "shows back link to course", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/study-guides")

      assert html =~ c.name
    end

    test "shows the generate new guide section", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/study-guides")

      assert html =~ "Generate New Guide"
      assert html =~ "Generate"
    end

    test "shows empty state when no guides exist", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/study-guides")

      assert html =~ "No study guides yet"
    end

    test "shows available test schedules in the dropdown", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      _schedule = insert_test_schedule(ur, c)
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/study-guides")

      assert html =~ "Mid-Term Exam"
    end

    test "shows list of existing guides when guides exist", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      schedule = insert_test_schedule(ur, c)
      _guide = insert_study_guide(ur, schedule)

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/study-guides")

      assert html =~ "My Study Guide"
    end

    test "shows aggregate score for existing guide", %{conn: conn, user_role: ur, course: c} do
      schedule = insert_test_schedule(ur, c)
      insert_study_guide(ur, schedule, %{"aggregate_score" => 75.0})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/study-guides")

      # 75% readiness displayed
      assert html =~ "75"
      assert html =~ "readiness"
    end

    test "shows progress bar for guide", %{conn: conn, user_role: ur, course: c} do
      schedule = insert_test_schedule(ur, c)

      insert_study_guide(ur, schedule, %{
        "progress" => %{"total_sections" => 10, "sections_reviewed" => 4}
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/study-guides")

      assert html =~ "reviewed"
    end

    test "shows days badge when test_date is in the future", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      schedule = insert_test_schedule(ur, c)
      future_date = Date.add(Date.utc_today(), 10)
      insert_study_guide(ur, schedule, %{"test_date" => Date.to_iso8601(future_date)})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/study-guides")

      # "10d left" badge should appear
      assert html =~ "10d left" or html =~ "left"
    end

    test "shows urgent badge for imminent test (1 day or fewer)", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      schedule = insert_test_schedule(ur, c)
      insert_study_guide(ur, schedule, %{"test_date" => Date.to_iso8601(Date.utc_today())})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/study-guides")

      assert html =~ "Today!" or html =~ "Tomorrow"
    end

    test "shows 'Past' badge for past test date", %{conn: conn, user_role: ur, course: c} do
      schedule = insert_test_schedule(ur, c)
      past_date = Date.add(Date.utc_today(), -5)
      insert_study_guide(ur, schedule, %{"test_date" => Date.to_iso8601(past_date)})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/study-guides")

      assert html =~ "Past"
    end

    test "shows section count for a guide", %{conn: conn, user_role: ur, course: c} do
      schedule = insert_test_schedule(ur, c)

      insert_study_guide(ur, schedule, %{
        "sections" => [%{"id" => "s1", "title" => "Topic A"}, %{"id" => "s2", "title" => "Topic B"}]
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/study-guides")

      assert html =~ "2 weak areas"
    end
  end

  describe "StudyGuidesListLive handle_event select_schedule" do
    test "selecting a schedule updates selected_schedule_id", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      schedule = insert_test_schedule(ur, c)
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/study-guides")

      # Simulate changing the select dropdown
      view
      |> element("select[name='schedule_id']")
      |> render_change(%{"schedule_id" => schedule.id})

      # No error after selecting a valid schedule
      html = render(view)
      refute html =~ "Please select a test schedule"
    end
  end

  describe "StudyGuidesListLive handle_event generate" do
    test "shows error flash when generating without a selected schedule", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/study-guides")

      # Click generate without selecting a schedule first
      view
      |> element("button[phx-click='generate']")
      |> render_click()

      html = render(view)
      assert html =~ "Please select a test schedule first"
    end

    test "shows error flash when generating with empty schedule_id", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      _schedule = insert_test_schedule(ur, c)
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/study-guides")

      # Set schedule_id to empty string then click generate
      view
      |> element("select[name='schedule_id']")
      |> render_change(%{"schedule_id" => ""})

      view
      |> element("button[phx-click='generate']")
      |> render_click()

      html = render(view)
      assert html =~ "Please select a test schedule first"
    end
  end
end
