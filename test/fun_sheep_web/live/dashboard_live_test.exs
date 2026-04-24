defmodule FunSheepWeb.DashboardLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{Accounts, Assessments, Courses}

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
      assert html =~ "Your Study Path"
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
end
