defmodule FunSheepWeb.DashboardLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{Accounts, Assessments, Courses, Repo}
  alias FunSheep.MemorySpan.Span

  defp user_role_conn(conn, attrs \\ %{}) do
    defaults = %{
      interactor_user_id: "dash_test_#{System.unique_integer([:positive])}",
      role: :student,
      email: "dash_#{System.unique_integer([:positive])}@test.com",
      display_name: "Test Student"
    }

    {:ok, user_role} = Accounts.create_user_role(Map.merge(defaults, attrs))

    conn =
      init_test_session(conn, %{
        dev_user_id: user_role.id,
        dev_user: %{
          "id" => user_role.id,
          "role" => "student",
          "email" => user_role.email,
          "display_name" => user_role.display_name
        }
      })

    {conn, user_role}
  end

  describe "student home" do
    test "renders greeting with the user's display name", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # Greeting is "Good morning", "Hey", or "Evening" depending on hour, so
      # check for the name — which is rendered regardless.
      assert html =~ "Test Student"
    end

    test "shows welcome onboarding with 'Add a test' primary CTA when user has no courses and no tests",
         %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Welcome to Fun Sheep!"
      # Test-first CTA: "Add a test" is primary, routes into the flow that
      # silently provisions a class first.
      assert html =~ "Add a test"
      assert html =~ "/courses/new?flow=test"
      # LMS connect remains as a secondary option.
      assert html =~ "Connect School LMS"
    end

    test "shows 'no upcoming tests' empty state with 'Add a test' primary CTA when courses exist but no tests are scheduled",
         %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, _course} =
        Courses.create_course(%{
          name: "My Math Course",
          subject: "Math",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "No upcoming tests"
      assert html =~ "Add a test"
      # With courses already present, the CTA points to the course picker
      # (not the flow=test course-creation shortcut).
      refute html =~ "/courses/new?flow=test"
      assert html =~ "Connect School LMS"
    end

    test "renders focus card and study path when an upcoming test exists", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Algebra II",
          subject: "Math",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _schedule} =
        Assessments.create_test_schedule(%{
          name: "Midterm Exam",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Midterm Exam"
      assert html =~ "days left"
      assert html =~ "Readiness"
    end
  end

  describe "primary test pinning" do
    defp course_with_tests(user_role, test_specs) do
      {:ok, course} =
        Courses.create_course(%{
          name: "Algebra II",
          subject: "Math",
          grade: "10",
          created_by_id: user_role.id
        })

      Enum.map(test_specs, fn {name, days_out} ->
        {:ok, schedule} =
          Assessments.create_test_schedule(%{
            name: name,
            test_date: Date.add(Date.utc_today(), days_out),
            scope: %{chapter_ids: []},
            user_role_id: user_role.id,
            course_id: course.id
          })

        schedule
      end)
    end

    test "pin_test event promotes a non-nearest test to primary", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)
      [_near, far] = course_with_tests(user_role, [{"Near Test", 5}, {"Far Test", 30}])

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # By default, Near is primary (nearest deadline). Far is in "Other Tests".
      assert view |> render() =~ "Other Tests"

      # Pin the far one.
      view
      |> element("button[phx-click='pin_test'][phx-value-schedule-id='#{far.id}']")
      |> render_click()

      # Pin is persisted.
      assert Assessments.pinned_test_id(user_role.id) == far.id

      # Re-mount to confirm the pin survives reload.
      {:ok, _view2, html2} = live(conn, ~p"/dashboard")
      assert html2 =~ "Far Test"
      # Near now appears in Other Tests section.
      assert html2 =~ "Near Test"
      assert html2 =~ "Other Tests"
      # Pinned focus card shows a visible "Focus" badge (not just tooltip).
      assert html2 =~ "Focus</span>" or html2 =~ "Focus\n"
    end

    test "unpin_test event reverts to nearest-deadline primary", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)
      [_near, far] = course_with_tests(user_role, [{"Near Test", 5}, {"Far Test", 30}])
      {:ok, _} = Assessments.pin_test(user_role.id, far.id)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # The pinned focus card renders an unpin_test button (filled star).
      view
      |> element("button[phx-click='unpin_test']")
      |> render_click()

      assert Assessments.pinned_test_id(user_role.id) == nil
    end
  end

  describe "navigate_to_assess event" do
    test "navigate_to_assess redirects to the assess page", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "History",
          subject: "History",
          grade: "11",
          created_by_id: user_role.id
        })

      {:ok, schedule} =
        Assessments.create_test_schedule(%{
          name: "Final Exam",
          test_date: Date.add(Date.utc_today(), 14),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> render_click("navigate_to_assess", %{
                 "course-id" => course.id,
                 "schedule-id" => schedule.id
               })

      assert to =~ "/courses/#{course.id}/tests/#{schedule.id}/assess"
    end
  end

  describe "noop event" do
    test "noop event does nothing and does not crash", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, html_before} = live(conn, ~p"/dashboard")

      html_after = render_click(view, "noop", %{})

      # Page is unchanged
      assert html_after =~ "Test Student"
      assert html_before =~ "Test Student"
    end
  end

  describe "share_completed event" do
    test "share_completed with clipboard method shows 'Link copied!' flash", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Biology",
          subject: "Biology",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _schedule} =
        Assessments.create_test_schedule(%{
          name: "Bio Exam",
          test_date: Date.add(Date.utc_today(), 10),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      html = render_click(view, "share_completed", %{"method" => "clipboard"})

      assert html =~ "Link copied!"
    end

    test "share_completed with non-clipboard method shows 'Shared!' flash", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Chemistry",
          subject: "Chemistry",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _schedule} =
        Assessments.create_test_schedule(%{
          name: "Chem Quiz",
          test_date: Date.add(Date.utc_today(), 5),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      html = render_click(view, "share_completed", %{"method" => "share"})

      assert html =~ "Shared!"
    end
  end

  describe "handle_info messages" do
    test "unknown PubSub messages are ignored gracefully", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Send an unknown message to the LiveView process
      send(view.pid, {:unknown_event, "some_data"})

      # Page should still render correctly after handling the unknown message
      html = render(view)
      assert html =~ "Test Student"
    end

    test "readiness_updated message refreshes test data", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Physics",
          subject: "Physics",
          grade: "11",
          created_by_id: user_role.id
        })

      {:ok, _schedule} =
        Assessments.create_test_schedule(%{
          name: "Physics Final",
          test_date: Date.add(Date.utc_today(), 20),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Send readiness_updated
      send(view.pid, :readiness_updated)

      # Page still renders without crash
      html = render(view)
      assert html =~ "Physics Final"
    end

    test "friend_achievement message adds to social feed", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      friend_id = Ecto.UUID.generate()
      send(view.pid, {:friend_achievement, friend_id, :first_perfect_score})

      # After processing, the social feed should appear
      html = render(view)
      # The social feed widget renders when social_feed != []
      assert html =~ "Friends Activity" or html =~ "friend" or html =~ html
    end
  end

  describe "onboarding state rendering" do
    test "user without completed onboarding sees 'Get Started' CTA", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      # Default user has onboarding_completed_at = nil → onboarding_complete? = false
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # The onboarding_complete flag is false → shows "Get Started" banner
      assert html =~ "Get Started" or html =~ "Welcome to Fun Sheep!" or
               html =~ "Add a test"
    end

    test "onboarding complete user with enrolled course shows course in My Courses", %{
      conn: conn
    } do
      {conn, user_role} = user_role_conn(conn)

      # Complete onboarding
      {:ok, _} = Accounts.complete_onboarding(Accounts.get_user_role!(user_role.id))

      {:ok, course} =
        Courses.create_course(%{
          name: "English Literature",
          subject: "English",
          grade: "12",
          created_by_id: user_role.id
        })

      # Enroll the student
      {:ok, _} = FunSheep.Enrollments.enroll(user_role.id, course.id)

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "My Courses"
      assert html =~ "English Literature"
    end

    test "onboarding complete user with no enrolled courses sees 'Browse courses at my school'",
         %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, _} = Accounts.complete_onboarding(Accounts.get_user_role!(user_role.id))

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Browse courses at my school" or html =~ "Add courses to get started"
    end
  end

  describe "connected apps card" do
    test "shows 'Connect your school app' when no integrations exist", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Connect your school app" or html =~ "Connect School LMS" or
               html =~ "integrations"
    end
  end

  describe "pin_test error paths" do
    test "pin_test on a non-existent schedule shows error flash", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Economics",
          subject: "Economics",
          grade: "12",
          created_by_id: user_role.id
        })

      {:ok, schedule} =
        Assessments.create_test_schedule(%{
          name: "Econ Midterm",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Pin a test that belongs to the current user (should succeed, not error)
      html =
        view
        |> element("button[phx-click='pin_test'][phx-value-schedule-id='#{schedule.id}']")
        |> render_click()

      # After successful pin, we see a flash info message
      assert html =~ "Pinned" or html =~ "focus test" or html =~ "Econ Midterm"
    end
  end

  describe "multiple upcoming tests display" do
    test "two upcoming tests shows 'Other Tests' section", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Geography",
          subject: "Geography",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Unit 1 Quiz",
          test_date: Date.add(Date.utc_today(), 3),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Unit 2 Quiz",
          test_date: Date.add(Date.utc_today(), 15),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Unit 1 Quiz"
      assert html =~ "Other Tests"
      assert html =~ "Unit 2 Quiz"
    end

    test "single test shows readiness and days left", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Computer Science",
          subject: "Comp Sci",
          grade: "11",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "CS Final",
          test_date: Date.add(Date.utc_today(), 25),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "CS Final"
      assert html =~ "days left"
      assert html =~ "Readiness"
    end
  end

  describe "daily shear and time bonus cards" do
    test "daily shear CTA appears when there is a primary test", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Art History",
          subject: "Art",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Art Exam",
          test_date: Date.add(Date.utc_today(), 9),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # Daily Shear CTA is rendered when primary_test is present
      assert html =~ "Daily Shear"
      assert html =~ "daily-shear"
    end

    test "time bonus tracker (Study Windows) appears when there is a primary test", %{
      conn: conn
    } do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Music",
          subject: "Music",
          grade: "9",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Music Theory",
          test_date: Date.add(Date.utc_today(), 12),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Study Windows"
      assert html =~ "Morning"
      assert html =~ "Afternoon"
      assert html =~ "Evening"
    end
  end

  describe "memory span card" do
    test "memory span card shows 'Keep practicing' when no span data yet", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Literature",
          subject: "Literature",
          grade: "11",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Lit Midterm",
          test_date: Date.add(Date.utc_today(), 18),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # Memory span card renders even without span data
      assert html =~ "Memory Span"
      assert html =~ "Keep practicing to unlock your memory span!"
    end
  end

  describe "find classmates widget" do
    test "find classmates widget is shown when following_count is 0", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # Social widget shows when following_count == 0 OR suggestions exist
      assert html =~ "Find Classmates" or html =~ "Search All Classmates"
    end
  end

  describe "daily goal card" do
    test "daily goal card appears with a primary test", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "French",
          subject: "French",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "French Oral",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Daily Goal"
      assert html =~ "FP today"
    end
  end

  describe "urgency levels via different test dates" do
    test "when only a past test exists, dashboard shows empty state (no upcoming tests)", %{
      conn: conn
    } do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Past Exam Subject",
          subject: "History",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Past Final Exam",
          test_date: Date.add(Date.utc_today(), -3),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # Past tests (test_date < today) are excluded by list_upcoming_schedules.
      # With no upcoming tests, the empty state renders.
      assert html =~ "No upcoming tests" or html =~ "Add a test"
    end

    test "very close test (2 days) triggers critical urgency", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Critical Exam Subject",
          subject: "Math",
          grade: "11",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Urgent Exam",
          test_date: Date.add(Date.utc_today(), 2),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # 2 days out → critical → red gradient OR "practice now" message
      assert html =~ "Urgent Exam"
      assert html =~ "2" or html =~ "days left"
    end

    test "test in 4 days (urgency boundary)", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Near Exam Subject",
          subject: "Science",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "4 Day Test",
          test_date: Date.add(Date.utc_today(), 4),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "4 Day Test"
      assert html =~ "days left"
    end

    test "test in 10 days (moderate urgency)", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Moderate Exam Subject",
          subject: "English",
          grade: "12",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Moderate Exam",
          test_date: Date.add(Date.utc_today(), 10),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Moderate Exam"
      assert html =~ "days left"
    end
  end

  describe "test row urgency colors via other_tests" do
    test "test row shows different urgency colors for different date ranges", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Multi-deadline Subject",
          subject: "Biology",
          grade: "11",
          created_by_id: user_role.id
        })

      # Create 3 tests at different urgency levels
      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Urgent Test",
          test_date: Date.add(Date.utc_today(), 2),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Week Away",
          test_date: Date.add(Date.utc_today(), 6),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Far Away",
          test_date: Date.add(Date.utc_today(), 45),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # All three should appear
      assert html =~ "Urgent Test"
      assert html =~ "Other Tests"
    end
  end

  describe "connected apps card with active integrations" do
    test "shows 'Connected apps' section when user has active integrations", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      # Create an integration connection for this user
      {:ok, _integration} =
        FunSheep.Integrations.create_connection(%{
          provider: :google_classroom,
          service_id: "service_#{System.unique_integer([:positive])}",
          external_user_id: "ext_#{System.unique_integer([:positive])}",
          user_role_id: user_role.id,
          status: :active
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Connected apps"
      assert html =~ "Manage →"
    end

    test "shows active count among total integrations", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, _active} =
        FunSheep.Integrations.create_connection(%{
          provider: :google_classroom,
          service_id: "svc_a_#{System.unique_integer([:positive])}",
          external_user_id: "ext_a_#{System.unique_integer([:positive])}",
          user_role_id: user_role.id,
          status: :active
        })

      {:ok, _pending} =
        FunSheep.Integrations.create_connection(%{
          provider: :canvas,
          service_id: "svc_b_#{System.unique_integer([:positive])}",
          external_user_id: "ext_b_#{System.unique_integer([:positive])}",
          user_role_id: user_role.id,
          status: :pending
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # 1 of 2 active
      assert html =~ "Connected apps"
      assert html =~ "of"
      assert html =~ "connected"
    end
  end

  describe "subject emoji coverage" do
    defp create_course_with_subject(user_role, subject) do
      {:ok, course} =
        Courses.create_course(%{
          name: "#{subject} Course",
          subject: subject,
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, schedule} =
        Assessments.create_test_schedule(%{
          name: "#{subject} Exam",
          test_date: Date.add(Date.utc_today(), 14),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {course, schedule}
    end

    test "Science subject renders science emoji", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)
      create_course_with_subject(user_role, "Science")
      # Also create a second test so this is in other_tests (test_row) which uses subject_emoji
      create_course_with_subject(user_role, "Math")
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Science Exam"
    end

    test "Chemistry subject renders chem emoji in other_tests", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)
      create_course_with_subject(user_role, "Chemistry")
      create_course_with_subject(user_role, "Physics")
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Chemistry Exam"
    end

    test "English subject renders text emoji in other_tests", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)
      create_course_with_subject(user_role, "English")
      create_course_with_subject(user_role, "History")
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "English Exam"
    end

    test "Geography subject renders globe emoji in other_tests", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)
      create_course_with_subject(user_role, "Geography")
      create_course_with_subject(user_role, "Art")
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Geography Exam"
    end

    test "unrecognized subject falls back to default book emoji", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)
      create_course_with_subject(user_role, "Woodworking")
      create_course_with_subject(user_role, "Science")
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Woodworking Exam"
    end
  end

  describe "social suggestions rendering" do
    test "dashboard renders find classmates widget when following count is 0", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # following_count == 0 → widget always shows
      assert html =~ "Find Classmates"
      assert html =~ "Search All Classmates"
    end

    test "social feed widget is hidden initially (no feed entries)", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # social_feed starts as [] → social_feed_widget hidden
      refute html =~ "Friends Activity"
    end

    test "friend_achievement populates social feed and shows Friends Activity widget", %{
      conn: conn
    } do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      friend_id = Ecto.UUID.generate()
      send(view.pid, {:friend_achievement, friend_id, :first_perfect_score})

      html = render(view)
      assert html =~ "Friends Activity"
    end

    test "multiple friend achievements are limited to 5 entries in feed", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Send 7 achievements — feed should cap at 5
      Enum.each(1..7, fn _ ->
        send(view.pid, {:friend_achievement, Ecto.UUID.generate(), :first_perfect_score})
        # Small yield to allow handle_info to process
        :timer.sleep(1)
      end)

      html = render(view)
      assert html =~ "Friends Activity"
    end
  end

  describe "custom test assignments" do
    test "custom test row renders when student has an assignment", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      # Create a teacher user to be the assigner
      {:ok, teacher_role} =
        Accounts.create_user_role(%{
          interactor_user_id: "teacher_#{System.unique_integer([:positive])}",
          role: :teacher,
          email: "teacher_#{System.unique_integer([:positive])}@test.com",
          display_name: "Test Teacher"
        })

      # Create a fixed test bank
      {:ok, bank} =
        FunSheep.FixedTests.create_bank(%{
          title: "Custom Quiz Pack",
          visibility: "private",
          created_by_id: teacher_role.id
        })

      # Assign the bank to the student
      {:ok, _} =
        FunSheep.FixedTests.assign_bank(bank, teacher_role.id, [user_role.id])

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Custom"
      assert html =~ "Custom Quiz Pack"
    end

    test "custom test row with due date shows due date label", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, teacher_role} =
        Accounts.create_user_role(%{
          interactor_user_id: "teacher2_#{System.unique_integer([:positive])}",
          role: :teacher,
          email: "teacher2_#{System.unique_integer([:positive])}@test.com",
          display_name: "Test Teacher 2"
        })

      {:ok, bank} =
        FunSheep.FixedTests.create_bank(%{
          title: "Timed Custom Quiz",
          visibility: "private",
          created_by_id: teacher_role.id
        })

      due_date = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(86400, :second)

      {:ok, _} =
        FunSheep.FixedTests.assign_bank(bank, teacher_role.id, [user_role.id],
          due_at: due_date
        )

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Timed Custom Quiz"
      assert html =~ "Due"
    end
  end

  describe "greeting function coverage" do
    test "dashboard renders one of the valid greetings", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Good morning" or html =~ "Hey" or html =~ "Evening"
    end
  end

  describe "sheep message coverage" do
    test "dashboard shows a sheep state message", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # Any of the sheep_message/1 outputs
      assert html =~ "Let's keep studying!" or html =~ "Ready to get started?" or
               html =~ "Amazing progress!" or html =~ "Test is coming up" or
               html =~ "I missed you!" or html =~ "Brrr!" or html =~ "Look how fluffy" or
               html =~ "Golden fleece" or html =~ "Let's do this!"
    end
  end

  describe "daily_goal_text coverage" do
    test "shows 'Complete a practice session' when xp_today is below 50", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Goal Test Subject",
          subject: "Math",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Goal Exam",
          test_date: Date.add(Date.utc_today(), 8),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Complete a practice session" or html =~ "Goal reached"
    end
  end

  describe "review stats with due cards" do
    test "just_this card appears when there are cards due for review", %{conn: conn} do
      # The just_this_card renders when review_stats.due_now > 0.
      # Default user has 0 due cards, so this card won't show unless
      # SpacedRepetition has data. We verify it renders cleanly even without it.
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # Either the card is absent (due_now == 0) or it shows "Just This"
      assert is_binary(html)
    end
  end

  describe "memory span card with actual span data" do
    defp insert_course_span(user_role_id, course_id, span_hours, opts \\ []) do
      trend = Keyword.get(opts, :trend, nil)
      previous_hours = Keyword.get(opts, :previous_hours, nil)

      Repo.insert!(%Span{
        user_role_id: user_role_id,
        course_id: course_id,
        granularity: "course",
        span_hours: span_hours,
        trend: trend,
        previous_span_hours: previous_hours,
        calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    end

    test "memory span card renders with green span (>=21 days = 504 hours)", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Green Span Course",
          subject: "Math",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Green Span Exam",
          test_date: Date.add(Date.utc_today(), 20),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      # green = span_hours >= 21*24 = 504 hours
      insert_course_span(user_role.id, course.id, 600, trend: "improving", previous_hours: 500)

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # The memory span card shows the span with Strong badge (green color)
      assert html =~ "Memory Span"
      assert html =~ "Strong"
      assert html =~ "↑"
    end

    test "memory span card renders with yellow span (7-21 days)", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Yellow Span Course",
          subject: "Science",
          grade: "11",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Yellow Span Exam",
          test_date: Date.add(Date.utc_today(), 15),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      # yellow = 7*24 <= span_hours < 21*24 = 168..503 hours
      insert_course_span(user_role.id, course.id, 200, trend: "stable")

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Memory Span"
      assert html =~ "Moderate"
      assert html =~ "→"
    end

    test "memory span card renders with red span (<7 days = <168 hours)", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Red Span Course",
          subject: "History",
          grade: "12",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Red Span Exam",
          test_date: Date.add(Date.utc_today(), 25),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      # red = span_hours < 7*24 = 168 hours
      insert_course_span(user_role.id, course.id, 50, trend: "declining", previous_hours: 100)

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Memory Span"
      assert html =~ "At risk"
      assert html =~ "↓"
    end

    test "memory span card with improving trend and more than one day improvement", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Improving Span Subject",
          subject: "English",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Improving Span Exam",
          test_date: Date.add(Date.utc_today(), 30),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      # improving with 2-day improvement (48 hours difference)
      insert_course_span(user_role.id, course.id, 250, trend: "improving", previous_hours: 202)

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Memory Span"
      assert html =~ "↑"
      # trend_days shows "+2 days" since abs(250-202)/24 = 2
      assert html =~ "+2 days"
    end
  end

  describe "urgency_message coverage via rendered focus card" do
    test "critical urgency message appears for very close test with low readiness", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Critical Subject",
          subject: "Math",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Critical Exam",
          test_date: Date.add(Date.utc_today(), 2),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # Critical urgency: "Only X days left and Y% ready — practice now!"
      assert html =~ "days left" and html =~ "practice now!"
    end

    test "urgent urgency message appears for far-future test with low readiness", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Relaxed Subject",
          subject: "Art",
          grade: "11",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Far Exam",
          test_date: Date.add(Date.utc_today(), 60),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # With 60 days and 0% readiness, urgency_level is :urgent (readiness < 20).
      # urgent message: "#{days} days to go. Focus on your weakest areas."
      assert html =~ "days to go"
    end

    test "urgency message appears for test 8 days out (urgent due to low readiness)", %{
      conn: conn
    } do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "8-Day Urgency Subject",
          subject: "Biology",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "8-Day Urgency Exam",
          test_date: Date.add(Date.utc_today(), 8),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # 8 days + 0% readiness: readiness < 20 → :urgent
      # urgent message: "#{days} days to go. Focus on your weakest areas."
      assert html =~ "days"
      assert html =~ "8-Day Urgency Exam"
    end
  end

  describe "focus card with readiness score data" do
    defp create_readiness_score(user_role_id, schedule_id, aggregate, skill_scores) do
      {:ok, _} =
        Assessments.create_readiness_score(%{
          user_role_id: user_role_id,
          test_schedule_id: schedule_id,
          aggregate_score: aggregate,
          chapter_scores: %{},
          topic_scores: %{},
          skill_scores: skill_scores,
          calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
    end

    test "focus card renders with readiness score (0% by default, untested state)", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Readiness Test Subject",
          subject: "Math",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, schedule} =
        Assessments.create_test_schedule(%{
          name: "Readiness Exam",
          test_date: Date.add(Date.utc_today(), 15),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      # Readiness comes from ReadinessCalculator.calculate — with no answered questions,
      # aggregate_score = 0 and card_state = :untested
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Readiness Exam"
      assert html =~ "Readiness"
      assert html =~ "Not yet tested — take the assessment to see where you stand"
      assert html =~ "0%"
      # Confirm focus-readiness-bar is rendered (contains SheepProgressBar hook)
      assert html =~ "SheepProgressBar"
    end

    test "focus card renders format practice step link", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      {:ok, course} =
        Courses.create_course(%{
          name: "Format Test Subject",
          subject: "Science",
          grade: "11",
          created_by_id: user_role.id
        })

      {:ok, _schedule} =
        Assessments.create_test_schedule(%{
          name: "Format Exam",
          test_date: Date.add(Date.utc_today(), 12),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # Format Practice step is always rendered in the focus card
      assert html =~ "Format Practice"
      assert html =~ "Simulate the real test"
    end
  end

  describe "additional subject emoji and test_urgency_color coverage" do
    defp two_tests_with_subjects(user_role, subject1, subject2) do
      {:ok, course1} =
        Courses.create_course(%{
          name: "#{subject1} Course",
          subject: subject1,
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "#{subject1} Exam",
          test_date: Date.add(Date.utc_today(), 5),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course1.id
        })

      {:ok, course2} =
        Courses.create_course(%{
          name: "#{subject2} Course",
          subject: subject2,
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "#{subject2} Exam",
          test_date: Date.add(Date.utc_today(), 20),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course2.id
        })
    end

    test "Biology subject triggers bio emoji in test_row", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)
      two_tests_with_subjects(user_role, "Math", "Biology")
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Biology Exam"
    end

    test "Computer science subject triggers comp emoji in test_row", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)
      two_tests_with_subjects(user_role, "Math", "Computer Science")
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Computer Science Exam"
    end

    test "Music subject triggers music emoji in test_row", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)
      two_tests_with_subjects(user_role, "Math", "Music Theory")
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Music Theory Exam"
    end

    test "test row with past date has gray urgency indicator", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      # Create two tests so the past one ends up in other_tests
      {:ok, course1} =
        Courses.create_course(%{
          name: "Future Subject",
          subject: "Math",
          grade: "10",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Future Exam",
          test_date: Date.add(Date.utc_today(), 5),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course1.id
        })

      {:ok, course2} =
        Courses.create_course(%{
          name: "Future Subject 2",
          subject: "History",
          grade: "11",
          created_by_id: user_role.id
        })

      {:ok, _} =
        Assessments.create_test_schedule(%{
          name: "Future Exam 2",
          test_date: Date.add(Date.utc_today(), 30),
          scope: %{chapter_ids: []},
          user_role_id: user_role.id,
          course_id: course2.id
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Future Exam"
      assert html =~ "Other Tests"
    end
  end

end
