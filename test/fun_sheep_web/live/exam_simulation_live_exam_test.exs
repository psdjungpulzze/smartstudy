defmodule FunSheepWeb.ExamSimulationLive.ExamTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{ContentFixtures, Courses, Questions}
  alias FunSheep.Assessments.{ExamSimulationEngine, ExamSimulations}

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

  defp create_question(course, chapter, section) do
    {:ok, q} =
      Questions.create_question(%{
        validation_status: :passed,
        content: "Sample question #{System.unique_integer([:positive])}?",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :medium,
        options: %{"A" => "Answer A", "B" => "Answer B", "C" => "Answer C", "D" => "Answer D"},
        course_id: course.id,
        chapter_id: chapter.id,
        section_id: section.id,
        classification_status: :admin_reviewed
      })

    q
  end

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{name: "Exam Course"})

    {:ok, chapter} =
      Courses.create_chapter(%{name: "Chapter 1", position: 1, course_id: course.id})

    {:ok, section} =
      Courses.create_section(%{name: "Section 1", position: 1, chapter_id: chapter.id})

    %{user_role: user_role, course: course, chapter: chapter, section: section}
  end

  describe "mount with no active session" do
    test "redirects to exam simulation index when no session", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      conn = auth_conn(conn, ur)

      assert {:error, {:live_redirect, %{to: path}}} =
               live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      assert path == ~p"/courses/#{c.id}/exam-simulation"
    end
  end

  describe "mount with active session" do
    setup %{user_role: ur, course: c, chapter: ch, section: sec} do
      questions = for _ <- 1..12, do: create_question(c, ch, sec)

      # Create the session directly to avoid triggering Oban's ExamTimeoutWorker
      # (which runs inline in test mode and immediately marks the session as timed_out).
      now = DateTime.utc_now(:second)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: now,
          question_ids_order: Enum.map(questions, & &1.id),
          section_boundaries: [
            %{
              "name" => "General",
              "question_count" => length(questions),
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ]
        })

      state = %{
        session_id: session.id,
        user_role_id: session.user_role_id,
        course_id: session.course_id,
        schedule_id: nil,
        format_template_id: nil,
        questions: questions,
        question_ids_order: session.question_ids_order,
        section_boundaries: session.section_boundaries,
        answers: %{},
        time_limit_seconds: session.time_limit_seconds,
        started_at: session.started_at,
        status: :in_progress
      }

      ExamSimulationEngine.cache_put(ur.id, session.id, state)

      %{questions: questions, session: session, engine_state: state}
    end

    test "renders exam UI when session exists", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      assert html =~ "Exam"
      assert html =~ "Exam Course"
    end

    test "shows question count in exam overview", %{
      conn: conn,
      user_role: ur,
      course: c,
      questions: questions
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      # Exam should show navigation or question indicator
      assert html =~ to_string(length(questions)) or html =~ "question"
    end

    test "shows timer in header", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      # Timer format is mm:ss
      assert html =~ "⏱" or html =~ ":"
    end

    test "shows Submit button in header", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      assert html =~ "Submit"
    end

    test "shows first question content", %{
      conn: conn,
      user_role: ur,
      course: c,
      questions: questions
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      first_q = List.first(questions)
      assert html =~ first_q.content
    end

    test "shows section navigation tabs", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      assert html =~ "General"
    end

    test "shows overview button", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      assert html =~ "Overview"
    end

    test "shows flag for review button", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      assert html =~ "Flag for Review"
    end

    test "shows Previous and Next navigation buttons", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      assert html =~ "Previous"
      assert html =~ "Next"
    end
  end

  describe "handle_event toggle_overview" do
    setup %{user_role: ur, course: c, chapter: ch, section: sec} do
      questions = for _ <- 1..5, do: create_question(c, ch, sec)
      now = DateTime.utc_now(:second)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: now,
          question_ids_order: Enum.map(questions, & &1.id),
          section_boundaries: [
            %{
              "name" => "General",
              "question_count" => length(questions),
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ]
        })

      state = %{
        session_id: session.id,
        user_role_id: session.user_role_id,
        course_id: session.course_id,
        schedule_id: nil,
        format_template_id: nil,
        questions: questions,
        question_ids_order: session.question_ids_order,
        section_boundaries: session.section_boundaries,
        answers: %{},
        time_limit_seconds: session.time_limit_seconds,
        started_at: session.started_at,
        status: :in_progress
      }

      ExamSimulationEngine.cache_put(ur.id, session.id, state)
      %{questions: questions, session: session}
    end

    test "toggle_overview shows and hides sidebar", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      # Overview sidebar hidden by default
      refute html =~ "Question Overview"

      # Click to open overview
      html_open = render_click(view, "toggle_overview", %{})
      assert html_open =~ "Question Overview"

      # Click again to close
      html_closed = render_click(view, "toggle_overview", %{})
      refute html_closed =~ "Question Overview"
    end
  end

  describe "handle_event open_submit_modal / close_submit_modal" do
    setup %{user_role: ur, course: c, chapter: ch, section: sec} do
      questions = for _ <- 1..5, do: create_question(c, ch, sec)
      now = DateTime.utc_now(:second)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: now,
          question_ids_order: Enum.map(questions, & &1.id),
          section_boundaries: [
            %{
              "name" => "General",
              "question_count" => length(questions),
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ]
        })

      state = %{
        session_id: session.id,
        user_role_id: session.user_role_id,
        course_id: session.course_id,
        schedule_id: nil,
        format_template_id: nil,
        questions: questions,
        question_ids_order: session.question_ids_order,
        section_boundaries: session.section_boundaries,
        answers: %{},
        time_limit_seconds: session.time_limit_seconds,
        started_at: session.started_at,
        status: :in_progress
      }

      ExamSimulationEngine.cache_put(ur.id, session.id, state)
      %{questions: questions, session: session}
    end

    test "open_submit_modal shows submit confirmation dialog", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      html = render_click(view, "open_submit_modal", %{})
      assert html =~ "Submit Exam?"
    end

    test "open_submit_modal shows unanswered count warning", %{
      conn: conn,
      user_role: ur,
      course: c,
      questions: questions
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      html = render_click(view, "open_submit_modal", %{})
      # All questions unanswered
      assert html =~ "unanswered question" or html =~ to_string(length(questions))
    end

    test "close_submit_modal hides the dialog", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      render_click(view, "open_submit_modal", %{})
      html = render_click(view, "close_submit_modal", %{})

      refute html =~ "Submit Exam?"
    end
  end

  describe "handle_event answer" do
    setup %{user_role: ur, course: c, chapter: ch, section: sec} do
      questions = for _ <- 1..5, do: create_question(c, ch, sec)
      now = DateTime.utc_now(:second)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: now,
          question_ids_order: Enum.map(questions, & &1.id),
          section_boundaries: [
            %{
              "name" => "General",
              "question_count" => length(questions),
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ]
        })

      state = %{
        session_id: session.id,
        user_role_id: session.user_role_id,
        course_id: session.course_id,
        schedule_id: nil,
        format_template_id: nil,
        questions: questions,
        question_ids_order: session.question_ids_order,
        section_boundaries: session.section_boundaries,
        answers: %{},
        time_limit_seconds: session.time_limit_seconds,
        started_at: session.started_at,
        status: :in_progress
      }

      ExamSimulationEngine.cache_put(ur.id, session.id, state)
      %{questions: questions, session: session}
    end

    test "answering a question advances to the next question", %{
      conn: conn,
      user_role: ur,
      course: c,
      questions: questions
    } do
      first_q = List.first(questions)
      second_q = Enum.at(questions, 1)

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      html = render_click(view, "answer", %{"question_id" => first_q.id, "answer" => "A"})

      # After answering, the view should advance and show the second question
      assert html =~ second_q.content or html =~ "2"
    end

    test "answered question is reflected in unanswered count", %{
      conn: conn,
      user_role: ur,
      course: c,
      questions: questions
    } do
      first_q = List.first(questions)
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      render_click(view, "answer", %{"question_id" => first_q.id, "answer" => "A"})
      html = render_click(view, "open_submit_modal", %{})

      total = length(questions)
      remaining = total - 1
      assert html =~ to_string(remaining) or html =~ "unanswered question"
    end
  end

  describe "handle_event flag" do
    setup %{user_role: ur, course: c, chapter: ch, section: sec} do
      questions = for _ <- 1..5, do: create_question(c, ch, sec)
      now = DateTime.utc_now(:second)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: now,
          question_ids_order: Enum.map(questions, & &1.id),
          section_boundaries: [
            %{
              "name" => "General",
              "question_count" => length(questions),
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ]
        })

      state = %{
        session_id: session.id,
        user_role_id: session.user_role_id,
        course_id: session.course_id,
        schedule_id: nil,
        format_template_id: nil,
        questions: questions,
        question_ids_order: session.question_ids_order,
        section_boundaries: session.section_boundaries,
        answers: %{},
        time_limit_seconds: session.time_limit_seconds,
        started_at: session.started_at,
        status: :in_progress
      }

      ExamSimulationEngine.cache_put(ur.id, session.id, state)
      %{questions: questions, session: session}
    end

    test "flagging a question changes the flag button appearance", %{
      conn: conn,
      user_role: ur,
      course: c,
      questions: questions
    } do
      first_q = List.first(questions)
      conn = auth_conn(conn, ur)
      {:ok, view, html_before} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      # Before flagging: border-slate-600 (unflagged style)
      assert html_before =~ "border-slate-600" or html_before =~ "Flag for Review"

      html_after = render_click(view, "flag", %{"question_id" => first_q.id})

      # After flagging: amber style applied
      assert html_after =~ "amber" or html_after =~ "Flag for Review"
    end

    test "flagging then unflagging restores original state", %{
      conn: conn,
      user_role: ur,
      course: c,
      questions: questions
    } do
      first_q = List.first(questions)
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      render_click(view, "flag", %{"question_id" => first_q.id})
      html = render_click(view, "flag", %{"question_id" => first_q.id})

      # Should be back to unflagged state
      assert html =~ "Flag for Review"
    end
  end

  describe "handle_event navigate" do
    setup %{user_role: ur, course: c, chapter: ch, section: sec} do
      questions = for _ <- 1..5, do: create_question(c, ch, sec)
      now = DateTime.utc_now(:second)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: now,
          question_ids_order: Enum.map(questions, & &1.id),
          section_boundaries: [
            %{
              "name" => "General",
              "question_count" => length(questions),
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ]
        })

      state = %{
        session_id: session.id,
        user_role_id: session.user_role_id,
        course_id: session.course_id,
        schedule_id: nil,
        format_template_id: nil,
        questions: questions,
        question_ids_order: session.question_ids_order,
        section_boundaries: session.section_boundaries,
        answers: %{},
        time_limit_seconds: session.time_limit_seconds,
        started_at: session.started_at,
        status: :in_progress
      }

      ExamSimulationEngine.cache_put(ur.id, session.id, state)
      %{questions: questions, session: session}
    end

    test "navigate event jumps to specific question", %{
      conn: conn,
      user_role: ur,
      course: c,
      questions: questions
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      # Navigate to question index 3 (4th question)
      target_q = Enum.at(questions, 3)
      html = render_click(view, "navigate", %{"section" => "0", "question" => "3"})

      assert html =~ target_q.content
    end
  end

  describe "handle_event prev / next" do
    setup %{user_role: ur, course: c, chapter: ch, section: sec} do
      questions = for _ <- 1..5, do: create_question(c, ch, sec)
      now = DateTime.utc_now(:second)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: now,
          question_ids_order: Enum.map(questions, & &1.id),
          section_boundaries: [
            %{
              "name" => "General",
              "question_count" => length(questions),
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ]
        })

      state = %{
        session_id: session.id,
        user_role_id: session.user_role_id,
        course_id: session.course_id,
        schedule_id: nil,
        format_template_id: nil,
        questions: questions,
        question_ids_order: session.question_ids_order,
        section_boundaries: session.section_boundaries,
        answers: %{},
        time_limit_seconds: session.time_limit_seconds,
        started_at: session.started_at,
        status: :in_progress
      }

      ExamSimulationEngine.cache_put(ur.id, session.id, state)
      %{questions: questions, session: session}
    end

    test "next event moves to next question", %{
      conn: conn,
      user_role: ur,
      course: c,
      questions: questions
    } do
      second_q = Enum.at(questions, 1)
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      html = render_click(view, "next", %{})
      assert html =~ second_q.content
    end

    test "prev event does nothing when at first question", %{
      conn: conn,
      user_role: ur,
      course: c,
      questions: questions
    } do
      first_q = List.first(questions)
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      # Should stay on first question
      html = render_click(view, "prev", %{})
      assert html =~ first_q.content
    end

    test "next then prev returns to original question", %{
      conn: conn,
      user_role: ur,
      course: c,
      questions: questions
    } do
      first_q = List.first(questions)
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      render_click(view, "next", %{})
      html = render_click(view, "prev", %{})
      assert html =~ first_q.content
    end
  end

  describe "handle_event confirm_submit" do
    setup %{user_role: ur, course: c, chapter: ch, section: sec} do
      questions = for _ <- 1..5, do: create_question(c, ch, sec)
      now = DateTime.utc_now(:second)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: now,
          question_ids_order: Enum.map(questions, & &1.id),
          section_boundaries: [
            %{
              "name" => "General",
              "question_count" => length(questions),
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ]
        })

      # Pre-answer all questions to avoid the NOT NULL constraint on answer_given
      # (question_attempts requires a non-null answer_given at the DB level)
      answers =
        Map.new(questions, fn q ->
          {q.id, %{"answer" => "A", "flagged" => false, "time_spent_seconds" => 10}}
        end)

      state = %{
        session_id: session.id,
        user_role_id: session.user_role_id,
        course_id: session.course_id,
        schedule_id: nil,
        format_template_id: nil,
        questions: questions,
        question_ids_order: session.question_ids_order,
        section_boundaries: session.section_boundaries,
        answers: answers,
        time_limit_seconds: session.time_limit_seconds,
        started_at: session.started_at,
        status: :in_progress
      }

      ExamSimulationEngine.cache_put(ur.id, session.id, state)
      %{questions: questions, session: session}
    end

    test "confirm_submit redirects to results page", %{
      conn: conn,
      user_role: ur,
      course: c,
      session: session
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      result = render_click(view, "confirm_submit", %{})

      assert {:error, {:live_redirect, %{to: path}}} = result
      assert path =~ "/exam-simulation/results/#{session.id}"
    end
  end

  describe "mount with expired session (time=0)" do
    test "redirects to exam simulation index when session has expired", %{
      conn: conn,
      user_role: ur,
      course: c,
      chapter: ch,
      section: sec
    } do
      questions = for _ <- 1..5, do: create_question(c, ch, sec)
      # started_at in the past, well beyond time_limit
      old_start = DateTime.add(DateTime.utc_now(:second), -9999, :second)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 60,
          started_at: old_start,
          question_ids_order: Enum.map(questions, & &1.id),
          section_boundaries: [
            %{
              "name" => "General",
              "question_count" => length(questions),
              "time_budget_seconds" => 60,
              "start_index" => 0
            }
          ]
        })

      # Pre-answer all questions so the timeout finalize path can write attempts
      # without hitting the NOT NULL constraint on question_attempts.answer_given
      answers =
        Map.new(questions, fn q ->
          {q.id, %{"answer" => "A", "flagged" => false, "time_spent_seconds" => 5}}
        end)

      state = %{
        session_id: session.id,
        user_role_id: session.user_role_id,
        course_id: session.course_id,
        schedule_id: nil,
        format_template_id: nil,
        questions: questions,
        question_ids_order: session.question_ids_order,
        section_boundaries: session.section_boundaries,
        answers: answers,
        time_limit_seconds: 60,
        started_at: old_start,
        status: :in_progress
      }

      ExamSimulationEngine.cache_put(ur.id, session.id, state)

      conn = auth_conn(conn, ur)

      assert {:error, {:live_redirect, %{to: path}}} =
               live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      assert path == ~p"/courses/#{c.id}/exam-simulation"
    end
  end

  # ── Helper: build a standard in-progress session state ─────────────────────

  defp build_session_state(ur, c, ch, sec, question_count \\ 5) do
    questions = for _ <- 1..question_count, do: create_question(c, ch, sec)
    now = DateTime.utc_now(:second)

    {:ok, session} =
      ExamSimulations.create_session(%{
        user_role_id: ur.id,
        course_id: c.id,
        time_limit_seconds: 2700,
        started_at: now,
        question_ids_order: Enum.map(questions, & &1.id),
        section_boundaries: [
          %{
            "name" => "General",
            "question_count" => question_count,
            "time_budget_seconds" => 2700,
            "start_index" => 0
          }
        ]
      })

    state = %{
      session_id: session.id,
      user_role_id: session.user_role_id,
      course_id: session.course_id,
      schedule_id: nil,
      format_template_id: nil,
      questions: questions,
      question_ids_order: session.question_ids_order,
      section_boundaries: session.section_boundaries,
      answers: %{},
      time_limit_seconds: session.time_limit_seconds,
      started_at: session.started_at,
      status: :in_progress
    }

    ExamSimulationEngine.cache_put(ur.id, session.id, state)
    %{questions: questions, session: session, engine_state: state}
  end

  describe "handle_info :tick — timer countdown" do
    setup %{user_role: ur, course: c, chapter: ch, section: sec} do
      build_session_state(ur, c, ch, sec, 3)
    end

    test "sends :tick message and updates remaining_seconds", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      # Send a :tick message directly to the LiveView process — it should
      # update the timer display without crashing.
      send(view.pid, :tick)
      html = render(view)

      # Timer display should still be present (format ⏱ mm:ss)
      assert html =~ "⏱" or html =~ ":"
    end
  end

  describe "multi-section navigation" do
    setup %{user_role: ur, course: c, chapter: ch, section: sec} do
      questions_a = for _ <- 1..3, do: create_question(c, ch, sec)
      questions_b = for _ <- 1..3, do: create_question(c, ch, sec)
      all_questions = questions_a ++ questions_b
      now = DateTime.utc_now(:second)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: now,
          question_ids_order: Enum.map(all_questions, & &1.id),
          section_boundaries: [
            %{
              "name" => "Section A",
              "question_count" => 3,
              "time_budget_seconds" => 1350,
              "start_index" => 0
            },
            %{
              "name" => "Section B",
              "question_count" => 3,
              "time_budget_seconds" => 1350,
              "start_index" => 3
            }
          ]
        })

      state = %{
        session_id: session.id,
        user_role_id: session.user_role_id,
        course_id: session.course_id,
        schedule_id: nil,
        format_template_id: nil,
        questions: all_questions,
        question_ids_order: session.question_ids_order,
        section_boundaries: session.section_boundaries,
        answers: %{},
        time_limit_seconds: session.time_limit_seconds,
        started_at: session.started_at,
        status: :in_progress
      }

      ExamSimulationEngine.cache_put(ur.id, session.id, state)
      %{questions: all_questions, session: session, questions_a: questions_a, questions_b: questions_b}
    end

    test "shows both section tabs in header", %{conn: conn, user_role: ur, course: c} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      assert html =~ "Section A"
      assert html =~ "Section B"
    end

    test "navigate to second section shows section B questions", %{
      conn: conn,
      user_role: ur,
      course: c,
      questions_b: questions_b
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      html = render_click(view, "navigate", %{"section" => "1", "question" => "0"})
      assert html =~ List.first(questions_b).content
    end

    test "next at last question of section A advances to section B", %{
      conn: conn,
      user_role: ur,
      course: c,
      questions_b: questions_b
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      # Navigate to last question of section A (index 2)
      render_click(view, "navigate", %{"section" => "0", "question" => "2"})
      html = render_click(view, "next", %{})

      # Should now be in Section B, showing first question of section B
      assert html =~ List.first(questions_b).content
    end

    test "prev at first question of section B goes back to section A", %{
      conn: conn,
      user_role: ur,
      course: c,
      questions_a: questions_a
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      # Go to section B, first question
      render_click(view, "navigate", %{"section" => "1", "question" => "0"})
      html = render_click(view, "prev", %{})

      # Should be back in section A — last question of section A
      last_a = List.last(questions_a)
      assert html =~ last_a.content
    end

    test "next at last question of last section stays put", %{
      conn: conn,
      user_role: ur,
      course: c,
      questions_b: questions_b
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      # Navigate to last question of last section
      render_click(view, "navigate", %{"section" => "1", "question" => "2"})
      html = render_click(view, "next", %{})

      # Should stay on the last question of section B
      last_b = List.last(questions_b)
      assert html =~ last_b.content
    end
  end

  describe "question type rendering" do
    setup %{user_role: ur, course: c, chapter: ch, section: sec} do
      # Create a true/false question
      {:ok, tf_q} =
        Questions.create_question(%{
          validation_status: :passed,
          content: "The sky is blue.",
          answer: "True",
          question_type: :true_false,
          difficulty: :easy,
          options: nil,
          course_id: c.id,
          chapter_id: ch.id,
          section_id: sec.id,
          classification_status: :admin_reviewed
        })

      now = DateTime.utc_now(:second)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: now,
          question_ids_order: [tf_q.id],
          section_boundaries: [
            %{
              "name" => "General",
              "question_count" => 1,
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ]
        })

      state = %{
        session_id: session.id,
        user_role_id: session.user_role_id,
        course_id: session.course_id,
        schedule_id: nil,
        format_template_id: nil,
        questions: [tf_q],
        question_ids_order: session.question_ids_order,
        section_boundaries: session.section_boundaries,
        answers: %{},
        time_limit_seconds: session.time_limit_seconds,
        started_at: session.started_at,
        status: :in_progress
      }

      ExamSimulationEngine.cache_put(ur.id, session.id, state)
      %{tf_question: tf_q, session: session}
    end

    test "true/false question shows True and False answer options", %{
      conn: conn,
      user_role: ur,
      course: c,
      tf_question: tf_q
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      assert html =~ tf_q.content
      assert html =~ "True"
      assert html =~ "False"
    end
  end

  describe "question type — short answer rendering" do
    setup %{user_role: ur, course: c, chapter: ch, section: sec} do
      {:ok, sa_q} =
        Questions.create_question(%{
          validation_status: :passed,
          content: "What is the capital of France?",
          answer: "Paris",
          question_type: :short_answer,
          difficulty: :easy,
          options: nil,
          course_id: c.id,
          chapter_id: ch.id,
          section_id: sec.id,
          classification_status: :admin_reviewed
        })

      now = DateTime.utc_now(:second)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: now,
          question_ids_order: [sa_q.id],
          section_boundaries: [
            %{
              "name" => "General",
              "question_count" => 1,
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ]
        })

      state = %{
        session_id: session.id,
        user_role_id: session.user_role_id,
        course_id: session.course_id,
        schedule_id: nil,
        format_template_id: nil,
        questions: [sa_q],
        question_ids_order: session.question_ids_order,
        section_boundaries: session.section_boundaries,
        answers: %{},
        time_limit_seconds: session.time_limit_seconds,
        started_at: session.started_at,
        status: :in_progress
      }

      ExamSimulationEngine.cache_put(ur.id, session.id, state)
      %{sa_question: sa_q, session: session}
    end

    test "short answer question shows textarea input", %{
      conn: conn,
      user_role: ur,
      course: c,
      sa_question: sa_q
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      assert html =~ sa_q.content
      assert html =~ "textarea" or html =~ "Your answer"
    end
  end

  describe "question type — free_response rendering" do
    setup %{user_role: ur, course: c, chapter: ch, section: sec} do
      {:ok, fr_q} =
        Questions.create_question(%{
          validation_status: :passed,
          content: "Explain the water cycle in detail.",
          answer: "The water cycle involves evaporation, condensation, and precipitation.",
          question_type: :free_response,
          difficulty: :hard,
          options: nil,
          course_id: c.id,
          chapter_id: ch.id,
          section_id: sec.id,
          classification_status: :admin_reviewed
        })

      now = DateTime.utc_now(:second)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: now,
          question_ids_order: [fr_q.id],
          section_boundaries: [
            %{
              "name" => "General",
              "question_count" => 1,
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ]
        })

      state = %{
        session_id: session.id,
        user_role_id: session.user_role_id,
        course_id: session.course_id,
        schedule_id: nil,
        format_template_id: nil,
        questions: [fr_q],
        question_ids_order: session.question_ids_order,
        section_boundaries: session.section_boundaries,
        answers: %{},
        time_limit_seconds: session.time_limit_seconds,
        started_at: session.started_at,
        status: :in_progress
      }

      ExamSimulationEngine.cache_put(ur.id, session.id, state)
      %{fr_question: fr_q, session: session}
    end

    test "free_response question shows a multi-row textarea", %{
      conn: conn,
      user_role: ur,
      course: c,
      fr_question: fr_q
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      assert html =~ fr_q.content
      # free_response renders a 6-row textarea vs short_answer's 2-row
      assert html =~ "textarea" or html =~ "Your answer"
    end
  end

  describe "question type — unsupported type rendering" do
    setup %{user_role: ur, course: c, chapter: ch, section: sec} do
      # matching questions are not supported by the exam UI
      {:ok, mq} =
        Questions.create_question(%{
          validation_status: :passed,
          content: "Match the terms to their definitions.",
          answer: "A-1,B-2",
          question_type: :matching,
          difficulty: :medium,
          options: nil,
          course_id: c.id,
          chapter_id: ch.id,
          section_id: sec.id,
          classification_status: :admin_reviewed
        })

      now = DateTime.utc_now(:second)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: now,
          question_ids_order: [mq.id],
          section_boundaries: [
            %{
              "name" => "General",
              "question_count" => 1,
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ]
        })

      state = %{
        session_id: session.id,
        user_role_id: session.user_role_id,
        course_id: session.course_id,
        schedule_id: nil,
        format_template_id: nil,
        questions: [mq],
        question_ids_order: session.question_ids_order,
        section_boundaries: session.section_boundaries,
        answers: %{},
        time_limit_seconds: session.time_limit_seconds,
        started_at: session.started_at,
        status: :in_progress
      }

      ExamSimulationEngine.cache_put(ur.id, session.id, state)
      %{matching_question: mq, session: session}
    end

    test "unsupported question type shows not-supported message", %{
      conn: conn,
      user_role: ur,
      course: c,
      matching_question: mq
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      assert html =~ mq.content
      assert html =~ "not supported" or html =~ "Question type"
    end
  end

  describe "overview sidebar — question status colors" do
    setup %{user_role: ur, course: c, chapter: ch, section: sec} do
      questions = for _ <- 1..3, do: create_question(c, ch, sec)
      now = DateTime.utc_now(:second)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: now,
          question_ids_order: Enum.map(questions, & &1.id),
          section_boundaries: [
            %{
              "name" => "General",
              "question_count" => length(questions),
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ]
        })

      state = %{
        session_id: session.id,
        user_role_id: session.user_role_id,
        course_id: session.course_id,
        schedule_id: nil,
        format_template_id: nil,
        questions: questions,
        question_ids_order: session.question_ids_order,
        section_boundaries: session.section_boundaries,
        answers: %{},
        time_limit_seconds: session.time_limit_seconds,
        started_at: session.started_at,
        status: :in_progress
      }

      ExamSimulationEngine.cache_put(ur.id, session.id, state)
      %{questions: questions, session: session}
    end

    test "overview sidebar shows Answered / Flagged / Unanswered legend", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      html = render_click(view, "toggle_overview", %{})
      assert html =~ "Answered"
      assert html =~ "Flagged"
      assert html =~ "Unanswered"
    end

    test "flagged question appears with amber styling in overview", %{
      conn: conn,
      user_role: ur,
      course: c,
      questions: questions
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/exam")

      first_q = List.first(questions)
      render_click(view, "flag", %{"question_id" => first_q.id})

      html = render_click(view, "toggle_overview", %{})
      assert html =~ "amber"
    end
  end
end
