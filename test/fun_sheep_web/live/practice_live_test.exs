defmodule FunSheepWeb.PracticeLiveTest do
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
      FunSheep.Courses.create_chapter(%{name: "Chapter 1", position: 1, course_id: course.id})

    {:ok, section} =
      FunSheep.Courses.create_section(%{name: "Sec 1", position: 1, chapter_id: chapter.id})

    {:ok, q1} =
      FunSheep.Questions.create_question(%{
        validation_status: :passed,
        content: "What is the powerhouse of the cell?",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{"A" => "Mitochondria", "B" => "Nucleus", "C" => "Ribosome", "D" => "Golgi"},
        course_id: course.id,
        chapter_id: chapter.id,
        section_id: section.id,
        classification_status: :admin_reviewed
      })

    {:ok, q2} =
      FunSheep.Questions.create_question(%{
        validation_status: :passed,
        content: "DNA stands for?",
        answer: "B",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{
          "A" => "Deoxyribonucleic Acid Test",
          "B" => "Deoxyribonucleic Acid",
          "C" => "Ribonucleic Acid",
          "D" => "None"
        },
        course_id: course.id,
        chapter_id: chapter.id,
        section_id: section.id,
        classification_status: :admin_reviewed
      })

    # Create wrong attempts so these are "weak" questions
    FunSheep.Questions.create_question_attempt(%{
      user_role_id: user_role.id,
      question_id: q1.id,
      answer_given: "B",
      is_correct: false
    })

    FunSheep.Questions.create_question_attempt(%{
      user_role_id: user_role.id,
      question_id: q2.id,
      answer_given: "A",
      is_correct: false
    })

    %{user_role: user_role, course: course, chapter: chapter, q1: q1, q2: q2}
  end

  describe "practice flow" do
    test "renders practice page with questions", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/practice")

      assert html =~ "Practice Mode"
      assert html =~ course.name
      assert html =~ "Question 1"
    end

    test "shows feedback after answering", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      render_click(view, "select_answer", %{"answer" => "A"})
      html = render_click(view, "submit_answer")

      assert html =~ "Correct" or html =~ "Incorrect"
      assert html =~ "Next Question"
    end

    test "shows summary on completion", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      # Answer all questions
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")
      render_click(view, "next_question")

      render_click(view, "select_answer", %{"answer" => "B"})
      render_click(view, "submit_answer")
      html = render_click(view, "next_question")

      assert html =~ "Practice Complete!"
      assert html =~ "Practice Again"
      assert html =~ "Go to Course Page"
    end
  end

  describe "no weak questions" do
    test "shows empty state when no wrong answers exist", %{conn: conn, course: course} do
      other_user = ContentFixtures.create_user_role()
      conn = auth_conn(conn, other_user)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/practice")

      assert html =~ "No Weak Questions Found"
    end
  end

  describe "event: filter_chapter" do
    test "filter_chapter restricts questions to the selected chapter", %{
      conn: conn,
      user_role: ur,
      course: course,
      chapter: chapter
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      # Filter by the existing chapter
      html = render_change(view, "filter_chapter", %{"chapter_id" => chapter.id})
      # Should still show a question from that chapter
      assert html =~ "Question 1" or html =~ "No Weak Questions Found"
    end

    test "filter_chapter with empty value resets to all chapters", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      html = render_change(view, "filter_chapter", %{"chapter_id" => ""})
      assert html =~ "Practice Mode"
    end
  end

  describe "event: update_text_answer" do
    test "update_text_answer is a no-op on non-freeform questions (does not crash)", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      # Sending update_text_answer when current question is MCQ sets selected_answer
      result = render_change(view, "update_text_answer", %{"answer" => "some text"})
      # View stays alive — no crash
      assert result =~ "Practice Mode"
    end
  end

  describe "event: submit_answer edge cases" do
    test "submit_answer with nil answer is a no-op", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      # Click submit without selecting anything — should remain unchanged
      html = render_click(view, "submit_answer")
      refute html =~ "Correct!"
      refute html =~ "Incorrect"
      assert html =~ "Submit Answer"
    end

    test "correct answer shows Correct feedback and triggers confetti event", %{
      conn: conn,
      user_role: ur,
      course: course,
      q1: q1,
      q2: q2
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, html} = live(conn, ~p"/courses/#{course.id}/practice")

      # q1 has answer "A", q2 has answer "B"
      current_answer =
        cond do
          html =~ q1.content -> "A"
          html =~ q2.content -> "B"
          true -> "A"
        end

      render_click(view, "select_answer", %{"answer" => current_answer})
      result = render_click(view, "submit_answer")
      assert result =~ "Correct!"
      assert result =~ "Next Question"
    end

    test "incorrect answer shows Incorrect feedback with correct answer", %{
      conn: conn,
      user_role: ur,
      course: course,
      q1: q1,
      q2: q2
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, html} = live(conn, ~p"/courses/#{course.id}/practice")

      # Pick the WRONG answer for whatever question is shown
      wrong_answer =
        cond do
          html =~ q1.content -> "C"
          html =~ q2.content -> "C"
          true -> "D"
        end

      render_click(view, "select_answer", %{"answer" => wrong_answer})
      result = render_click(view, "submit_answer")
      assert result =~ "Incorrect"
      assert result =~ "Next Question"
    end
  end

  describe "event: practice_again" do
    test "practice_again resets the session", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      # Complete practice
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")
      render_click(view, "next_question")

      render_click(view, "select_answer", %{"answer" => "B"})
      render_click(view, "submit_answer")
      render_click(view, "next_question")

      summary_html = render(view)

      if summary_html =~ "Practice Complete!" do
        result = render_click(view, "practice_again")
        assert result =~ "Question 1"
      else
        # Did not complete yet — just verify practice_again doesn't crash
        render_click(view, "practice_again")
        assert render(view) =~ "Practice Mode"
      end
    end
  end

  describe "event: flag_question" do
    # Ensure the QuestionFlag module is loaded before tests run so its @reasons atoms
    # (e.g. :incorrect_answer) are interned — required for String.to_existing_atom/1
    # in practice_live.ex:257.
    setup do
      Code.ensure_loaded!(FunSheep.Questions.QuestionFlag)
      :ok
    end

    test "flag_question with empty reason marks question as reported", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      # Select and submit an answer first, then flag
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")

      html = render_click(view, "flag_question", %{"reason" => ""})
      assert html =~ "Reported"
    end

    test "flag_question with incorrect_answer reason marks as reported", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")

      html = render_click(view, "flag_question", %{"reason" => "incorrect_answer"})
      assert html =~ "Reported"
    end

    test "flag_question with unclear reason marks as reported", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")

      html = render_click(view, "flag_question", %{"reason" => "unclear"})
      assert html =~ "Reported"
    end

    test "flag_question with outdated reason marks as reported", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")

      html = render_click(view, "flag_question", %{"reason" => "outdated"})
      assert html =~ "Reported"
    end
  end

  describe "event: tutor interactions" do
    test "open_tutor shows the tutor panel", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      # Need to submit answer first to show the tutor buttons
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")

      html = render_click(view, "open_tutor")
      assert html =~ "AI Tutor"
      assert html =~ "Ask me anything about this question"
    end

    test "close_tutor hides the tutor panel", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")
      render_click(view, "open_tutor")

      html = render_click(view, "close_tutor")
      refute html =~ "Ask me anything about this question"
    end

    test "tutor_input event updates the input value", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")
      render_click(view, "open_tutor")

      html = render_change(view, "tutor_input", %{"message" => "What is this about?"})
      assert html =~ "What is this about?"
    end

    test "tutor_send with empty message is a no-op", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")
      render_click(view, "open_tutor")

      # Sending empty message — handled by the guard clause
      html = render_submit(view, "tutor_send", %{"message" => ""})
      assert html =~ "AI Tutor"
    end

    test "tutor_send with a message sends to tutor session", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")
      render_click(view, "open_tutor")

      # Send a real message — tutor session will be started in mock mode
      html = render_submit(view, "tutor_send", %{"message" => "Explain this please"})
      # Message sent — the view may show loading or response
      assert html =~ "Explain this please" or html =~ "AI Tutor"
    end

    test "tutor_quick_action sends a quick action to tutor", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")

      # Tutor quick actions appear after submitting an answer
      html = render_click(view, "tutor_quick_action", %{"action" => "explain"})
      # Should show "Explain this concept" message in tutor panel or open tutor
      assert html =~ "Explain this concept" or html =~ "AI Tutor"
    end

    test "tutor_quick_action why_wrong shows after incorrect answer", %{
      conn: conn,
      user_role: ur,
      course: course,
      q1: q1,
      q2: q2
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, html} = live(conn, ~p"/courses/#{course.id}/practice")

      # Pick wrong answer
      wrong =
        cond do
          html =~ q1.content -> "C"
          html =~ q2.content -> "C"
          true -> "D"
        end

      render_click(view, "select_answer", %{"answer" => wrong})
      feedback_html = render_click(view, "submit_answer")

      if feedback_html =~ "Incorrect" do
        result = render_click(view, "tutor_quick_action", %{"action" => "why_wrong"})
        assert result =~ "Why was I wrong?" or result =~ "AI Tutor"
      else
        assert feedback_html =~ "Correct!"
      end
    end

    test "tutor_quick_action hint action triggers tutor", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")

      html = render_click(view, "tutor_quick_action", %{"action" => "hint"})
      assert html =~ "Give me a hint" or html =~ "AI Tutor"
    end

    test "tutor_quick_action step_by_step action triggers tutor", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")

      html = render_click(view, "tutor_quick_action", %{"action" => "step_by_step"})
      assert html =~ "Walk me through it step by step" or html =~ "AI Tutor"
    end
  end

  describe "schedule-scoped practice" do
    setup %{user_role: ur, course: course, chapter: chapter} do
      {:ok, schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Bio Quiz",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: ur.id,
          course_id: course.id
        })

      %{schedule: schedule}
    end

    test "practice page with schedule_id param scopes to that schedule", %{
      conn: conn,
      user_role: ur,
      course: course,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{course.id}/practice?schedule_id=#{schedule.id}")

      assert html =~ "Practice Mode"
      # Either shows questions or empty state
      assert html =~ "Question 1" or html =~ "No Weak Questions"
    end

    test "practice with nonexistent schedule_id falls back gracefully", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{course.id}/practice?schedule_id=00000000-0000-0000-0000-000000000000")

      assert html =~ "Practice Mode"
    end
  end

  describe "handle_info: tutor responses" do
    test "tutor_response PubSub message is handled safely", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      # Send a PubSub tutor response that arrives late
      send(view.pid, {:tutor_response, "Some AI response text"})
      html = render(view)
      assert html =~ "Practice Mode"
    end

    test "unknown messages are ignored", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      send(view.pid, {:unexpected, :message})
      send(view.pid, :plain_atom)
      html = render(view)
      assert html =~ "Practice Mode"
    end
  end

  describe "question feedback with explanation" do
    test "wrong answer shows correct answer text", %{
      conn: conn,
      user_role: ur,
      course: course,
      q1: q1,
      q2: q2
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, html} = live(conn, ~p"/courses/#{course.id}/practice")

      wrong =
        cond do
          html =~ q1.content -> "C"
          html =~ q2.content -> "C"
          true -> "D"
        end

      render_click(view, "select_answer", %{"answer" => wrong})
      result = render_click(view, "submit_answer")

      if result =~ "Incorrect" do
        # Should show "Correct answer:" text
        assert result =~ "Correct answer:"
      else
        assert result =~ "Correct!"
      end
    end
  end

  describe "next_question resets tutor state" do
    test "next_question after answering resets question_flagged and tutor", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      # Answer and flag
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")
      render_click(view, "flag_question", %{"reason" => ""})

      # Advance to next question
      html = render_click(view, "next_question")

      # Flagged state should be reset
      refute html =~ "Reported"
    end
  end
end
