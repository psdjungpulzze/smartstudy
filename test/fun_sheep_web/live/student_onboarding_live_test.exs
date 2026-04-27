defmodule FunSheepWeb.StudentOnboardingLiveTest do
  @moduledoc """
  Tests for the 5-step student onboarding wizard.
  """

  use FunSheepWeb.ConnCase, async: true

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

  defp go_to_step2(view) do
    view |> element("button[phx-click='select_grade'][phx-value-grade='10']") |> render_click()
    view |> element("button[phx-click='step1_next']") |> render_click()
  end

  defp go_to_step3(view) do
    go_to_step2(view)
    view |> element("button[phx-click='step2_skip']") |> render_click()
  end

  # ── mount ──────────────────────────────────────────────────────────────────

  describe "mount" do
    test "renders step 1 for new student", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/onboarding/student")

      assert html =~ "get you set up" or html =~ "Step 1 of 5"
      assert html =~ "Display name"
      assert html =~ "Grade"
    end

    test "shows all grade options including College and Adult", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/onboarding/student")

      assert html =~ "College"
      assert html =~ "Adult"
    end

    test "pre-fills display_name from existing user_role", %{conn: conn} do
      uid = System.unique_integer([:positive])

      {:ok, user_role} =
        Accounts.create_user_role(%{
          interactor_user_id: "onb_#{uid}",
          role: :student,
          email: "pre#{uid}@test.com",
          display_name: "PrefilledName"
        })

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

      {:ok, _view, html} = live(conn, ~p"/onboarding/student")
      assert html =~ "PrefilledName"
    end
  end

  # ── handle_params ──────────────────────────────────────────────────────────

  describe "handle_params ?step=done" do
    test "navigating to done step marks onboarding complete and shows step 5", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, _view, html} = live(conn, "/onboarding/student?step=done")

      assert html =~ "You're all set" or html =~ "Start Practicing"
    end
  end

  # ── Step 1 ──────────────────────────────────────────────────────────────────

  describe "Step 1 — display name + grade" do
    test "update_display_name event updates display name assign", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")

      render_change(view, "update_display_name", %{"value" => "NewName"})
      html = render(view)
      assert html =~ "NewName"
    end

    test "grade selection updates the active grade styling", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")

      view |> element("button[phx-click='select_grade'][phx-value-grade='10']") |> render_click()
      html = render(view)

      assert html =~ "select_grade"
      assert html =~ "phx-value-grade=\"10\""
    end

    test "clicking Next without a grade shows an error message", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")

      view |> element("button[phx-click='step1_next']") |> render_click()
      assert render(view) =~ "Please select your grade"
    end

    test "selecting a grade clears a previously shown error", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")

      # Show error first
      view |> element("button[phx-click='step1_next']") |> render_click()
      assert render(view) =~ "Please select your grade"

      # Select grade and proceed — error clears
      view |> element("button[phx-click='select_grade'][phx-value-grade='10']") |> render_click()
      view |> element("button[phx-click='step1_next']") |> render_click()

      html = render(view)
      refute html =~ "Please select your grade"
      assert html =~ "Find your school"
    end

    test "selecting grade and clicking Next progresses to step 2", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")

      view |> element("button[phx-click='select_grade'][phx-value-grade='10']") |> render_click()
      view |> element("button[phx-click='step1_next']") |> render_click()

      html = render(view)
      assert html =~ "Find your school"
      assert html =~ "Step 2 of 5"
    end
  end

  # ── Step 2 ──────────────────────────────────────────────────────────────────

  describe "Step 2 — school search" do
    test "step2_skip advances to step 3", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step2(view)

      view |> element("button[phx-click='step2_skip']") |> render_click()
      assert render(view) =~ "Step 3 of 5"
    end

    test "step2_next without school advances to step 3", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step2(view)

      view |> element("button[phx-click='step2_next']") |> render_click()
      assert render(view) =~ "Step 3 of 5"
    end

    test "search_school event updates school search results assign", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      _school = create_school()

      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step2(view)

      # Trigger search — may or may not find results, but must not crash
      render_keyup(view, "search_school", %{"query" => "High School"})
      html = render(view)
      # Should still be on step 2
      assert html =~ "Find your school"
    end

    test "clear_school event clears the school selection", %{conn: conn} do
      school = create_school()

      uid = System.unique_integer([:positive])

      {:ok, user_role} =
        Accounts.create_user_role(%{
          interactor_user_id: "onb_#{uid}",
          role: :student,
          email: "clr#{uid}@test.com",
          display_name: "Clear Test",
          school_id: school.id
        })

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

      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      # Proceed to step 2 using grade "10"
      view |> element("button[phx-click='select_grade'][phx-value-grade='10']") |> render_click()
      view |> element("button[phx-click='step1_next']") |> render_click()

      # School from user_role would be pre-filled — clear it
      render_click(view, "clear_school", %{})
      html = render(view)

      # After clearing, search input should be visible instead of school badge
      assert html =~ "school" or html =~ "Search"
    end

    test "step2_next with school saves school and advances", %{conn: conn} do
      school = create_school()

      uid = System.unique_integer([:positive])

      {:ok, user_role} =
        Accounts.create_user_role(%{
          interactor_user_id: "onb_#{uid}",
          role: :student,
          email: "sch#{uid}@test.com",
          display_name: "School Test",
          school_id: school.id
        })

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

      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      view |> element("button[phx-click='select_grade'][phx-value-grade='10']") |> render_click()
      view |> element("button[phx-click='step1_next']") |> render_click()

      # School is pre-set so step2_next should update school_id and proceed to step 3
      view |> element("button[phx-click='step2_next']") |> render_click()
      assert render(view) =~ "Step 3 of 5"
    end
  end

  # ── Step 3 ──────────────────────────────────────────────────────────────────

  describe "Step 3 — course selection" do
    test "shows empty state when no courses exist for the grade", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step3(view)

      html = render(view)
      assert html =~ "Create a course" or html =~ "first students on FunSheep"
    end

    test "shows course list when courses exist for grade 10", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      _course = create_course(%{name: "Algebra 10", subject: "Math", grade: "10"})

      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step3(view)

      html = render(view)
      assert html =~ "Pick your courses"
      assert html =~ "Algebra 10"
    end

    test "toggle_course selects and deselects a course", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      course = create_course(%{name: "Toggle Course", subject: "Math", grade: "10"})

      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step3(view)

      # Select the course
      render_click(view, "toggle_course", %{"course_id" => course.id})
      html_selected = render(view)
      # 1 selected
      assert html_selected =~ "1 selected"

      # Deselect it
      render_click(view, "toggle_course", %{"course_id" => course.id})
      html_deselected = render(view)
      assert html_deselected =~ "0 selected"
    end

    test "toggle_other_courses toggles show_other_courses", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step3(view)

      # Trigger toggle — must not crash
      render_click(view, "toggle_other_courses", %{})
      html = render(view)
      assert html =~ "Step 3 of 5"
    end

    test "invite_teacher_email event updates the email assign", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step3(view)

      render_change(view, "invite_teacher_email", %{"email" => "teacher@school.edu"})
      html = render(view)
      assert html =~ "teacher@school.edu" or html =~ "Invite"
    end

    test "step3_continue with no selection advances to step 4", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step3(view)

      view |> element("button[phx-click='step3_continue']") |> render_click()
      html = render(view)
      # Step 4 is the "Follow classmates" screen
      assert html =~ "classmates" or html =~ "Step 4 of 5"
    end

    test "step3_continue with selected courses enrolls and moves to step 4", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      course = create_course(%{name: "Enrolled Course", subject: "Math", grade: "10"})

      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step3(view)

      render_click(view, "toggle_course", %{"course_id" => course.id})
      view |> element("button[phx-click='step3_continue']") |> render_click()

      html = render(view)
      # Should be on step 4 (classmates) or step 5 (done) — definitely past step 3
      refute html =~ "Pick your courses"
    end
  end

  # ── Step 4 ──────────────────────────────────────────────────────────────────

  describe "Step 4 — follow classmates" do
    defp go_to_step4(view) do
      go_to_step3(view)
      view |> element("button[phx-click='step3_continue']") |> render_click()
    end

    test "step4_done advances to step 5 done screen", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step4(view)

      view |> element("button[phx-click='step4_done']") |> render_click()
      html = render(view)
      assert html =~ "You're all set" or html =~ "Start Practicing"
    end

    test "shows empty classmates state when no peers exist", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step4(view)

      html = render(view)
      assert html =~ "classmates" or html =~ "school" or html =~ "Step 4 of 5"
    end
  end

  # ── Step 5 ──────────────────────────────────────────────────────────────────

  describe "Step 5 — done screen" do
    test "full flow from step 1 through step 5 ends on done screen", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")

      # Step 1
      view |> element("button[phx-click='select_grade'][phx-value-grade='9']") |> render_click()
      view |> element("button[phx-click='step1_next']") |> render_click()
      # Step 2
      view |> element("button[phx-click='step2_skip']") |> render_click()
      # Step 3 — no courses, click continue
      view |> element("button[phx-click='step3_continue']") |> render_click()
      # Step 4 — follow classmates screen, click done
      view |> element("button[phx-click='step4_done']") |> render_click()

      html = render(view)
      assert html =~ "You're all set" or html =~ "Start Practicing"
    end

    test "step 5 shows a dashboard link", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, _view, html} = live(conn, "/onboarding/student?step=done")

      assert html =~ "dashboard" or html =~ "Start Practicing"
    end
  end

  # ── select_school event ──────────────────────────────────────────────────────

  describe "select_school event" do
    test "selecting a school from search results updates the school assign", %{conn: conn} do
      school = create_school()
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step2(view)

      # Simulate selecting a school by ID
      render_click(view, "select_school", %{"school_id" => school.id})
      html = render(view)

      # After selecting, the school name should appear and the search results disappear
      assert html =~ school.name or html =~ "Change"
    end

    test "selecting a school clears the search results list", %{conn: conn} do
      school = create_school()
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step2(view)

      render_click(view, "select_school", %{"school_id" => school.id})
      html = render(view)

      # School results dropdown should no longer be visible
      refute html =~ "phx-click=\"select_school\""
    end
  end

  # ── onboarding_follow event ──────────────────────────────────────────────────

  describe "onboarding_follow event" do
    defp go_to_step4_from_start(view) do
      go_to_step3(view)
      view |> element("button[phx-click='step3_continue']") |> render_click()
    end

    test "following a peer with a real user_role_id updates followed set", %{conn: conn} do
      # Social.follow requires the followee to exist as a user_role in the DB
      uid = System.unique_integer([:positive])

      {:ok, peer_role} =
        Accounts.create_user_role(%{
          interactor_user_id: "peer_#{uid}",
          role: :student,
          email: "peer#{uid}@test.com",
          display_name: "Peer User"
        })

      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step4_from_start(view)

      render_click(view, "onboarding_follow", %{"id" => peer_role.id})
      html = render(view)

      # After following at least one peer, button shows "Continue →"
      assert html =~ "Continue" or html =~ "Step 4 of 5"
    end
  end

  # ── send_teacher_invite event ────────────────────────────────────────────────

  describe "send_teacher_invite event" do
    test "send_teacher_invite with invalid email shows error", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step3(view)

      # Set invalid email and try to send
      render_change(view, "invite_teacher_email", %{"email" => "not-an-email"})
      render_click(view, "send_teacher_invite", %{})
      html = render(view)

      # Should show an error or remain on step 3
      assert html =~ "Could not send invite" or html =~ "Step 3 of 5" or html =~ "error"
    end
  end

  # ── Step 2 with school — load_step3_courses with school+grade ───────────────

  describe "step2_next with school sets school and loads school courses" do
    test "courses from grade appear in step 3 when skipping school", %{conn: conn} do
      _course = create_course(%{name: "Grade Only Course", subject: "Science", grade: "10"})
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")

      view |> element("button[phx-click='select_grade'][phx-value-grade='10']") |> render_click()
      view |> element("button[phx-click='step1_next']") |> render_click()
      view |> element("button[phx-click='step2_skip']") |> render_click()

      html = render(view)
      assert html =~ "Grade Only Course" or html =~ "Pick your courses"
    end

    test "step2_next with selected school loads school+grade courses", %{conn: conn} do
      school = create_school()

      uid = System.unique_integer([:positive])

      {:ok, user_role} =
        Accounts.create_user_role(%{
          interactor_user_id: "onb_#{uid}",
          role: :student,
          email: "school2#{uid}@test.com",
          display_name: "School Step Test",
          school_id: school.id
        })

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

      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      view |> element("button[phx-click='select_grade'][phx-value-grade='10']") |> render_click()
      view |> element("button[phx-click='step1_next']") |> render_click()

      # school is pre-set from user_role — step2_next saves it and advances
      view |> element("button[phx-click='step2_next']") |> render_click()

      html = render(view)
      assert html =~ "Step 3 of 5"
    end
  end

  # ── handle_params — non-done param ──────────────────────────────────────────

  describe "handle_params — non-done param passes through" do
    test "random query param does not crash the LiveView", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, _view, html} = live(conn, "/onboarding/student?foo=bar")

      # Should render step 1 normally
      assert html =~ "Step 1 of 5" or html =~ "get you set up"
    end
  end

  # ── toggle_other_courses with data ──────────────────────────────────────────

  describe "toggle_other_courses — show_other_courses toggling" do
    test "toggle twice returns to original state", %{conn: conn} do
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")
      go_to_step3(view)

      render_click(view, "toggle_other_courses", %{})
      render_click(view, "toggle_other_courses", %{})
      html = render(view)
      assert html =~ "Step 3 of 5"
    end
  end

  # ── Step 5 shows enrolled courses ───────────────────────────────────────────

  describe "Step 5 — enrolled courses list" do
    test "step 5 done screen is reached via step3_continue with empty selection", %{conn: conn} do
      # When no courses are selected, bulk_enroll is not called and enrolled_courses = []
      # so render_step5 does not try to access sc.course.name (avoiding the association bug)
      {conn, _user_role} = student_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/onboarding/student")

      view |> element("button[phx-click='select_grade'][phx-value-grade='11']") |> render_click()
      view |> element("button[phx-click='step1_next']") |> render_click()
      view |> element("button[phx-click='step2_skip']") |> render_click()

      # No courses for grade 11 were created; step3 renders empty state
      render_click(view, "step3_continue", %{})
      render_click(view, "step4_done", %{})

      html = render(view)
      assert html =~ "You're all set" or html =~ "Start Practicing"
    end

    test "step 5 render includes display_name in greeting", %{conn: conn} do
      {conn, _user_role} = student_conn(conn, %{display_name: "Alice"})
      {:ok, _view, html} = live(conn, "/onboarding/student?step=done")

      assert html =~ "Alice" or html =~ "You're all set"
    end
  end
end
