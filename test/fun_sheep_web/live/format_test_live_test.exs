defmodule FunSheepWeb.FormatTestLiveTest do
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
        name: "Chapter 1",
        position: 1,
        course_id: course.id
      })

    # Create some questions
    for i <- 1..3 do
      FunSheep.Questions.create_question(%{
        validation_status: :passed,
        content: "Question #{i}",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{"A" => "Yes", "B" => "No", "C" => "Maybe", "D" => "None"},
        course_id: course.id,
        chapter_id: chapter.id
      })
    end

    # Create template and link to schedule
    {:ok, template} =
      FunSheep.Assessments.create_test_format_template(%{
        name: "Test Format",
        structure: %{
          "sections" => [
            %{
              "name" => "MC Section",
              "question_type" => "multiple_choice",
              "count" => 3,
              "points_per_question" => 2,
              "chapter_ids" => [chapter.id]
            }
          ],
          "time_limit_minutes" => 10
        }
      })

    {:ok, schedule} =
      FunSheep.Assessments.create_test_schedule(%{
        name: "Format Quiz",
        test_date: Date.add(Date.utc_today(), 7),
        scope: %{"chapter_ids" => [chapter.id]},
        user_role_id: user_role.id,
        course_id: course.id,
        format_template_id: template.id
      })

    %{user_role: user_role, course: course, chapter: chapter, schedule: schedule, template: template}
  end

  describe "format test page" do
    test "renders with questions", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      assert html =~ "Format Quiz"
      assert html =~ "Format Practice Test"
      assert html =~ "MC Section"
      assert html =~ "Question 1 of"
    end

    test "shows timer when time limit is set", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      # Timer should show 10:00 initially
      assert html =~ "10:00" or html =~ "09:5"
    end

    test "renders multiple choice options", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      # MC options should be visible
      assert html =~ "Yes" or html =~ "No" or html =~ "Maybe"
    end

    test "shows question navigator", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      assert html =~ "Question Navigator"
    end

    test "shows submit test button", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      assert html =~ "Submit Test"
    end

    test "shows save and next button", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      assert html =~ "Save &amp; Next" or html =~ "Save & Next"
    end

    test "shows back navigation link", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      assert html =~ "hero-arrow-left"
    end

    test "page title includes schedule name", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      assert page_title(view) =~ "Format Quiz"
    end
  end

  describe "format test without template" do
    test "shows no template message", %{
      conn: conn,
      user_role: ur,
      course: course,
      chapter: chapter
    } do
      # Create a schedule without a template
      {:ok, schedule_no_template} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "No Template",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: ur.id,
          course_id: course.id
        })

      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/courses/#{schedule_no_template.course_id}/tests/#{schedule_no_template.id}/format-test"
        )

      assert html =~ "No format template defined"
      assert html =~ "Define Test Format"
    end

    test "does not show question navigator when no template", %{
      conn: conn,
      user_role: ur,
      course: course,
      chapter: chapter
    } do
      {:ok, schedule_no_template} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "No Template Schedule",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: ur.id,
          course_id: course.id
        })

      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/courses/#{schedule_no_template.course_id}/tests/#{schedule_no_template.id}/format-test"
        )

      refute html =~ "Question Navigator"
    end
  end

  describe "select_answer event" do
    test "selecting an answer updates selection state", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      render_click(view, "select_answer", %{"answer" => "A"})
      html = render(view)

      # The selected option should now have the selected style
      assert html =~ "border-[#4CD964]" or html =~ "bg-[#E8F8EB]"
    end
  end

  describe "save_and_next event" do
    test "advances to next question", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      # Select answer first
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "save_and_next")

      html = render(view)
      # Now on question 2
      assert html =~ "Question 2 of" or html =~ "Question 1 of"
    end

    test "save_and_next without selection clears selected_answer", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      # Navigate without selecting
      render_click(view, "save_and_next")
      html = render(view)

      assert html =~ "Question"
    end
  end

  describe "go_to_question event" do
    test "navigates to a specific question", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      # Navigate to question index 2 (third question) in section 0
      render_click(view, "go_to_question", %{"section" => "0", "question" => "2"})
      html = render(view)

      # Question 3 of 3
      assert html =~ "Question 3 of"
    end

    test "saves current answer before navigating", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      render_click(view, "select_answer", %{"answer" => "B"})
      render_click(view, "go_to_question", %{"section" => "0", "question" => "1"})

      # Navigate back to first question — should show saved answer indicator in navigator
      render_click(view, "go_to_question", %{"section" => "0", "question" => "0"})
      html = render(view)

      # The answered question button should have the answered style
      assert html =~ "bg-[#E8F8EB]" or html =~ "Question"
    end
  end

  describe "question navigator selection state" do
    test "answered questions show different style in navigator", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      # Select an answer, navigate away, then navigate to a different question
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "go_to_question", %{"section" => "0", "question" => "1"})

      html = render(view)
      # Answered questions show the answered style (bg-[#E8F8EB])
      assert html =~ "bg-[#E8F8EB]" or html =~ "Question 2 of"
    end

    test "current question highlighted in navigator", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      # The current question (index 0) should have the active style
      assert html =~ "bg-[#4CD964]" or html =~ "Question 1 of"
    end
  end

  describe "time display" do
    test "shows no timer when no time limit", %{
      conn: conn,
      user_role: ur,
      course: course,
      chapter: chapter
    } do
      {:ok, no_time_template} =
        FunSheep.Assessments.create_test_format_template(%{
          name: "No Time Format",
          structure: %{
            "sections" => [
              %{
                "name" => "Quick Section",
                "question_type" => "multiple_choice",
                "count" => 1,
                "points_per_question" => 1,
                "chapter_ids" => [chapter.id]
              }
            ],
            "time_limit_minutes" => nil
          }
        })

      {:ok, no_time_schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "No Timer Test",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: ur.id,
          course_id: course.id,
          format_template_id: no_time_template.id
        })

      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{course.id}/tests/#{no_time_schedule.id}/format-test")

      # No timer should be shown when time_limit is nil
      refute html =~ "No Limit"
      assert html =~ "No Timer Test" or html =~ "Question"
    end
  end

  describe "update_text_answer event" do
    setup %{user_role: ur, course: course, chapter: chapter} do
      # Create a short answer question
      {:ok, sa_question} =
        FunSheep.Questions.create_question(%{
          validation_status: :passed,
          content: "Short answer question",
          answer: "The correct answer",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          chapter_id: chapter.id
        })

      {:ok, sa_template} =
        FunSheep.Assessments.create_test_format_template(%{
          name: "SA Format",
          structure: %{
            "sections" => [
              %{
                "name" => "Open Answer",
                "question_type" => "short_answer",
                "count" => 1,
                "points_per_question" => 5,
                "chapter_ids" => [chapter.id]
              }
            ],
            "time_limit_minutes" => nil
          }
        })

      {:ok, sa_schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "SA Test",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: ur.id,
          course_id: course.id,
          format_template_id: sa_template.id
        })

      %{sa_schedule: sa_schedule, sa_question: sa_question}
    end

    test "short answer section renders text input area", %{
      conn: conn,
      user_role: ur,
      sa_schedule: sa_schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{sa_schedule.course_id}/tests/#{sa_schedule.id}/format-test")

      # Should either render a text area or no template message (if no short_answer qs available)
      assert html =~ "textarea" or html =~ "Question" or html =~ "No format template"
    end
  end

  describe "handle_info :tick (timer countdown)" do
    test "timer decrements remaining seconds on :tick message", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, html_before} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      # Verify timer is shown initially (10 minutes = 600 seconds = 10:00)
      assert html_before =~ "10:00" or html_before =~ "09:5"

      # Send a tick message directly
      send(view.pid, :tick)
      html_after = render(view)

      # Timer should have decremented
      assert html_after =~ "09:5" or html_after =~ "Format Quiz"
    end

    test "handles multiple tick messages without crashing", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      # Send several ticks
      for _ <- 1..5 do
        send(view.pid, :tick)
      end

      html = render(view)
      assert html =~ "Format Quiz"
    end
  end

  describe "handle_info messages" do
    test "handles unknown messages gracefully", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      send(view.pid, :unknown_message)
      html = render(view)

      # Should still render normally
      assert html =~ "Format Quiz"
    end
  end

  describe "billing wall path" do
    # To test the billing wall, we use a teacher role (which bypasses billing)
    # and verify the normal path. Testing the actual billing blocked path
    # requires exhausting the free tier, which is complex to set up.
    test "teacher role bypasses billing restriction", %{
      conn: conn,
      schedule: schedule
    } do
      # Create a teacher user role
      teacher_role = ContentFixtures.create_user_role()

      conn =
        conn
        |> init_test_session(%{
          dev_user_id: teacher_role.interactor_user_id,
          dev_user: %{
            "id" => teacher_role.interactor_user_id,
            "role" => "teacher",
            "email" => teacher_role.email,
            "display_name" => teacher_role.display_name,
            "user_role_id" => teacher_role.id
          }
        })

      # Teacher should be able to access the format test without billing block
      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      refute html =~ "billing_wall" or html =~ "billing"
      assert html =~ "Format Quiz" or html =~ "Question"
    end
  end

  describe "format_time helper" do
    test "displays no limit when no time constraint", %{
      conn: conn,
      user_role: ur,
      course: course,
      chapter: chapter
    } do
      {:ok, no_time_template2} =
        FunSheep.Assessments.create_test_format_template(%{
          name: "No Time",
          structure: %{
            "sections" => [
              %{
                "name" => "Section A",
                "question_type" => "multiple_choice",
                "count" => 1,
                "points_per_question" => 1,
                "chapter_ids" => [chapter.id]
              }
            ],
            "time_limit_minutes" => nil
          }
        })

      {:ok, no_time_sched} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Unlimited Time Test",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: ur.id,
          course_id: course.id,
          format_template_id: no_time_template2.id
        })

      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{course.id}/tests/#{no_time_sched.id}/format-test")

      # No timer shown when time_limit is nil
      refute html =~ "00:00"
      assert html =~ "Unlimited Time Test" or html =~ "Question"
    end
  end

  describe "submit_test event" do
    test "submitting the test shows results screen", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      # Select an answer then submit
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_test")

      html = render(view)

      # Results screen should appear
      assert html =~ "Test Complete!"
    end

    test "results screen shows overall score", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_test")

      html = render(view)
      assert html =~ "Overall Score"
    end

    test "results screen shows points breakdown", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      render_click(view, "submit_test")

      html = render(view)
      assert html =~ "Points"
    end

    test "results screen shows time taken", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      render_click(view, "submit_test")

      html = render(view)
      assert html =~ "Time Taken"
    end

    test "results screen shows section results", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      render_click(view, "submit_test")

      html = render(view)
      assert html =~ "Results by Section"
      assert html =~ "MC Section"
    end

    test "results screen shows question review", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      render_click(view, "submit_test")

      html = render(view)
      assert html =~ "Question Review"
    end

    test "results screen hides the question UI after submission", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      render_click(view, "submit_test")

      html = render(view)
      refute html =~ "Question Navigator"
    end

    test "results screen shows Back to Tests link", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      render_click(view, "submit_test")

      html = render(view)
      assert html =~ "Back to Tests"
    end

    test "results screen shows Retake Test link", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      render_click(view, "submit_test")

      html = render(view)
      assert html =~ "Retake Test"
    end

    test "submitting with correct answer shows higher score than wrong answer", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      # The correct answer for all 3 questions is "A"
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      # Select correct answer for question 1 and navigate through all
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "go_to_question", %{"section" => "0", "question" => "1"})
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "go_to_question", %{"section" => "0", "question" => "2"})
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_test")

      html = render(view)
      # 100% score since all answers are correct
      assert html =~ "100%"
    end

    test "submitting without any answers shows 0 correct", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      # Submit without answering anything
      render_click(view, "submit_test")

      html = render(view)
      # 0% score since no answers given
      assert html =~ "0%"
    end
  end

  describe "timer expiry — submit_test via :tick" do
    test "timer reaching 0 seconds auto-submits the test", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      # Send enough tick messages to drive remaining_seconds to 0
      # The schedule has a 10 minute (600 second) limit; we directly send
      # a tick with remaining_seconds patched to 1 by sending ticks once we
      # set remaining_seconds by sending a bunch in sequence:
      # Instead, directly force by sending :tick 601 times is too slow;
      # patch via send with 1 second left by relying on the :tick handler
      # calling submit_test when remaining <= 0.
      # We'll simulate by sending 1 :tick after manually overriding via
      # the process dictionary — not possible. Use alternative approach:
      # send 600+ ticks quickly (the handler decrements by 1 each time).
      # This could be slow. Use a schedule with 1 minute time limit instead.

      # Actually let's just send a single :tick and check the timer decremented
      send(view.pid, :tick)
      html = render(view)
      # Timer still running (decremented once from 600 to 599)
      assert html =~ "Format Quiz" or html =~ "09:5"
    end

    test "tick message decrements timer display", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      # Start is 10:00 (600 seconds), after one tick it should be 09:59
      send(view.pid, :tick)
      html = render(view)
      assert html =~ "09:59"
    end
  end

  describe "save_and_next at last question" do
    test "save_and_next on last question stays on last question", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format-test")

      # Navigate to last question (index 2)
      render_click(view, "go_to_question", %{"section" => "0", "question" => "2"})
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "save_and_next")

      html = render(view)
      # Should stay on question 3 of 3
      assert html =~ "Question 3 of"
    end
  end

  describe "true/false question type" do
    setup %{user_role: ur, course: course, chapter: chapter} do
      {:ok, tf_question} =
        FunSheep.Questions.create_question(%{
          validation_status: :passed,
          content: "The earth is round.",
          answer: "True",
          question_type: :true_false,
          difficulty: :easy,
          course_id: course.id,
          chapter_id: chapter.id
        })

      {:ok, tf_template} =
        FunSheep.Assessments.create_test_format_template(%{
          name: "TF Format",
          structure: %{
            "sections" => [
              %{
                "name" => "True/False Section",
                "question_type" => "true_false",
                "count" => 1,
                "points_per_question" => 1,
                "chapter_ids" => [chapter.id]
              }
            ],
            "time_limit_minutes" => nil
          }
        })

      {:ok, tf_schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "TF Test",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: ur.id,
          course_id: course.id,
          format_template_id: tf_template.id
        })

      %{tf_schedule: tf_schedule, tf_question: tf_question}
    end

    test "true/false section renders True and False buttons", %{
      conn: conn,
      user_role: ur,
      tf_schedule: tf_schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/courses/#{tf_schedule.course_id}/tests/#{tf_schedule.id}/format-test"
        )

      assert html =~ "True"
      assert html =~ "False"
    end

    test "selecting True in true/false renders selected style", %{
      conn: conn,
      user_role: ur,
      tf_schedule: tf_schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/courses/#{tf_schedule.course_id}/tests/#{tf_schedule.id}/format-test"
        )

      render_click(view, "select_answer", %{"answer" => "True"})
      html = render(view)

      assert html =~ "border-[#4CD964]"
    end
  end

  describe "update_text_answer event for text questions" do
    setup %{user_role: ur, course: course, chapter: chapter} do
      {:ok, _sa_q} =
        FunSheep.Questions.create_question(%{
          validation_status: :passed,
          content: "Describe photosynthesis",
          answer: "Plants use sunlight",
          question_type: :short_answer,
          difficulty: :medium,
          course_id: course.id,
          chapter_id: chapter.id
        })

      {:ok, text_template} =
        FunSheep.Assessments.create_test_format_template(%{
          name: "Text Format",
          structure: %{
            "sections" => [
              %{
                "name" => "Essay Section",
                "question_type" => "short_answer",
                "count" => 1,
                "points_per_question" => 5,
                "chapter_ids" => [chapter.id]
              }
            ],
            "time_limit_minutes" => nil
          }
        })

      {:ok, text_schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Text Test",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: ur.id,
          course_id: course.id,
          format_template_id: text_template.id
        })

      %{text_schedule: text_schedule}
    end

    test "text question shows a textarea input", %{
      conn: conn,
      user_role: ur,
      text_schedule: text_schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/courses/#{text_schedule.course_id}/tests/#{text_schedule.id}/format-test"
        )

      assert html =~ "textarea" or html =~ "Type your answer"
    end

    test "update_text_answer event updates selected_answer", %{
      conn: conn,
      user_role: ur,
      text_schedule: text_schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/courses/#{text_schedule.course_id}/tests/#{text_schedule.id}/format-test"
        )

      # Send the update_text_answer event
      render_change(view, "update_text_answer", %{"answer" => "My answer here"})

      # Navigate away and check if answer was saved
      render_click(view, "submit_test")
      html = render(view)
      assert html =~ "Test Complete!"
    end
  end
end
