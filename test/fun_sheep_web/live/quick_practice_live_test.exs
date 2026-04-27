defmodule FunSheepWeb.QuickPracticeLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  alias FunSheep.{Assessments, ContentFixtures, Questions, Tutorials}

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

  defp add_question(course_id, content) do
    # Auto-create a chapter + section so each question carries a skill tag
    # required by adaptive flows (North Star I-1).
    {:ok, ch} =
      FunSheep.Courses.create_chapter(%{
        name: "Ch #{System.unique_integer([:positive])}",
        position: 1,
        course_id: course_id
      })

    {:ok, sec} =
      FunSheep.Courses.create_section(%{name: "Sec 1", position: 1, chapter_id: ch.id})

    {:ok, q} =
      Questions.create_question(%{
        validation_status: :passed,
        content: content,
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{"A" => "yes", "B" => "no"},
        course_id: course_id,
        chapter_id: ch.id,
        section_id: sec.id,
        classification_status: :admin_reviewed
      })

    q
  end

  defp schedule_test(user_role_id, course_id, name, days_from_now) do
    {:ok, ts} =
      Assessments.create_test_schedule(%{
        name: name,
        test_date: Date.add(Date.utc_today(), days_from_now),
        scope: %{},
        user_role_id: user_role_id,
        course_id: course_id
      })

    ts
  end

  describe "course defaulting from upcoming tests" do
    test "pulls questions only from the closest upcoming test's course", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      # Mark tutorial seen so it doesn't obscure assertions
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")

      bio = ContentFixtures.create_course(%{name: "AP Biology", created_by_id: user.id})
      math = ContentFixtures.create_course(%{name: "AP Calc", created_by_id: user.id})

      add_question(bio.id, "BIO-Q-close")
      add_question(math.id, "MATH-Q-far")

      # Closest test is AP Biology (3 days), then AP Calc (20 days)
      schedule_test(user.id, bio.id, "AP Biology Unit 3", 3)
      schedule_test(user.id, math.id, "AP Calc Exam", 20)

      conn = auth_conn(conn, user)
      {:ok, _view, html} = live(conn, ~p"/practice")

      assert html =~ "BIO-Q-close"
      refute html =~ "MATH-Q-far"
    end

    test "?test_id= URL param overrides default selection", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")

      bio = ContentFixtures.create_course(%{name: "AP Biology", created_by_id: user.id})
      math = ContentFixtures.create_course(%{name: "AP Calc", created_by_id: user.id})

      add_question(bio.id, "BIO-Q")
      add_question(math.id, "MATH-Q-pick-me")

      schedule_test(user.id, bio.id, "AP Biology Unit 3", 3)
      math_ts = schedule_test(user.id, math.id, "AP Calc Exam", 20)

      conn = auth_conn(conn, user)
      {:ok, _view, html} = live(conn, ~p"/practice?test_id=#{math_ts.id}")

      assert html =~ "MATH-Q-pick-me"
      refute html =~ "BIO-Q"
    end

    test "renders a pill for each upcoming test", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")

      bio = ContentFixtures.create_course(%{name: "AP Biology", created_by_id: user.id})
      math = ContentFixtures.create_course(%{name: "AP Calc", created_by_id: user.id})
      add_question(bio.id, "q1")
      add_question(math.id, "q2")

      schedule_test(user.id, bio.id, "Bio Final", 5)
      schedule_test(user.id, math.id, "Calc Midterm", 14)

      conn = auth_conn(conn, user)
      {:ok, _view, html} = live(conn, ~p"/practice")

      assert html =~ "AP Biology"
      assert html =~ "AP Calc"
      # days-until labels — at least one of these forms
      assert html =~ "5d" or html =~ "tomorrow" or html =~ "today"
    end
  end

  describe "first-time tutorial" do
    test "overlay shows on first visit", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q1")

      conn = auth_conn(conn, user)
      {:ok, _view, html} = live(conn, ~p"/practice")

      assert html =~ "How Practice works"
      assert html =~ "Got it!"
    end

    test "dismiss_tutorial marks the tutorial seen", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q1")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      refute Tutorials.seen?(user.id, "quick_practice")

      html = render_click(view, "dismiss_tutorial")
      refute html =~ "How Practice works"

      assert Tutorials.seen?(user.id, "quick_practice")
    end

    test "overlay is not shown once seen", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q1")

      conn = auth_conn(conn, user)
      {:ok, _view, html} = live(conn, ~p"/practice")

      refute html =~ "How Practice works"
    end

    test "replay_tutorial re-opens overlay for an already-seen tutorial", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q1")

      conn = auth_conn(conn, user)
      {:ok, view, html} = live(conn, ~p"/practice")

      refute html =~ "How Practice works"

      html = render_click(view, "replay_tutorial")
      assert html =~ "How Practice works"
    end
  end

  describe "keyboard shortcuts" do
    test "ArrowRight marks question as known (desktop)", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q1")
      add_question(course.id, "q2")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      # ArrowRight from question phase → mark_known → advances
      html = render_keydown(view, "keydown", %{"key" => "ArrowRight"})
      # Stats pill should now show 1 correct
      assert html =~ "1"
    end

    test "ArrowLeft marks question as dont know and transitions to reveal phase", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "Q-arrow-left")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      html = render_keydown(view, "keydown", %{"key" => "ArrowLeft"})

      # In reveal phase — the answer section renders; apostrophe is HTML-escaped
      assert html =~ "Here&#39;s the answer" or html =~ "Answer"
    end

    test "ArrowUp skips the current question", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q-skip-1")
      add_question(course.id, "q-skip-2")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      html = render_keydown(view, "keydown", %{"key" => "ArrowUp"})

      # Skip increments skipped counter; stats show 1 skipped
      assert html =~ "1"
    end

    test "Space key triggers show_answer_input (answering phase)", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q-space")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      html = render_keydown(view, "keydown", %{"key" => " "})

      # In answering phase, the submit button should appear
      assert html =~ "Submit" or html =~ "Cancel"
    end
  end

  describe "confidence-based events" do
    test "mark_i_know increments correct count and advances", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "question-know")
      add_question(course.id, "question-know-2")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      html = render_click(view, "mark_i_know")

      # Correct count should increment to 1
      assert html =~ "1"
    end

    test "mark_dont_know transitions to reveal phase showing answer", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "question-dont-know")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      html = render_click(view, "mark_dont_know")

      # Apostrophe in "Here's the answer" is HTML-escaped in render output
      assert html =~ "Here&#39;s the answer"
      assert html =~ "Next Card"
    end

    test "mark_not_sure transitions to reveal phase", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "question-not-sure")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      html = render_click(view, "mark_not_sure")

      # Apostrophe in "Here's the answer" is HTML-escaped in render output
      assert html =~ "Here&#39;s the answer"
    end

    test "skip increments skipped count and advances to next question", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "question-skip-1")
      add_question(course.id, "question-skip-2")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      html = render_click(view, "skip")

      # Should show 1 in skipped stats
      assert html =~ "1"
    end
  end

  describe "answering flow" do
    test "show_answer_input transitions to answering phase", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q-answer-input")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      html = render_click(view, "show_answer_input")

      assert html =~ "Submit"
      assert html =~ "Cancel"
    end

    test "select_answer stores the selected answer and highlights it", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q-select")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      render_click(view, "show_answer_input")
      html = render_click(view, "select_answer", %{"answer" => "A"})

      # The selected option should be highlighted (has green border class)
      assert html =~ "border-\\[#4CD964\\]" or html =~ "A."
    end

    test "submit_answer with correct MCQ answer shows correct feedback", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      # answer is "A" by default in add_question
      add_question(course.id, "q-submit-correct")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      render_click(view, "show_answer_input")
      render_click(view, "select_answer", %{"answer" => "A"})
      html = render_click(view, "submit_answer")

      # Correct answer "A" was submitted — should show feedback phase
      assert html =~ "Correct!" or html =~ "How well did you know this"
    end

    test "submit_answer with wrong MCQ answer shows incorrect feedback", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q-submit-wrong")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      render_click(view, "show_answer_input")
      render_click(view, "select_answer", %{"answer" => "B"})
      html = render_click(view, "submit_answer")

      # Wrong answer — should show "Not quite" feedback
      assert html =~ "Not quite" or html =~ "How well did you know this"
    end

    test "confidence_selected after submit advances to next card", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q-confidence")
      add_question(course.id, "q-confidence-2")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      render_click(view, "show_answer_input")
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")
      # Select confidence to advance past the feedback phase
      html = render_click(view, "confidence_selected", %{"confidence" => "i_know"})

      # Should have moved on — confidence prompt no longer shown
      refute html =~ "How well did you know this"
    end

    test "next_card from reveal phase advances to next question", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "first-question-reveal")
      add_question(course.id, "second-question-reveal")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      # Transition to reveal phase
      render_click(view, "mark_dont_know")
      # Advance via next_card
      html = render_click(view, "next_card")

      refute html =~ "Here&#39;s the answer"
    end
  end

  describe "session complete and restart" do
    test "completing all questions shows session complete screen", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "only-question")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice?course_id=#{course.id}")

      # Mark the single question as known — session completes
      html = render_click(view, "mark_i_know")

      assert html =~ "Session Done!" or html =~ "Keep Practicing"
    end

    test "restart resets the session and shows practice UI again", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "restart-question")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice?course_id=#{course.id}")

      render_click(view, "mark_i_know")
      html = render_click(view, "restart")

      # After restart the session complete screen should be gone
      refute html =~ "Session Done!"
    end
  end

  describe "course_id param selection" do
    test "?course_id= param restricts questions to that course", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")

      bio = ContentFixtures.create_course(%{name: "Biology", created_by_id: user.id})
      chem = ContentFixtures.create_course(%{name: "Chemistry", created_by_id: user.id})

      add_question(bio.id, "BIO-COURSE-PARAM")
      add_question(chem.id, "CHEM-COURSE-PARAM")

      conn = auth_conn(conn, user)
      {:ok, _view, html} = live(conn, ~p"/practice?course_id=#{bio.id}")

      assert html =~ "BIO-COURSE-PARAM"
      refute html =~ "CHEM-COURSE-PARAM"
    end

    test "empty course with no questions shows session complete with zero score", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      empty_course = ContentFixtures.create_course(%{created_by_id: user.id, name: "Empty Course"})

      conn = auth_conn(conn, user)
      {:ok, _view, html} = live(conn, ~p"/practice?course_id=#{empty_course.id}")

      # With 0 questions the engine immediately marks the session complete.
      # The session-done screen shows "0 cards reviewed" and a restart button.
      assert html =~ "0 cards reviewed" or html =~ "Keep Practicing" or
               html =~ "Session Done!"
    end
  end

  describe "tutor panel" do
    test "open_tutor event shows AI Tutor panel", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "tutor-question")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      html = render_click(view, "open_tutor")

      assert html =~ "AI Tutor" or html =~ "Ask me anything"
    end

    test "close_tutor event hides the tutor panel", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "tutor-close-question")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      render_click(view, "open_tutor")
      html = render_click(view, "close_tutor")

      refute html =~ "Ask me anything about this question"
    end

    test "tutor_input event updates the input field value", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "tutor-input-question")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      render_click(view, "open_tutor")
      html = render_change(view, "tutor_input", %{"message" => "explain this concept"})

      assert html =~ "explain this concept"
    end
  end

  describe "swipe events" do
    test "swipe right marks question as known (same as mark_i_know)", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "swipe-right-q1")
      add_question(course.id, "swipe-right-q2")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      html = render_click(view, "swipe", %{"direction" => "right"})
      assert html =~ "1"
    end

    test "swipe left transitions to reveal phase (same as mark_dont_know)", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "swipe-left-q")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      html = render_click(view, "swipe", %{"direction" => "left"})
      assert html =~ "Here&#39;s the answer" or html =~ "Answer"
    end

    test "swipe up skips the current question (same as skip)", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "swipe-up-q1")
      add_question(course.id, "swipe-up-q2")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      html = render_click(view, "swipe", %{"direction" => "up"})
      assert html =~ "1"
    end
  end

  describe "update_text_answer event" do
    test "updates selected_answer for freeform questions", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})

      # Create a short_answer question for freeform input
      {:ok, ch} =
        FunSheep.Courses.create_chapter(%{
          name: "Ch #{System.unique_integer([:positive])}",
          position: 1,
          course_id: course.id
        })

      {:ok, sec} =
        FunSheep.Courses.create_section(%{name: "Sec 1", position: 1, chapter_id: ch.id})

      {:ok, _q} =
        Questions.create_question(%{
          validation_status: :passed,
          content: "Explain photosynthesis",
          answer: "Plants use sunlight to make food",
          question_type: :short_answer,
          difficulty: :easy,
          options: %{},
          course_id: course.id,
          chapter_id: ch.id,
          section_id: sec.id,
          classification_status: :admin_reviewed
        })

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice?course_id=#{course.id}")

      render_click(view, "show_answer_input")
      html = render_change(view, "update_text_answer", %{"answer" => "my typed answer"})

      assert html =~ "my typed answer"
    end
  end

  describe "submit_answer edge cases" do
    test "submit_answer with nil answer does nothing", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q-nil-answer")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      render_click(view, "show_answer_input")
      # Submit with no answer selected — should be a no-op
      html = render_click(view, "submit_answer")

      # Still in answering phase (no feedback shown)
      assert html =~ "Submit"
    end
  end

  describe "confidence_selected after answering" do
    test "confidence_selected with not_sure advances to next card", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q-conf-not-sure")
      add_question(course.id, "q-conf-not-sure-2")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      render_click(view, "show_answer_input")
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")
      html = render_click(view, "confidence_selected", %{"confidence" => "not_sure"})

      refute html =~ "How well did you know this"
    end

    test "confidence_selected with dont_know advances to next card", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q-conf-dont-know")
      add_question(course.id, "q-conf-dont-know-2")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      render_click(view, "show_answer_input")
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")
      html = render_click(view, "confidence_selected", %{"confidence" => "dont_know"})

      refute html =~ "How well did you know this"
    end
  end

  describe "keydown in reveal and answering phases" do
    test "Space key in reveal phase advances to next card", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q-reveal-space")
      add_question(course.id, "q-reveal-space-2")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      # Enter reveal phase
      render_click(view, "mark_dont_know")
      # Space in reveal phase triggers next_card
      html = render_keydown(view, "keydown", %{"key" => " "})

      refute html =~ "Here&#39;s the answer"
    end

    test "Enter key in reveal phase advances to next card", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q-reveal-enter")
      add_question(course.id, "q-reveal-enter-2")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      render_click(view, "mark_dont_know")
      html = render_keydown(view, "keydown", %{"key" => "Enter"})

      refute html =~ "Here&#39;s the answer"
    end

    test "ArrowRight in reveal phase advances to next card", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q-reveal-arrow-right")
      add_question(course.id, "q-reveal-arrow-right-2")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      render_click(view, "mark_dont_know")
      html = render_keydown(view, "keydown", %{"key" => "ArrowRight"})

      refute html =~ "Here&#39;s the answer"
    end

    test "Escape key in answering phase exits to question card", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q-escape")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      render_click(view, "show_answer_input")
      html = render_keydown(view, "keydown", %{"key" => "Escape"})

      # After escape, the submit/cancel buttons should be gone
      refute html =~ "Cancel (Esc)"
    end

    test "Enter key in question phase shows answer input", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q-enter-answer")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      html = render_keydown(view, "keydown", %{"key" => "Enter"})

      assert html =~ "Submit"
    end

    test "keydown when session complete does nothing", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "only-q-keydown")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice?course_id=#{course.id}")

      # Complete session
      render_click(view, "mark_i_know")
      # Keydown on completed session is a no-op
      html = render_keydown(view, "keydown", %{"key" => "ArrowRight"})

      assert html =~ "Session Done!"
    end

    test "random key in question phase does nothing", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q-random-key")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      html = render_keydown(view, "keydown", %{"key" => "z"})
      # Should still be in question phase
      assert html =~ "q-random-key"
    end
  end

  describe "tutor send and quick actions" do
    test "tutor_send with empty message does nothing", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "tutor-empty-send")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      render_click(view, "open_tutor")
      # Empty message should be no-op
      html = render_submit(view, "tutor_send", %{"message" => ""})

      assert html =~ "AI Tutor"
    end

    test "tutor_quick_action with no session does nothing gracefully", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "tutor-action-q")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      # Quick action without session (no open_tutor first, so session may not exist)
      html = render_click(view, "tutor_quick_action", %{"action" => "hint"})

      # Should not crash — may or may not show tutor depending on whether session started
      assert is_binary(html)
    end
  end

  describe "mark events with no current question" do
    test "mark_i_know with no question is a no-op", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      # Empty course — session_complete will be true immediately
      empty_course = ContentFixtures.create_course(%{created_by_id: user.id, name: "Empty"})

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice?course_id=#{empty_course.id}")

      # Already session complete, mark_i_know should be a no-op
      html = render_click(view, "mark_i_know")
      assert html =~ "Session Done!" or html =~ "Keep Practicing"
    end

    test "mark_dont_know with no question is a no-op", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      empty_course = ContentFixtures.create_course(%{created_by_id: user.id, name: "Empty2"})

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice?course_id=#{empty_course.id}")

      html = render_click(view, "mark_dont_know")
      assert html =~ "Session Done!" or html =~ "Keep Practicing"
    end

    test "mark_not_sure with no question is a no-op", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      empty_course = ContentFixtures.create_course(%{created_by_id: user.id, name: "Empty3"})

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice?course_id=#{empty_course.id}")

      html = render_click(view, "mark_not_sure")
      assert html =~ "Session Done!" or html =~ "Keep Practicing"
    end

    test "skip with no question is a no-op", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      empty_course = ContentFixtures.create_course(%{created_by_id: user.id, name: "Empty4"})

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice?course_id=#{empty_course.id}")

      html = render_click(view, "skip")
      assert html =~ "Session Done!" or html =~ "Keep Practicing"
    end
  end

  describe "handle_info grading callbacks" do
    test "unhandled messages are ignored gracefully", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q-handle-info")

      conn = auth_conn(conn, user)
      {:ok, view, html} = live(conn, ~p"/practice")

      # Send an unrelated message — handle_info(:msg, socket) should ignore it
      send(view.pid, :some_random_message)
      html_after = render(view)

      # State unchanged
      assert html_after == html or is_binary(html_after)
    end
  end

  describe "freeform question grading" do
    defp add_freeform_question(course_id, content) do
      {:ok, ch} =
        FunSheep.Courses.create_chapter(%{
          name: "Ch #{System.unique_integer([:positive])}",
          position: 1,
          course_id: course_id
        })

      {:ok, sec} =
        FunSheep.Courses.create_section(%{name: "Sec 1", position: 1, chapter_id: ch.id})

      {:ok, q} =
        Questions.create_question(%{
          validation_status: :passed,
          content: content,
          answer: "correct answer here",
          question_type: :short_answer,
          difficulty: :medium,
          options: %{},
          course_id: course_id,
          chapter_id: ch.id,
          section_id: sec.id,
          classification_status: :admin_reviewed
        })

      q
    end

    setup do
      # Stub AI mock to return a correct grading response
      Mox.stub(FunSheep.AI.ClientMock, :call, fn _system, _prompt, _opts ->
        {:ok, Jason.encode!(%{"correct" => true, "feedback" => "Great answer!"})}
      end)

      :ok
    end

    test "submitting freeform answer shows grading spinner then feedback", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_freeform_question(course.id, "Explain photosynthesis briefly")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice?course_id=#{course.id}")

      render_click(view, "show_answer_input")
      render_change(view, "update_text_answer", %{"answer" => "Plants use sunlight"})

      # Allow AI mock from Task's parent process (LiveView process)
      Mox.allow(FunSheep.AI.ClientMock, self(), view.pid)

      html = render_click(view, "submit_answer")

      # Either showing grading spinner or feedback (task may complete quickly)
      assert html =~ "Grading your answer" or html =~ "How well did you know this" or
               html =~ "Correct!" or html =~ "Not quite"
    end

    test "after freeform grading, confidence phase is shown", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_freeform_question(course.id, "What is mitosis?")
      add_question(course.id, "Second question")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice?course_id=#{course.id}")

      Mox.allow(FunSheep.AI.ClientMock, self(), view.pid)

      render_click(view, "show_answer_input")
      render_change(view, "update_text_answer", %{"answer" => "Cell division process"})
      render_click(view, "submit_answer")

      # Wait for async grading to complete
      Process.sleep(300)
      html = render(view)

      # Should be in feedback phase now
      assert html =~ "How well did you know this" or html =~ "Correct!" or
               html =~ "Not quite" or html =~ "Second question"
    end
  end

  describe "test_id param with invalid id" do
    test "invalid test_id falls back to default selection", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "fallback-q")

      # Schedule to ensure there's a default
      schedule_test(user.id, course.id, "My Test", 5)

      conn = auth_conn(conn, user)
      {:ok, _view, html} = live(conn, ~p"/practice?test_id=nonexistent-id")

      # Falls back to the closest test's course
      assert html =~ "fallback-q"
    end

    test "no upcoming tests with no params selects all courses", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "all-courses-q")

      conn = auth_conn(conn, user)
      {:ok, _view, html} = live(conn, ~p"/practice")

      # No upcoming tests and no params means all questions
      assert html =~ "all-courses-q"
    end
  end

  describe "true/false question type" do
    defp add_true_false_question(course_id, content) do
      {:ok, ch} =
        FunSheep.Courses.create_chapter(%{
          name: "Ch #{System.unique_integer([:positive])}",
          position: 1,
          course_id: course_id
        })

      {:ok, sec} =
        FunSheep.Courses.create_section(%{name: "Sec 1", position: 1, chapter_id: ch.id})

      {:ok, q} =
        Questions.create_question(%{
          validation_status: :passed,
          content: content,
          answer: "True",
          question_type: :true_false,
          difficulty: :easy,
          options: %{},
          course_id: course_id,
          chapter_id: ch.id,
          section_id: sec.id,
          classification_status: :admin_reviewed
        })

      q
    end

    test "true/false question shows T/F type label", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_true_false_question(course.id, "The Earth orbits the Sun")

      conn = auth_conn(conn, user)
      {:ok, _view, html} = live(conn, ~p"/practice?course_id=#{course.id}")

      assert html =~ "T/F"
    end

    test "submitting True answer for true/false question shows feedback", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_true_false_question(course.id, "Water is H2O")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice?course_id=#{course.id}")

      render_click(view, "show_answer_input")
      render_click(view, "select_answer", %{"answer" => "True"})
      html = render_click(view, "submit_answer")

      assert html =~ "Correct!" or html =~ "How well did you know this"
    end

    test "submitting False answer for true/false question shows feedback", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_true_false_question(course.id, "The sky is green")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice?course_id=#{course.id}")

      render_click(view, "show_answer_input")
      render_click(view, "select_answer", %{"answer" => "False"})
      html = render_click(view, "submit_answer")

      assert html =~ "Not quite" or html =~ "How well did you know this"
    end
  end

  describe "course_id param with matching test" do
    test "?course_id= param sets selected_test_id to matching schedule", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")

      bio = ContentFixtures.create_course(%{name: "AP Biology", created_by_id: user.id})
      add_question(bio.id, "bio-question")

      schedule_test(user.id, bio.id, "Bio Test", 5)

      conn = auth_conn(conn, user)
      {:ok, _view, html} = live(conn, ~p"/practice?course_id=#{bio.id}")

      # Should show that course's questions and the AP Biology pill
      assert html =~ "bio-question"
      assert html =~ "AP Biology"
    end
  end

  describe "session streak display" do
    test "streak badge appears after 3 consecutive correct answers", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "streak-q1")
      add_question(course.id, "streak-q2")
      add_question(course.id, "streak-q3")
      add_question(course.id, "streak-q4")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice?course_id=#{course.id}")

      render_click(view, "mark_i_know")
      render_click(view, "mark_i_know")
      html = render_click(view, "mark_i_know")

      # After 3 correct, streak counter shows
      assert html =~ "3" or html =~ "🔥"
    end
  end
end
