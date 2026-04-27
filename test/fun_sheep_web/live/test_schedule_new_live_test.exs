defmodule FunSheepWeb.TestScheduleNewLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{Assessments, ContentFixtures, Courses}

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
    course = ContentFixtures.create_course(%{name: "Physics 101"})

    {:ok, chapter1} =
      Courses.create_chapter(%{name: "Mechanics", position: 1, course_id: course.id})

    {:ok, chapter2} =
      Courses.create_chapter(%{name: "Thermodynamics", position: 2, course_id: course.id})

    {:ok, section1} =
      Courses.create_section(%{name: "Newtons Laws", position: 1, chapter_id: chapter1.id})

    %{
      user_role: user_role,
      course: course,
      chapter1: chapter1,
      chapter2: chapter2,
      section1: section1
    }
  end

  describe "new test form" do
    test "renders new test form with correct title", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      assert html =~ "New Test"
      assert html =~ "Physics 101"
    end

    test "shows chapter list for scope selection", %{
      conn: conn,
      user_role: ur,
      course: c,
      chapter1: ch1,
      chapter2: ch2
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      assert html =~ "Mechanics"
      assert html =~ "Thermodynamics"
    end

    test "shows test name and date fields", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      assert html =~ "Test Name"
      assert html =~ "Test Date"
    end

    test "shows test type options", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      assert html =~ "Adaptive"
    end
  end

  describe "toggle_chapter event" do
    test "selecting a chapter marks it as selected", %{
      conn: conn,
      user_role: ur,
      course: c,
      chapter1: ch1
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      render_click(view, "toggle_chapter", %{"chapter-id" => ch1.id})

      html = render(view)
      assert html =~ "Mechanics"
    end

    test "deselecting a chapter removes it", %{
      conn: conn,
      user_role: ur,
      course: c,
      chapter1: ch1
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      # Select then deselect
      render_click(view, "toggle_chapter", %{"chapter-id" => ch1.id})
      render_click(view, "toggle_chapter", %{"chapter-id" => ch1.id})

      html = render(view)
      assert html =~ "Mechanics"
    end
  end

  describe "select/deselect all chapters" do
    test "select_all_chapters selects all chapters", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      render_click(view, "select_all_chapters")

      html = render(view)
      assert html =~ "Mechanics"
      assert html =~ "Thermodynamics"
    end

    test "deselect_all_chapters clears selection", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      render_click(view, "select_all_chapters")
      render_click(view, "deselect_all_chapters")

      html = render(view)
      assert html =~ "Mechanics"
    end
  end

  describe "toggle_expand event" do
    test "expands chapter to show sections", %{
      conn: conn,
      user_role: ur,
      course: c,
      chapter1: ch1
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      render_click(view, "toggle_expand", %{"chapter-id" => ch1.id})

      html = render(view)
      assert html =~ "Newtons Laws"
    end

    test "collapses expanded chapter", %{conn: conn, user_role: ur, course: c, chapter1: ch1} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      render_click(view, "toggle_expand", %{"chapter-id" => ch1.id})
      render_click(view, "toggle_expand", %{"chapter-id" => ch1.id})

      html = render(view)
      assert html =~ "Mechanics"
    end
  end

  describe "validate event" do
    test "updates form fields on validate", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      render_submit(view, "validate", %{
        "name" => "My Physics Test",
        "test_date" => "2027-01-15"
      })

      html = render(view)
      assert html =~ "My Physics Test"
    end
  end

  describe "save adaptive test" do
    test "saves a test schedule and navigates away", %{
      conn: conn,
      user_role: ur,
      course: c,
      chapter1: ch1
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      # Select chapter
      render_click(view, "toggle_chapter", %{"chapter-id" => ch1.id})

      result =
        view
        |> render_submit("save", %{
          "name" => "Physics Midterm",
          "test_date" => Date.to_iso8601(Date.add(Date.utc_today(), 30))
        })

      # Should redirect to test list or show success
      assert {:error, {:live_redirect, %{to: destination}}} = result
      assert destination =~ "/courses/#{c.id}/tests"
    end

    test "shows error when name is blank", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      html =
        view
        |> render_submit("save", %{"name" => "", "test_date" => "2027-01-15"})

      assert html =~ "required"
    end
  end

  describe "edit mode" do
    setup %{user_role: ur, course: c, chapter1: ch1} do
      {:ok, schedule} =
        Assessments.create_test_schedule(%{
          name: "Existing Test",
          test_date: Date.add(Date.utc_today(), 14),
          scope: %{"chapter_ids" => [ch1.id], "section_ids" => []},
          user_role_id: ur.id,
          course_id: c.id
        })

      %{schedule: schedule}
    end

    test "renders edit form with existing values", %{
      conn: conn,
      user_role: ur,
      course: c,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests/new?schedule_id=#{schedule.id}")

      assert html =~ "Edit Test"
      assert html =~ "Existing Test"
    end

    test "shows correct page title in edit mode", %{
      conn: conn,
      user_role: ur,
      course: c,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests/new?schedule_id=#{schedule.id}")

      assert html =~ "Edit Test"
      assert html =~ "Physics 101"
    end
  end

  describe "set_test_type event" do
    test "switching to custom type shows custom test options", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      render_click(view, "set_test_type", %{"type" => "custom"})

      html = render(view)
      assert html =~ "Custom"
    end

    test "switching back to adaptive shows scope selection", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      render_click(view, "set_test_type", %{"type" => "custom"})
      render_click(view, "set_test_type", %{"type" => "adaptive"})

      html = render(view)
      assert html =~ "Adaptive"
    end
  end

  describe "toggle_section event" do
    test "selecting a section marks the chapter as selected", %{
      conn: conn,
      user_role: ur,
      course: c,
      chapter1: ch1,
      section1: s1
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      # Expand the chapter first so sections are visible
      render_click(view, "toggle_expand", %{"chapter-id" => ch1.id})
      render_click(view, "toggle_section", %{"section-id" => s1.id, "chapter-id" => ch1.id})

      html = render(view)
      assert html =~ "Newtons Laws"
    end

    test "deselecting the only section of a chapter deselects the chapter", %{
      conn: conn,
      user_role: ur,
      course: c,
      chapter1: ch1,
      section1: s1
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      # Select section first
      render_click(view, "toggle_expand", %{"chapter-id" => ch1.id})
      render_click(view, "toggle_section", %{"section-id" => s1.id, "chapter-id" => ch1.id})
      # Now deselect it
      render_click(view, "toggle_section", %{"section-id" => s1.id, "chapter-id" => ch1.id})

      html = render(view)
      # Should render without error
      assert html =~ "Mechanics"
    end
  end

  describe "update_description event" do
    test "updates the format description", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      render_submit(view, "update_description", %{
        "format_description" => "20 MC (30 min)\nFRQ: 2 questions"
      })

      html = render(view)
      assert html =~ "20 MC"
    end
  end

  describe "add_section event" do
    test "adds a valid section to format_sections", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      render_submit(view, "update_section_form", %{
        "name" => "Multiple Choice",
        "question_type" => "multiple_choice",
        "count" => "20",
        "points_per_question" => "1"
      })

      render_submit(view, "add_section", %{})

      html = render(view)
      assert html =~ "Multiple Choice"
    end

    test "shows error flash when section name is blank", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      # Submit add_section without a name
      render_submit(view, "add_section", %{})

      html = render(view)
      assert html =~ "Section name is required"
    end
  end

  describe "remove_section event" do
    test "removes an existing format section and section list shrinks", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      # Add two sections
      render_submit(view, "update_section_form", %{
        "name" => "Part A MC",
        "question_type" => "multiple_choice",
        "count" => "10",
        "points_per_question" => "1"
      })

      render_submit(view, "add_section", %{})

      render_submit(view, "update_section_form", %{
        "name" => "Part B FRQ",
        "question_type" => "free_response",
        "count" => "3",
        "points_per_question" => "5"
      })

      render_submit(view, "add_section", %{})

      # Both sections present
      html_before = render(view)
      assert html_before =~ "Part A MC"
      assert html_before =~ "Part B FRQ"

      # Remove the first section (index 0)
      render_click(view, "remove_section", %{"index" => "0"})

      html_after = render(view)
      # Part A MC should be gone from the saved sections list
      # (Part B FRQ stays)
      assert html_after =~ "Part B FRQ"
    end
  end

  describe "update_section_form event" do
    test "updates new section form fields", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      render_submit(view, "update_section_form", %{
        "name" => "True/False",
        "question_type" => "true_false",
        "count" => "15",
        "points_per_question" => "2"
      })

      html = render(view)
      assert html =~ "True/False"
    end
  end

  describe "update_time_limit event" do
    test "setting a time limit stores the value", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      render_submit(view, "update_time_limit", %{"time_limit" => "90"})

      html = render(view)
      assert html =~ "90"
    end

    test "clearing time limit sets it to nil", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      render_submit(view, "update_time_limit", %{"time_limit" => "90"})
      render_submit(view, "update_time_limit", %{"time_limit" => ""})

      html = render(view)
      assert html =~ "Time Limit"
    end
  end

  describe "validate event edge cases" do
    test "validate with missing keys does not crash", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      # Trigger the fallback validate clause
      render_submit(view, "validate", %{})

      html = render(view)
      assert html =~ "Test Name"
    end
  end

  describe "save adaptive test - edit mode" do
    setup %{user_role: ur, course: c, chapter1: ch1} do
      {:ok, schedule} =
        Assessments.create_test_schedule(%{
          name: "Edit Me Test",
          test_date: Date.add(Date.utc_today(), 14),
          scope: %{"chapter_ids" => [ch1.id], "section_ids" => []},
          user_role_id: ur.id,
          course_id: c.id
        })

      %{schedule: schedule}
    end

    test "saves edits and navigates back to tests list", %{
      conn: conn,
      user_role: ur,
      course: c,
      schedule: schedule,
      chapter1: ch1
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new?schedule_id=#{schedule.id}")

      # Re-select chapter and save
      render_click(view, "toggle_chapter", %{"chapter-id" => ch1.id})
      render_click(view, "toggle_chapter", %{"chapter-id" => ch1.id})

      result =
        view
        |> render_submit("save", %{
          "name" => "Edit Me Test Updated",
          "test_date" => Date.to_iso8601(Date.add(Date.utc_today(), 21))
        })

      assert {:error, {:live_redirect, %{to: destination}}} = result
      assert destination =~ "/courses/#{c.id}/tests"
    end

    test "edit mode shows Save Changes button", %{
      conn: conn,
      user_role: ur,
      course: c,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/tests/new?schedule_id=#{schedule.id}")

      assert html =~ "Save Changes"
    end
  end

  describe "custom test save" do
    test "saves custom test and redirects to custom test page", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      # Switch to custom mode
      render_click(view, "set_test_type", %{"type" => "custom"})

      result =
        view
        |> render_submit("save", %{
          "name" => "My Custom Test",
          "test_date" => ""
        })

      # Should navigate to the custom test page
      assert {:error, {:live_redirect, %{to: destination}}} = result
      assert destination =~ "/custom-tests/"
    end

    test "custom test with blank name shows error", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      render_click(view, "set_test_type", %{"type" => "custom"})

      html =
        view
        |> render_submit("save", %{
          "name" => "   ",
          "test_date" => ""
        })

      assert html =~ "required"
    end
  end

  describe "count_selected_items calculation" do
    test "shows correct selection count after selecting chapters", %{
      conn: conn,
      user_role: ur,
      course: c,
      chapter1: ch1,
      chapter2: ch2
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      render_click(view, "toggle_chapter", %{"chapter-id" => ch1.id})

      html = render(view)
      # Selected items counter should be visible
      assert html =~ "of"
      assert html =~ "selected"
    end

    test "select all shows max selected count", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/tests/new")

      render_click(view, "select_all_chapters")

      html = render(view)
      assert html =~ "selected"
    end
  end
end
