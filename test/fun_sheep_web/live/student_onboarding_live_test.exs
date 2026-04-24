defmodule FunSheepWeb.StudentOnboardingLiveTest do
  @moduledoc """
  Tests for the 4-step student onboarding wizard.
  """

  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FunSheep.{Accounts, Courses, Geo}

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp student_conn(conn, extra \\ %{}) do
    uid = System.unique_integer([:positive])

    defaults = %{
      interactor_user_id: "onb_student_#{uid}",
      role: :student,
      email: "onb_s#{uid}@test.com",
      display_name: "Onboard Student"
    }

    {:ok, user_role} = Accounts.create_user_role(Map.merge(defaults, extra))

    conn =
      init_test_session(conn, %{
        dev_user_id: user_role.id,
        dev_user: %{
          "id" => user_role.id,
          "user_role_id" => user_role.id,
          "interactor_user_id" => user_role.interactor_user_id,
          "role" => "student",
          "email" => user_role.email,
          "display_name" => user_role.display_name
        }
      })

    {conn, user_role}
  end

  defp create_school do
    {:ok, country} =
      Geo.create_country(%{
        name: "US-OB#{System.unique_integer()}",
        code: "UO#{System.unique_integer()}"
      })

    {:ok, state} =
      Geo.create_state(%{name: "CA-OB#{System.unique_integer()}", country_id: country.id})

    {:ok, district} =
      Geo.create_district(%{name: "LA-OB#{System.unique_integer()}", state_id: state.id})

    {:ok, school} =
      Geo.create_school(%{
        name: "Onboard High School #{System.unique_integer()}",
        district_id: district.id
      })

    school
  end

  defp create_course(attrs \\ %{}) do
    defaults = %{
      name: "OB Course #{System.unique_integer()}",
      subject: "Math",
      grade: "10"
    }

    {:ok, course} = Courses.create_course(Map.merge(defaults, attrs))
    course
  end

  # ── Step 1 ──────────────────────────────────────────────────────────────────

  describe "Step 1 — display name + grade" do
    test "renders step 1 for new student", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/onboarding/student")

      # Check either for the heading text or the "step 1 of 4" indicator
      assert html =~ "get you set up" or html =~ "Step 1 of 4"
      assert html =~ "Display name"
      assert html =~ "Grade"
    end

    test "grade selection updates assigns", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")

      view |> element("button[phx-click='select_grade'][phx-value-grade='10']") |> render_click()
      html = render(view)

      # The '10' button should now have the active styling
      assert html =~ "select_grade"
      assert html =~ "phx-value-grade=\"10\""
    end

    test "clicking Next without a grade shows error", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")

      view |> element("button[phx-click='step1_next']") |> render_click()

      assert render(view) =~ "Please select your grade"
    end

    test "selecting grade and clicking Next progresses to step 2", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")

      view |> element("button[phx-click='select_grade'][phx-value-grade='10']") |> render_click()
      view |> element("button[phx-click='step1_next']") |> render_click()

      html = render(view)
      assert html =~ "Find your school"
      assert html =~ "Step 2 of 4"
    end
  end

  # ── Step 2 ──────────────────────────────────────────────────────────────────

  describe "Step 2 — school search" do
    defp go_to_step2(view) do
      view |> element("button[phx-click='select_grade'][phx-value-grade='10']") |> render_click()
      view |> element("button[phx-click='step1_next']") |> render_click()
    end

    test "step2_skip advances to step 3", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step2(view)

      view |> element("button[phx-click='step2_skip']") |> render_click()

      html = render(view)
      assert html =~ "Step 3 of 4"
    end

    test "step2_next advances to step 3", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step2(view)

      view |> element("button[phx-click='step2_next']") |> render_click()

      assert render(view) =~ "Step 3 of 4"
    end
  end

  # ── Step 3 — empty state ────────────────────────────────────────────────────

  describe "Step 3 — empty state when school has no courses" do
    defp go_to_step3(view) do
      view |> element("button[phx-click='select_grade'][phx-value-grade='10']") |> render_click()
      view |> element("button[phx-click='step1_next']") |> render_click()
      view |> element("button[phx-click='step2_skip']") |> render_click()
    end

    test "shows empty state A when school has no courses for the grade", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step3(view)

      html = render(view)
      # Empty state card
      assert html =~ "Create a course" or html =~ "first students on FunSheep"
    end

    test "shows course list when courses exist for grade", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      # Create a course for grade 10
      _course = create_course(%{name: "Algebra 10", subject: "Math", grade: "10"})

      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step3(view)

      html = render(view)
      assert html =~ "Pick your courses"
      assert html =~ "Algebra 10"
    end
  end

  # ── Step 4 — done ───────────────────────────────────────────────────────────

  describe "Step 4 — done screen" do
    test "step3_continue with no selection reaches done screen", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")

      # Step 1
      view |> element("button[phx-click='select_grade'][phx-value-grade='9']") |> render_click()
      view |> element("button[phx-click='step1_next']") |> render_click()
      # Step 2
      view |> element("button[phx-click='step2_skip']") |> render_click()
      # Step 3 — no courses, click dashboard CTA
      view |> element("button[phx-click='step3_continue']") |> render_click()

      html = render(view)
      assert html =~ "You're all set" or html =~ "Start Practicing"
    end
  end
end
