defmodule FunSheepWeb.TestDatePickerComponentTest do
  @moduledoc """
  Tests for TestDatePickerComponent via the course_detail route, which embeds
  the component when the course has a catalog_test_type and no upcoming tests.
  """

  use FunSheepWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias FunSheep.{ContentFixtures, Repo}
  alias FunSheep.Assessments.TestSchedule
  alias FunSheep.Courses.KnownTestDate

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

  defp create_sat_course do
    {:ok, course} =
      %FunSheep.Courses.Course{}
      |> FunSheep.Courses.Course.changeset(%{
        name: "SAT Prep",
        subject: "Mathematics",
        grades: ["11"],
        catalog_test_type: "sat",
        access_level: "public"
      })
      |> Repo.insert()

    course
  end

  defp create_known_date(attrs \\ %{}) do
    defaults = %{
      test_type: "sat",
      test_name: "SAT Spring #{System.unique_integer([:positive])}",
      test_date: Date.add(Date.utc_today(), 90),
      region: "us"
    }

    {:ok, kd} =
      %KnownTestDate{}
      |> KnownTestDate.changeset(Map.merge(defaults, attrs))
      |> Repo.insert()

    kd
  end

  setup do
    user_role = ContentFixtures.create_user_role()
    course = create_sat_course()
    %{user_role: user_role, course: course}
  end

  describe "component renders" do
    test "date picker shows when course has catalog_test_type and no tests", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}")

      assert html =~ "When is your test?"
    end

    test "shows official dates when known dates exist", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      _kd = create_known_date(%{test_name: "SAT March 2027"})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}")

      assert html =~ "SAT March 2027"
      assert html =~ "Official SAT Dates"
    end

    test "shows custom date option when no known dates", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}")

      assert html =~ "Set a custom date"
    end

    test "shows fallback when no official dates", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}")

      assert html =~ "No upcoming official dates found yet"
    end
  end

  describe "show_custom_form event" do
    test "clicking custom date button reveals the form", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}")

      html =
        view
        |> element("button[phx-click='show_custom_form']")
        |> render_click()

      assert html =~ "Custom test date"
      assert html =~ "Test name"
      assert html =~ "Test date"
    end

    test "cancel button hides the custom form", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}")

      view |> element("button[phx-click='show_custom_form']") |> render_click()

      html =
        view
        |> element("button[phx-click='hide_custom_form']")
        |> render_click()

      assert html =~ "Set a custom date"
      refute html =~ "Custom test date"
    end
  end

  describe "save_custom_date event" do
    test "saves a custom date and creates a TestSchedule", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}")

      view |> element("button[phx-click='show_custom_form']") |> render_click()

      view
      |> element("input[phx-change='update_custom_name']")
      |> render_change(%{"value" => "My AP Test"})

      view
      |> element("input[phx-change='update_custom_date']")
      |> render_change(%{"value" => Date.to_iso8601(Date.add(Date.utc_today(), 60))})

      view
      |> element("button[phx-click='save_custom_date']")
      |> render_click()

      # Verify the TestSchedule was persisted to the database.
      # (Parent handle_info re-render may lag behind render_click return, so check DB directly.)
      schedules =
        Repo.all(
          from s in TestSchedule,
            where: s.user_role_id == ^ur.id and s.course_id == ^c.id
        )

      assert length(schedules) > 0
    end

    test "shows error for invalid date", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}")

      view |> element("button[phx-click='show_custom_form']") |> render_click()

      view
      |> element("input[phx-change='update_custom_name']")
      |> render_change(%{"value" => "Test"})

      view
      |> element("input[phx-change='update_custom_date']")
      |> render_change(%{"value" => "not-a-date"})

      html =
        view
        |> element("button[phx-click='save_custom_date']")
        |> render_click()

      assert html =~ "valid date"
    end
  end

  describe "pick_official_date event" do
    test "selecting an official date creates a TestSchedule", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      kd = create_known_date(%{test_name: "SAT October 2027"})

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}")

      view
      |> element("button[phx-value-known_test_date_id='#{kd.id}']")
      |> render_click()

      # Verify the TestSchedule was persisted. Parent handle_info re-render may lag behind
      # render_click's return, so assert against the DB rather than the returned HTML.
      schedules =
        Repo.all(
          from s in TestSchedule,
            where: s.user_role_id == ^ur.id and s.course_id == ^c.id
        )

      assert length(schedules) > 0
    end

    test "shows error for unknown date id", %{conn: conn, user_role: ur, course: c} do
      _kd = create_known_date()

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}")

      html =
        view
        |> element("button[phx-click='pick_official_date']")
        |> render_click(%{"known_test_date_id" => Ecto.UUID.generate()})

      assert html =~ "Date not found"
    end
  end
end
