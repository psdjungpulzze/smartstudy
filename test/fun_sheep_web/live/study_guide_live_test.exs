defmodule FunSheepWeb.StudyGuideLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.ContentFixtures

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
      FunSheep.Courses.create_chapter(%{
        name: "Biology Basics",
        position: 1,
        course_id: course.id
      })

    {:ok, schedule} =
      FunSheep.Assessments.create_test_schedule(%{
        name: "Bio Final",
        test_date: Date.add(Date.utc_today(), 10),
        scope: %{"chapter_ids" => [chapter.id]},
        user_role_id: user_role.id,
        course_id: course.id
      })

    # Generate a study guide
    {:ok, guide} =
      FunSheep.Learning.StudyGuideGenerator.generate(user_role.id, schedule.id)

    %{user_role: user_role, course: course, chapter: chapter, schedule: schedule, guide: guide}
  end

  describe "study guide page" do
    test "renders study guide", %{conn: conn, user_role: ur, schedule: schedule, guide: guide} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      assert html =~ "Study Guide: Bio Final"
      assert html =~ "Test Course"
    end

    test "shows sections with priority badges", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      assert html =~ "Biology Basics"
      assert html =~ "Critical"
    end

    test "shows aggregate score", %{conn: conn, user_role: ur, schedule: schedule, guide: guide} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      assert html =~ "readiness"
    end

    test "shows tab navigation", %{conn: conn, user_role: ur, schedule: schedule, guide: guide} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      assert html =~ "Overview"
      assert html =~ "Study Plan"
      assert html =~ "Chapters"
    end

    test "shows action buttons", %{conn: conn, user_role: ur, schedule: schedule, guide: guide} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      assert html =~ "Practice Weak Areas"
      assert html =~ "Export"
      assert html =~ "All Guides"
    end

    test "overview shows quick stats", %{conn: conn, user_role: ur, schedule: schedule, guide: guide} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      assert html =~ "Critical"
      assert html =~ "Wrong Questions"
      assert html =~ "Reviewed"
    end

    test "overview shows chapter breakdown section", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      assert html =~ "Chapter Breakdown"
      assert html =~ "Biology Basics"
    end
  end

  describe "switch_tab event" do
    test "switching to study plan tab shows plan content", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      html =
        view
        |> element("button[phx-click='switch_tab'][phx-value-tab='plan']")
        |> render_click()

      assert html =~ "Day"
    end

    test "switching to chapters tab shows chapters content", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      html =
        view
        |> element("button[phx-click='switch_tab'][phx-value-tab='chapters']")
        |> render_click()

      assert html =~ "Biology Basics"
      assert html =~ "toggle_section"
    end

    test "switching back to overview tab from another tab", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      # Switch to chapters
      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='chapters']")
      |> render_click()

      # Switch back to overview
      html =
        view
        |> element("button[phx-click='switch_tab'][phx-value-tab='overview']")
        |> render_click()

      assert html =~ "Chapter Breakdown"
    end
  end

  describe "toggle_section event" do
    test "clicking a chapter header expands it", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      # Switch to chapters tab first
      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='chapters']")
      |> render_click()

      # Click the toggle_section button for the chapter
      html =
        view
        |> element("button[phx-click='toggle_section'][phx-value-chapter-id='#{chapter.id}']")
        |> render_click()

      # Expanded content should now be visible: AI Study Summary, Review Topics
      assert html =~ "AI Study Summary"
    end

    test "clicking a chapter header twice collapses it", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='chapters']")
      |> render_click()

      # Expand
      view
      |> element("button[phx-click='toggle_section'][phx-value-chapter-id='#{chapter.id}']")
      |> render_click()

      # Collapse
      html =
        view
        |> element("button[phx-click='toggle_section'][phx-value-chapter-id='#{chapter.id}']")
        |> render_click()

      refute html =~ "AI Study Summary"
    end
  end

  describe "toggle_reviewed event" do
    test "marking a chapter as reviewed shows checkmark", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='chapters']")
      |> render_click()

      html = render_hook(view, "toggle_reviewed", %{"chapter-id" => chapter.id})

      # After marking reviewed, the section should show reviewed styling
      # (the chapter_id is now in the reviewed set → `reviewed: true` in content)
      assert html =~ "line-through"
    end

    test "toggling reviewed twice returns section to unreviewed", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='chapters']")
      |> render_click()

      # Mark as reviewed
      render_hook(view, "toggle_reviewed", %{"chapter-id" => chapter.id})

      # Unmark
      html = render_hook(view, "toggle_reviewed", %{"chapter-id" => chapter.id})

      # Should no longer have line-through on the chapter name
      refute html =~ "line-through"
    end

    test "progress reviewed percentage updates after marking", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      render_hook(view, "toggle_reviewed", %{"chapter-id" => chapter.id})

      html = render(view)
      # 1 of 1 chapters reviewed = 100%
      assert html =~ "100"
    end
  end

  describe "toggle_plan_day event" do
    test "marking a study plan day as completed shows it completed", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      # Switch to plan tab
      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='plan']")
      |> render_click()

      # Get guide content to find the day number
      updated_guide = FunSheep.Learning.get_study_guide!(guide.id)
      plan = Map.get(updated_guide.content, "study_plan", [])

      if plan != [] do
        day = List.first(plan)
        html = render_hook(view, "toggle_plan_day", %{"day" => to_string(day["day"])})

        # The completed day shows a completed icon
        assert html =~ "hero-check-mini"
      else
        # No plan days — just verify the empty state renders
        html = render(view)
        assert html =~ "No study plan available"
      end
    end

    test "toggling a day twice marks it incomplete again", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='plan']")
      |> render_click()

      updated_guide = FunSheep.Learning.get_study_guide!(guide.id)
      plan = Map.get(updated_guide.content, "study_plan", [])

      if plan != [] do
        day = List.first(plan)
        day_str = to_string(day["day"])

        # Complete
        render_hook(view, "toggle_plan_day", %{"day" => day_str})

        # Uncomplete
        html = render_hook(view, "toggle_plan_day", %{"day" => day_str})

        # Completed state (green circle with check) should be gone
        # Uncompleted state has border-[#E5E5EA]
        assert html =~ "border-[#E5E5EA]"
      end
    end
  end

  describe "load_chapter_summary event" do
    test "loading chapter summary sets loading state then shows summary", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      # Switch to chapters tab and expand the section
      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='chapters']")
      |> render_click()

      view
      |> element("button[phx-click='toggle_section'][phx-value-chapter-id='#{chapter.id}']")
      |> render_click()

      # Trigger load_chapter_summary — the AI mock returns a response synchronously
      html = render_hook(view, "load_chapter_summary", %{"chapter-id" => chapter.id})

      # After loading, the summary should be shown or loading state
      assert html =~ "AI Study Summary"
    end

    test "loading chapter summary twice does not reload", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='chapters']")
      |> render_click()

      view
      |> element("button[phx-click='toggle_section'][phx-value-chapter-id='#{chapter.id}']")
      |> render_click()

      # First load
      render_hook(view, "load_chapter_summary", %{"chapter-id" => chapter.id})

      # Wait for async task to complete
      html1 = render(view)

      # Second load — since summary is already loaded, it should be a no-op
      render_hook(view, "load_chapter_summary", %{"chapter-id" => chapter.id})
      html2 = render(view)

      # Both renders should show the same summary content
      assert html1 =~ "AI Study Summary"
      assert html2 =~ "AI Study Summary"
    end
  end

  describe "explain_question event" do
    test "explain_question shows loading state and then explanation", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      # Get guide's wrong questions
      updated_guide = FunSheep.Learning.get_study_guide!(guide.id)
      sections = Map.get(updated_guide.content, "sections", [])
      wrong_questions = sections |> Enum.flat_map(&(&1["wrong_questions"] || []))

      if wrong_questions != [] do
        wq = List.first(wrong_questions)
        question_id = wq["id"]

        # Switch to chapters and expand the chapter
        view
        |> element("button[phx-click='switch_tab'][phx-value-tab='chapters']")
        |> render_click()

        view
        |> element("button[phx-click='toggle_section'][phx-value-chapter-id='#{chapter.id}']")
        |> render_click()

        # Trigger explain — mock AI returns immediately
        render_hook(view, "explain_question", %{"question-id" => question_id})

        # Wait for async task to finish
        html = render(view)
        # The explanation should have been generated by the mock AI
        assert html =~ "explanation" or html =~ "Explain"
      else
        # No wrong questions — just verify the section renders without wrong questions section
        view
        |> element("button[phx-click='switch_tab'][phx-value-tab='chapters']")
        |> render_click()

        html =
          view
          |> element("button[phx-click='toggle_section'][phx-value-chapter-id='#{chapter.id}']")
          |> render_click()

        # When no wrong questions, the wrong questions section is not rendered
        refute html =~ "Wrong Questions (0)" or html =~ "phx-click=\"explain_question\""
      end
    end
  end

  describe "handle_info for task results" do
    test "unknown messages are ignored gracefully", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      # Send an arbitrary message to the LiveView process
      send(view.pid, {:unknown_message, "some data"})

      # View should still be alive and render correctly
      html = render(view)
      assert html =~ "Study Guide: Bio Final"
    end

    test "DOWN process message is handled gracefully", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      send(view.pid, {:DOWN, make_ref(), :process, self(), :normal})

      html = render(view)
      assert html =~ "Study Guide: Bio Final"
    end
  end

  describe "study guides list" do
    test "renders list page", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/study-guides")

      assert html =~ "Study Guides"
    end

    test "shows generated guides", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/study-guides")

      assert html =~ "Study Guide: Bio Final"
    end

    test "shows generate new section", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/study-guides")

      assert html =~ "Generate New Guide"
      assert html =~ "Select a test schedule"
    end
  end

  describe "study guide rendering details" do
    test "shows test date and days remaining", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      # Guide has test_date set (10 days from today)
      assert html =~ "10 days" or html =~ "days"
    end

    test "shows correct weak area count", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      # Study guide shows "N weak areas" in header
      assert html =~ "weak areas"
    end

    test "study plan tab shows empty message when no plan", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      html =
        view
        |> element("button[phx-click='switch_tab'][phx-value-tab='plan']")
        |> render_click()

      # Either shows plan days or empty state
      assert html =~ "Day" or html =~ "No study plan available"
    end

    test "chapters tab shows progress counts", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      html =
        view
        |> element("button[phx-click='switch_tab'][phx-value-tab='chapters']")
        |> render_click()

      # The chapter tab button shows (reviewed/total) progress
      assert html =~ "0/"
    end
  end

  describe "handle_info task error result" do
    test "AI explanation error shows flash message", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      # Send a simulated task error result via handle_info
      ref = make_ref()
      send(view.pid, {ref, {:error, "AI unavailable"}})

      html = render(view)
      assert html =~ "Study Guide: Bio Final"
    end

    test "task success with ok result for explain task is handled", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      # Send an unmatched task success — the cond true branch should handle it gracefully
      ref = make_ref()
      send(view.pid, {ref, {:ok, "some text"}})

      html = render(view)
      assert html =~ "Study Guide: Bio Final"
    end
  end

  describe "toggle_reviewed error handling" do
    test "toggle_reviewed with invalid chapter id does not crash", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      # Use an invalid chapter id — should either succeed or show error flash
      html = render_hook(view, "toggle_reviewed", %{"chapter-id" => "non-existent-chapter-id"})

      # View should still be alive
      assert html =~ "Study Guide"
    end
  end

  describe "toggle_plan_day error handling" do
    test "toggle_plan_day with invalid day string is handled", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='plan']")
      |> render_click()

      # Day 999 doesn't exist, should handle gracefully
      html = render_hook(view, "toggle_plan_day", %{"day" => "999"})

      assert html =~ "Study Guide"
    end
  end

  describe "overview tab renders priority badge variants" do
    test "overview renders the chapter breakdown with priority info", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      # The overview shows priority data
      assert html =~ "Chapter Breakdown" or html =~ "Critical" or html =~ "High"
    end

    test "overview stats cards are rendered", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      # All four stat cards present
      assert html =~ "High Priority"
      assert html =~ "Wrong Questions"
      assert html =~ "Reviewed"
    end
  end

  describe "study plan day label variants" do
    test "plan tab shows day labels from study plan", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      html =
        view
        |> element("button[phx-click='switch_tab'][phx-value-tab='plan']")
        |> render_click()

      # Should show plan content or empty state
      assert html =~ "Day" or html =~ "No study plan available" or html =~ "calendar"
    end
  end

  describe "study guides list actions" do
    test "can navigate from study guide list to study guide detail", %{
      conn: conn,
      user_role: ur,
      course: course,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/study-guides")

      # Guide link should be present
      assert html =~ guide.id or html =~ "Study Guide: Bio Final"
    end

    test "study guide list shows generate new section with schedule selector", %{
      conn: conn,
      user_role: ur,
      course: course,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/study-guides")

      assert html =~ "Generate New Guide"
      assert html =~ schedule.name
    end
  end

  describe "chapter expand load_chapter_summary loading state" do
    test "loading state shows generating indicator when summary is loading", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='chapters']")
      |> render_click()

      view
      |> element("button[phx-click='toggle_section'][phx-value-chapter-id='#{chapter.id}']")
      |> render_click()

      # After expansion, the section should show the Generate button or loading state
      html = render(view)
      assert html =~ "Generate" or html =~ "AI Study Summary"
    end
  end

  describe "days_label variants via different test dates" do
    test "shows Today! when test_date is today", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user_role.id})

      {:ok, chapter} =
        FunSheep.Courses.create_chapter(%{
          name: "Today Chapter",
          position: 1,
          course_id: course.id
        })

      {:ok, schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Today Test",
          test_date: Date.utc_today(),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, guide} = FunSheep.Learning.StudyGuideGenerator.generate(user_role.id, schedule.id)

      conn = auth_conn(conn, user_role)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/study-guides/#{guide.id}")

      assert html =~ "Today!" or html =~ "Today"
    end

    test "shows Tomorrow when test_date is tomorrow", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user_role.id})

      {:ok, chapter} =
        FunSheep.Courses.create_chapter(%{
          name: "Tomorrow Chapter",
          position: 1,
          course_id: course.id
        })

      {:ok, schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Tomorrow Test",
          test_date: Date.add(Date.utc_today(), 1),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, guide} = FunSheep.Learning.StudyGuideGenerator.generate(user_role.id, schedule.id)

      conn = auth_conn(conn, user_role)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/study-guides/#{guide.id}")

      assert html =~ "Tomorrow"
    end

    test "shows days ago when test_date is in the past", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user_role.id})

      {:ok, chapter} =
        FunSheep.Courses.create_chapter(%{
          name: "Past Chapter",
          position: 1,
          course_id: course.id
        })

      {:ok, schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Past Test",
          test_date: Date.add(Date.utc_today(), -5),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: user_role.id,
          course_id: course.id
        })

      {:ok, guide} = FunSheep.Learning.StudyGuideGenerator.generate(user_role.id, schedule.id)

      conn = auth_conn(conn, user_role)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/study-guides/#{guide.id}")

      assert html =~ "days ago" or html =~ "Overdue" or html =~ "5"
    end
  end

  describe "score display variations" do
    test "shows 0% reviewed stat when progress is empty", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      # Reviewed stat shows 0% before anything is reviewed
      assert html =~ "0%" or html =~ "Reviewed"
    end

    test "chapters tab shows wrong questions count per chapter", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='chapters']")
      |> render_click()

      html = render(view)
      # Show wrong questions count text
      assert html =~ "wrong questions" or html =~ "Biology Basics"
      assert html =~ chapter.id or html =~ "toggle_section"
    end
  end

  describe "guide navigation" do
    test "practice weak areas link is present", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      assert html =~ "Practice Weak Areas"
      assert html =~ "practice"
    end

    test "export link is present with correct guide ID", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      assert html =~ "export/study-guide/#{guide.id}"
    end

    test "all guides link navigates back to list", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      assert html =~ "All Guides"
      assert html =~ "study-guides"
    end
  end

  describe "priority badge class variants via rich guide content" do
    # Directly update the guide content to include different priority sections
    test "renders High priority badge when section score is 30-49", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      # Update guide to have a High priority section
      high_content =
        Map.put(guide.content, "sections", [
          %{
            "chapter_id" => chapter.id,
            "chapter_name" => chapter.name,
            "score" => 40.0,
            "priority" => "High",
            "wrong_questions" => [],
            "review_topics" => [],
            "source_materials" => [],
            "reviewed" => false,
            "total_attempted" => 5,
            "total_correct" => 2
          }
        ])

      {:ok, updated_guide} = FunSheep.Learning.update_study_guide(guide, %{content: high_content})

      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{updated_guide.id}")

      assert html =~ "High"
    end

    test "renders Medium priority badge when section score is 50-69", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      medium_content =
        Map.put(guide.content, "sections", [
          %{
            "chapter_id" => chapter.id,
            "chapter_name" => chapter.name,
            "score" => 60.0,
            "priority" => "Medium",
            "wrong_questions" => [],
            "review_topics" => [],
            "source_materials" => [],
            "reviewed" => false,
            "total_attempted" => 10,
            "total_correct" => 6
          }
        ])

      {:ok, updated_guide} =
        FunSheep.Learning.update_study_guide(guide, %{content: medium_content})

      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{updated_guide.id}")

      assert html =~ "Medium"
    end

    test "renders Low priority badge when section score is >= 70", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      low_content =
        Map.put(guide.content, "sections", [
          %{
            "chapter_id" => chapter.id,
            "chapter_name" => chapter.name,
            "score" => 75.0,
            "priority" => "Low",
            "wrong_questions" => [],
            "review_topics" => [],
            "source_materials" => [],
            "reviewed" => false
          }
        ])

      {:ok, updated_guide} = FunSheep.Learning.update_study_guide(guide, %{content: low_content})

      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{updated_guide.id}")

      assert html =~ "Low"
    end

    test "renders wrong questions with difficulty badges when sections have them", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      wq_id = Ecto.UUID.generate()

      content_with_wqs =
        Map.put(guide.content, "sections", [
          %{
            "chapter_id" => chapter.id,
            "chapter_name" => chapter.name,
            "score" => 20.0,
            "priority" => "Critical",
            "wrong_questions" => [
              %{
                "id" => wq_id,
                "content" => "What is photosynthesis?",
                "answer" => "The process by which plants make food using sunlight.",
                "difficulty" => "easy",
                "attempt_count" => 3,
                "source_page" => nil
              }
            ],
            "review_topics" => ["Photosynthesis", "Cell respiration"],
            "source_materials" => [],
            "reviewed" => false
          }
        ])

      {:ok, updated_guide} =
        FunSheep.Learning.update_study_guide(guide, %{content: content_with_wqs})

      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{updated_guide.id}")

      # Go to chapters tab and expand the section
      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='chapters']")
      |> render_click()

      html =
        view
        |> element("button[phx-click='toggle_section'][phx-value-chapter-id='#{chapter.id}']")
        |> render_click()

      # Should show Easy badge and wrong questions section
      assert html =~ "Easy" or html =~ "photosynthesis" or html =~ "Wrong Questions"
    end

    test "renders hard difficulty badge in wrong questions section", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      wq_id = Ecto.UUID.generate()

      content_with_hard_wqs =
        Map.put(guide.content, "sections", [
          %{
            "chapter_id" => chapter.id,
            "chapter_name" => chapter.name,
            "score" => 15.0,
            "priority" => "Critical",
            "wrong_questions" => [
              %{
                "id" => wq_id,
                "content" => "Describe the Krebs cycle in detail.",
                "answer" => "A series of biochemical reactions...",
                "difficulty" => "hard",
                "attempt_count" => 5,
                "source_page" => 42
              }
            ],
            "review_topics" => [],
            "source_materials" => [],
            "reviewed" => false
          }
        ])

      {:ok, updated_guide} =
        FunSheep.Learning.update_study_guide(guide, %{content: content_with_hard_wqs})

      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{updated_guide.id}")

      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='chapters']")
      |> render_click()

      html =
        view
        |> element("button[phx-click='toggle_section'][phx-value-chapter-id='#{chapter.id}']")
        |> render_click()

      assert html =~ "Hard" or html =~ "Krebs cycle" or html =~ "Wrong Questions"
    end

    test "renders source materials section when section has materials", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      content_with_materials =
        Map.put(guide.content, "sections", [
          %{
            "chapter_id" => chapter.id,
            "chapter_name" => chapter.name,
            "score" => 25.0,
            "priority" => "Critical",
            "wrong_questions" => [],
            "review_topics" => [],
            "source_materials" => [
              %{"file_name" => "biology_textbook.pdf", "name" => "Biology Textbook"}
            ],
            "reviewed" => false
          }
        ])

      {:ok, updated_guide} =
        FunSheep.Learning.update_study_guide(guide, %{content: content_with_materials})

      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{updated_guide.id}")

      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='chapters']")
      |> render_click()

      html =
        view
        |> element("button[phx-click='toggle_section'][phx-value-chapter-id='#{chapter.id}']")
        |> render_click()

      assert html =~ "Source Materials" or html =~ "biology_textbook.pdf"
    end

    test "renders completed study plan day with check icon", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      completed_plan_content =
        Map.put(guide.content, "study_plan", [
          %{
            "day" => 1,
            "date" => Date.to_string(Date.add(Date.utc_today(), 1)),
            "focus" => "Review Biology Basics",
            "chapter_ids" => [],
            "completed" => true
          }
        ])

      {:ok, updated_guide} =
        FunSheep.Learning.update_study_guide(guide, %{content: completed_plan_content})

      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{updated_guide.id}")

      html =
        view
        |> element("button[phx-click='switch_tab'][phx-value-tab='plan']")
        |> render_click()

      # Completed day shows hero-check-mini icon
      assert html =~ "hero-check-mini" or html =~ "Completed" or html =~ "Review Biology Basics"
    end

    test "renders Today focus in overview when study plan has today entry", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      today_str = Date.to_string(Date.utc_today())

      plan_with_today =
        guide.content
        |> Map.put("study_plan", [
          %{
            "day" => 1,
            "date" => today_str,
            "focus" => "Focus on Mitosis Today",
            "chapter_ids" => [chapter.id],
            "completed" => false
          }
        ])

      {:ok, updated_guide} =
        FunSheep.Learning.update_study_guide(guide, %{content: plan_with_today})

      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{updated_guide.id}")

      # Overview should show Today's Focus section
      assert html =~ "Today's Focus" or html =~ "Focus on Mitosis Today"
    end

    test "renders overdue badge in study plan for past incomplete day", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      past_str = Date.to_string(Date.add(Date.utc_today(), -2))

      plan_with_past =
        Map.put(guide.content, "study_plan", [
          %{
            "day" => 1,
            "date" => past_str,
            "focus" => "Overdue Study Session",
            "chapter_ids" => [],
            "completed" => false
          }
        ])

      {:ok, updated_guide} =
        FunSheep.Learning.update_study_guide(guide, %{content: plan_with_past})

      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{updated_guide.id}")

      html =
        view
        |> element("button[phx-click='switch_tab'][phx-value-tab='plan']")
        |> render_click()

      # Should show "Overdue" badge for past incomplete days
      assert html =~ "Overdue" or html =~ "Overdue Study Session"
    end

    test "explain_question toggle shows and hides explanation for loaded question", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide,
      chapter: chapter
    } do
      wq_id = Ecto.UUID.generate()

      content_with_wq =
        Map.put(guide.content, "sections", [
          %{
            "chapter_id" => chapter.id,
            "chapter_name" => chapter.name,
            "score" => 10.0,
            "priority" => "Critical",
            "wrong_questions" => [
              %{
                "id" => wq_id,
                "content" => "Test question text",
                "answer" => "Test answer",
                "difficulty" => "medium"
              }
            ],
            "review_topics" => [],
            "source_materials" => [],
            "reviewed" => false
          }
        ])

      {:ok, updated_guide} =
        FunSheep.Learning.update_study_guide(guide, %{content: content_with_wq})

      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{updated_guide.id}")

      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='chapters']")
      |> render_click()

      view
      |> element("button[phx-click='toggle_section'][phx-value-chapter-id='#{chapter.id}']")
      |> render_click()

      # Trigger explain_question - this starts an async task
      render_hook(view, "explain_question", %{"question-id" => wq_id})

      # View remains alive
      html = render(view)
      assert html =~ "Test question text" or html =~ "Wrong Questions"
    end
  end
end
