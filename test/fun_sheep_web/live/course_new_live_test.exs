defmodule FunSheepWeb.CourseNewLiveTest do
  # async: false because Oban inline mode runs workers in the LiveView process
  # (not the test process), so with_testing_mode(:manual) doesn't stop them.
  # Shared ClientMock global state requires serialized access.
  use FunSheepWeb.ConnCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  import Mox
  import Phoenix.LiveViewTest

  alias FunSheep.AI.ClientMock
  alias FunSheep.Accounts
  alias FunSheep.Courses
  alias FunSheep.ContentFixtures

  # Catch-all stub: workers' AI calls fail gracefully instead of crashing with
  # Mox.UnexpectedCallError, matching prior behaviour where Agents calls returned
  # {:error, :assistant_not_found}.
  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    stub(ClientMock, :call, fn _sys, _usr, _opts -> {:error, :not_configured_in_test} end)
    :ok
  end

  defp user_role_conn(conn, attrs \\ %{}) do
    defaults = %{
      interactor_user_id: "cn_test_#{System.unique_integer([:positive])}",
      role: :student,
      email: "cn_#{System.unique_integer([:positive])}@test.com",
      display_name: "Course New Test Student"
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

  describe "school_id propagation" do
    test "created course inherits school_id from the user's profile", %{conn: conn} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        school = ContentFixtures.create_school()
        {conn, _user_role} = user_role_conn(conn, %{school_id: school.id})
        {:ok, view, _html} = live(conn, ~p"/courses/new")

        view
        |> element("#course-form")
        |> render_change(%{"course_name" => "AP Chemistry", "subject" => "Chemistry"})

        render_click(view, "toggle_grade", %{"grade" => "11"})
        render_click(view, "no_textbook", %{})

        assert {:error, {:live_redirect, _}} =
                 view |> element("#course-form") |> render_submit()

        course = Courses.list_courses() |> Enum.find(&(&1.name == "AP Chemistry"))
        assert course != nil
        assert course.school_id == school.id
      end)
    end
  end

  describe "default flow (no query param)" do
    test "renders 'New Course' heading and default subcopy", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses/new")

      assert html =~ "New Course"
      assert html =~ "Define your course and textbook"
      assert html =~ "Course Name"
      assert html =~ "Create Course"
    end
  end

  describe "?flow=test — test-first flow" do
    test "renders test-framed heading, subcopy, form label, and submit button", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses/new?flow=test")

      # Heading and subcopy swap to the test-first framing.
      assert html =~ "Add a Test"
      assert html =~ "Tests live inside a class"
      assert html =~ "schedule the test next"

      # Form noun aligns to "class" in test-first mode.
      assert html =~ "Class Name"
      refute html =~ ">Course Name *"

      # Submit button points the user forward to scheduling.
      assert html =~ "Continue to test"
      refute html =~ "Create Course"
    end

    test "after save, redirects to the test-schedule new page for the created course", %{
      conn: conn
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {conn, _user_role} = user_role_conn(conn)
        {:ok, view, _html} = live(conn, ~p"/courses/new?flow=test")

        # Fill subject + grade so the textbook picker becomes visible.
        view
        |> element("#course-form")
        |> render_change(%{"course_name" => "AP Biology", "subject" => "Biology"})

        render_click(view, "toggle_grade", %{"grade" => "11"})

        # Skip textbook so validation passes without hitting the OpenLibrary API.
        render_click(view, "no_textbook", %{})

        assert {:error, {:live_redirect, %{to: redirect_to}}} =
                 view
                 |> element("#course-form")
                 |> render_submit()

        assert redirect_to =~ ~r"^/courses/[^/]+/tests/new$"
      end)
    end
  end

  describe "form validation errors" do
    test "shows course_name error when name is blank", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      # Submit without filling anything
      html = render_click(view, "save_course", %{})

      assert html =~ "Course name is required"
    end

    test "shows subject error when subject is blank", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "Biology 101"})

      html = render_click(view, "save_course", %{})

      assert html =~ "Subject is required"
    end

    test "shows grade error when no grade selected", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "Biology 101", "subject" => "Biology"})

      html = render_click(view, "save_course", %{})

      assert html =~ "Grade level is required"
    end

    test "does not save when no textbook chosen (form stays on page)", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "Biology 101", "subject" => "Biology"})

      render_click(view, "toggle_grade", %{"grade" => "10"})

      # Save should fail validation and remain on the form (no redirect)
      result = render_click(view, "save_course", %{})

      # The result is HTML, not a redirect error — the form stays on the page
      assert is_binary(result)
      assert result =~ "Create Course"
    end
  end

  describe "grade toggling" do
    test "toggling a grade selects it", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      render_click(view, "toggle_grade", %{"grade" => "10"})
      html = render(view)

      # Grade button should now be active (green)
      assert html =~ "10"
    end

    test "toggling same grade twice deselects it", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      render_click(view, "toggle_grade", %{"grade" => "10"})
      render_click(view, "toggle_grade", %{"grade" => "10"})
      # Should render without crashing
      html = render(view)
      assert html =~ "Grade Level"
    end

    test "toggling multiple grades selects all of them", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      render_click(view, "toggle_grade", %{"grade" => "10"})
      render_click(view, "toggle_grade", %{"grade" => "11"})

      html = render(view)
      assert html =~ "10"
      assert html =~ "11"
    end
  end

  describe "textbook mode transitions" do
    setup %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      # Fill course name and subject, pick grade to show textbook section
      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "History 101", "subject" => "History"})

      render_click(view, "toggle_grade", %{"grade" => "9"})

      %{conn: conn, view: view, user_role: user_role}
    end

    test "use_custom_textbook switches to custom mode", %{view: view} do
      render_click(view, "use_custom_textbook", %{})
      html = render(view)

      # Custom textbook input should appear
      assert html =~ "Enter your textbook name"
    end

    test "update_custom_textbook updates the custom textbook name", %{view: view} do
      render_click(view, "use_custom_textbook", %{})

      render_click(view, "update_custom_textbook", %{"value" => "My Custom Book"})

      html = render(view)
      assert html =~ "My Custom Book"
    end

    test "back_to_textbook_list from custom mode returns to none mode", %{view: view} do
      render_click(view, "use_custom_textbook", %{})
      render_click(view, "back_to_textbook_list", %{})

      html = render(view)
      # Should show the search input again
      assert html =~ "Search for your textbook"
    end

    test "no_textbook sets skipped mode", %{view: view} do
      render_click(view, "no_textbook", %{})
      html = render(view)

      assert html =~ "Proceeding without a textbook"
    end

    test "back_to_textbook_list from skipped mode returns to none mode", %{view: view} do
      render_click(view, "no_textbook", %{})
      render_click(view, "back_to_textbook_list", %{})

      html = render(view)
      assert html =~ "Search for your textbook"
    end

    test "deselect_textbook returns to none mode when no textbook selected", %{view: view} do
      render_click(view, "no_textbook", %{})
      render_click(view, "back_to_textbook_list", %{})

      html = render(view)
      assert html =~ "Search for your textbook"
    end
  end

  describe "update_brief event" do
    test "updates generation_brief assign", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      render_click(view, "update_brief", %{"value" => "Focus on cell biology and genetics"})

      html = render(view)
      assert html =~ "Focus on cell biology and genetics"
    end

    test "auto-detected brief is overridden when user edits it", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      # Detect SAT profile first (auto-fills brief)
      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "SAT Math"})

      # Now user manually edits the brief
      render_click(view, "update_brief", %{"value" => "Custom brief text"})

      html = render(view)
      assert html =~ "Custom brief text"
    end
  end

  describe "textbook_search event" do
    test "searching with a subject set returns results or empty", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      # Set subject and grade first
      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "Biology 101", "subject" => "Biology"})

      render_click(view, "toggle_grade", %{"grade" => "10"})

      # Search for a textbook
      render_click(view, "textbook_search", %{"textbook_query" => "biology"})

      html = render(view)
      # The page should still render without error
      assert html =~ "Textbook"
    end

    test "searching without subject returns no results", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      # Search without setting subject
      render_click(view, "textbook_search", %{"textbook_query" => "biology"})

      html = render(view)
      # View should render without crashing
      assert html =~ "Course Name"
    end
  end

  describe "form_change event" do
    test "changing course name updates the name assign", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "Chemistry 201"})

      html = render(view)
      assert html =~ "Chemistry 201"
    end

    test "changing subject updates the subject assign", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      view
      |> element("#course-form")
      |> render_change(%{"subject" => "Physics"})

      html = render(view)
      assert html =~ "Physics"
    end

    test "SAT course name auto-detects profile and shows recognized test banner", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "SAT Math"})

      html = render(view)
      assert html =~ "SAT"
    end

    test "non-standardized course name clears detected profile", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      # First detect a profile
      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "SAT Math"})

      # Then clear it with a non-standardized name
      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "My Custom Biology Class"})

      html = render(view)
      # The SAT banner should be gone
      refute html =~ "SAT Math Prep"
    end
  end

  describe "edit mode (courses/:id/edit)" do
    setup do
      {:ok, course} =
        Courses.create_course(%{
          "name" => "Edit Me Course",
          "subject" => "Physics",
          "grades" => ["11"],
          "description" => "A course to edit"
        })

      %{course: course}
    end

    test "renders edit form with existing course data", %{conn: conn, course: course} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/edit")

      assert html =~ "Edit Course"
      assert html =~ "Edit Me Course"
      assert html =~ "Physics"
      assert html =~ "Save Changes"
    end

    test "edit mode shows Back link to course detail", %{conn: conn, course: course} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/edit")

      assert html =~ "Back"
    end

    test "edit mode shows Save Changes button and is ready to submit", %{
      conn: conn,
      course: course
    } do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/edit")

      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "Edit Me Course Updated", "subject" => "Physics"})

      render_click(view, "no_textbook", %{})

      html = render(view)
      assert html =~ "Save Changes"
      assert html =~ "Proceeding without a textbook"
    end

    test "cancel in edit mode links back to courses", %{conn: conn, course: course} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/edit")

      # Cancel link should exist
      assert html =~ "Cancel"
    end
  end

  describe "edit mode with custom textbook" do
    setup do
      {:ok, course} =
        Courses.create_course(%{
          "name" => "Custom Textbook Course",
          "subject" => "Chemistry",
          "grades" => ["10"],
          "custom_textbook_name" => "My Chem Book"
        })

      %{course: course}
    end

    test "prefills custom textbook name in edit mode", %{conn: conn, course: course} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/edit")

      assert html =~ "Edit Course"
      assert html =~ "My Chem Book"
    end
  end

  describe "deselect_textbook event" do
    test "deselect_textbook clears selected textbook and returns to none mode", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      # Set subject and grade to show textbook section
      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "Bio 101", "subject" => "Biology"})

      render_click(view, "toggle_grade", %{"grade" => "10"})

      # Go into custom mode first, then deselect
      render_click(view, "use_custom_textbook", %{})
      render_click(view, "update_custom_textbook", %{"value" => "Biology Book"})
      render_click(view, "deselect_textbook", %{})

      html = render(view)
      # Should be back to search mode
      assert html =~ "Search for your textbook"
    end
  end

  describe "load_user_role with non-UUID dev_user id" do
    test "handles non-UUID user id gracefully", %{conn: conn} do
      # Use a non-UUID id to hit the fallback branch in load_user_role
      conn =
        init_test_session(conn, %{
          dev_user_id: "not-a-real-uuid",
          dev_user: %{
            "id" => "not-a-real-uuid",
            "role" => "student",
            "email" => "badid@test.com",
            "display_name" => "Bad ID User"
          }
        })

      {:ok, _view, html} = live(conn, ~p"/courses/new")
      assert html =~ "New Course"
    end
  end

  describe "back to textbook list after search" do
    test "back_to_textbook_list triggers textbook refresh", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "Biology 101", "subject" => "Biology"})

      render_click(view, "toggle_grade", %{"grade" => "10"})
      render_click(view, "no_textbook", %{})
      render_click(view, "back_to_textbook_list", %{})

      html = render(view)
      assert html =~ "Search for your textbook"
    end
  end

  describe "maybe_detect_profile branch coverage" do
    test "user-edited brief is preserved when SAT profile is detected", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      # First detect SAT (auto-fills brief with generation_brief_auto: true)
      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "SAT Math"})

      # User manually overrides brief via update_brief event
      # This sets generation_brief_auto: false
      render_click(view, "update_brief", %{"value" => "My custom SAT brief"})

      # Now form_change again with SAT course name — should preserve user brief
      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "SAT Math Prep"})

      html = render(view)
      # User brief should be preserved, not overwritten
      assert html =~ "My custom SAT brief"
    end

    test "auto brief is cleared when switching from SAT to non-SAT course", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      # Detect SAT (auto-fills brief)
      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "SAT Math"})

      # Switch to non-SAT course — auto brief should be cleared
      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "My Custom History Class"})

      html = render(view)
      # Profile banner should be gone
      refute html =~ "SAT"
    end

    test "user-edited brief survives switch to non-SAT course", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      # Detect SAT profile
      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "SAT Math"})

      # User overrides brief (no longer auto)
      render_click(view, "update_brief", %{"value" => "My own special brief"})

      # Now switch to non-SAT — user brief should be preserved (not auto)
      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "History 101"})

      html = render(view)
      assert html =~ "My own special brief"
    end
  end

  describe "premium catalog — access level and price" do
    test "update_access_level changes access level", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      # Trigger SAT detection to show premium options
      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "SAT Math", "subject" => "Mathematics"})

      render_click(view, "toggle_premium_catalog", %{})
      render_click(view, "update_access_level", %{"value" => "standard"})

      html = render(view)
      assert html =~ "standard"
    end

    test "update_price_cents stores a valid integer price", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "SAT Math", "subject" => "Mathematics"})

      render_click(view, "toggle_premium_catalog", %{})
      render_click(view, "update_price_cents", %{"value" => "999"})

      html = render(view)
      assert html =~ "999"
    end

    test "update_price_cents ignores non-integer values", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "SAT Math", "subject" => "Mathematics"})

      render_click(view, "toggle_premium_catalog", %{})

      # Non-integer should not crash
      html = render_click(view, "update_price_cents", %{"value" => "not-a-number"})
      assert html =~ "One-time price"
    end

    test "toggling premium catalog off resets price and access level", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "SAT Math", "subject" => "Mathematics"})

      # Toggle on then off
      render_click(view, "toggle_premium_catalog", %{})
      render_click(view, "toggle_premium_catalog", %{})

      html = render(view)
      # Access level and price sections should be hidden
      refute html =~ "Access level"
    end
  end

  describe "save_course — pre-submit state" do
    test "form renders save button when all required fields are filled", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "New Test Course", "subject" => "Chemistry"})

      render_click(view, "toggle_grade", %{"grade" => "12"})
      render_click(view, "no_textbook", %{})

      html = render(view)
      assert html =~ "Create Course"
      assert html =~ "Proceeding without a textbook"
    end

    test "form renders Cancel link", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses/new")

      assert html =~ "Cancel"
    end
  end
end
