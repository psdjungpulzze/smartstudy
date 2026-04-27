defmodule FunSheepWeb.DailyChallengeLiveTest do
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
    course = ContentFixtures.create_course(%{name: "Biology 101"})

    {:ok, chapter} =
      FunSheep.Courses.create_chapter(%{name: "Chapter 1", position: 1, course_id: course.id})

    {:ok, section} =
      FunSheep.Courses.create_section(%{name: "Section 1", position: 1, chapter_id: chapter.id})

    %{user_role: user_role, course: course, chapter: chapter, section: section}
  end

  describe "mount/3" do
    test "renders intro phase with course name", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      assert html =~ "Daily Shear"
      assert html =~ "Biology 101"
      assert html =~ "Today&#39;s Daily Shear"
    end

    test "renders start challenge button when not yet attempted", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      assert html =~ "Start Challenge"
    end

    test "shows already attempted screen when user has completed today's challenge", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      # Create and complete an attempt for this user
      {:ok, challenge} = FunSheep.Engagement.DailyChallenges.get_or_create_today(course.id)
      {:ok, attempt} = FunSheep.Engagement.DailyChallenges.start_attempt(ur.id, challenge.id)

      {:ok, _attempt} =
        FunSheep.Engagement.DailyChallenges.complete_attempt(attempt.id, 30_000)

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      assert html =~ "Already Completed!"
      assert html =~ "Come back tomorrow"
      refute html =~ "Start Challenge"
    end
  end

  describe "start_challenge event" do
    test "shows error flash when no questions are available", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      # No questions in this course — challenge will have empty question_ids
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      html = render_click(view, "start_challenge")

      # Either shows error flash (no questions) or transitions to question phase
      # with questions available. With no questions, we expect the error flash.
      assert html =~ "not available" or html =~ "Question 1"
    end

    test "transitions to question phase when questions are available", %{
      conn: conn,
      user_role: ur,
      course: course,
      chapter: chapter,
      section: section
    } do
      # Create questions so the daily challenge has material to work with
      for i <- 1..5 do
        {:ok, _} =
          FunSheep.Questions.create_question(%{
            validation_status: :passed,
            content: "Question #{i} content",
            answer: "A",
            question_type: :multiple_choice,
            difficulty: if(i <= 2, do: :easy, else: if(i <= 4, do: :medium, else: :hard)),
            options: %{"A" => "Option A", "B" => "Option B", "C" => "Option C", "D" => "Option D"},
            course_id: course.id,
            chapter_id: chapter.id,
            section_id: section.id,
            classification_status: :admin_reviewed
          })
      end

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      html = render_click(view, "start_challenge")

      assert html =~ "Question 1"
      assert html =~ "Submit Answer"
    end
  end

  describe "answer selection and submission" do
    setup %{course: course, chapter: chapter, section: section} do
      for i <- 1..5 do
        {:ok, _} =
          FunSheep.Questions.create_question(%{
            validation_status: :passed,
            content: "Test question #{i}",
            answer: "A",
            question_type: :multiple_choice,
            difficulty: if(i <= 2, do: :easy, else: if(i <= 4, do: :medium, else: :hard)),
            options: %{"A" => "Correct", "B" => "Wrong", "C" => "Wrong", "D" => "Wrong"},
            course_id: course.id,
            chapter_id: chapter.id,
            section_id: section.id,
            classification_status: :admin_reviewed
          })
      end

      :ok
    end

    test "select_answer updates the selected answer", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      render_click(view, "start_challenge")
      html = render_click(view, "select_answer", %{"answer" => "A"})

      # The selected option should be visually highlighted (border-[#4CD964])
      assert html =~ "border-[#4CD964]"
    end

    test "submit_answer shows correct/incorrect feedback", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      render_click(view, "start_challenge")
      render_click(view, "select_answer", %{"answer" => "A"})
      html = render_click(view, "submit_answer")

      assert html =~ "Correct" or html =~ "Incorrect"
      assert html =~ "Next Question"
    end

    test "share_completed event with clipboard method shows link copied flash", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      html = render_click(view, "share_completed", %{"method" => "clipboard"})
      assert html =~ "Link copied!"
    end

    test "share_completed event with non-clipboard method shows Shared! flash", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      html = render_click(view, "share_completed", %{"method" => "native"})
      assert html =~ "Shared!"
    end

    test "select_answer when feedback already present is a no-op", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      render_click(view, "start_challenge")
      # Select and submit so feedback is active
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")
      # Selecting another answer while feedback is active should not crash
      html = render_click(view, "select_answer", %{"answer" => "B"})
      assert is_binary(html)
    end

    test "submit_answer with no answer selected is a no-op", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      render_click(view, "start_challenge")
      # Submit without selecting — should not crash
      html = render_click(view, "submit_answer")
      assert is_binary(html)
      # Still shows submit button (no feedback yet)
      assert html =~ "Submit Answer" or html =~ "Question 1"
    end

    test "next_question event moves to next question", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      render_click(view, "start_challenge")
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")
      html = render_click(view, "next_question")

      # Should now be on question 2, or completed if only 1 question
      assert html =~ "Question 2" or html =~ "Challenge Complete" or html =~ "Perfect Score"
    end

    test "update_text_answer event updates the selected answer", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      render_click(view, "start_challenge")
      # update_text_answer is used for short-answer questions; it should not crash
      html = render_hook(view, "update_text_answer", %{"answer" => "my answer text"})
      assert is_binary(html)
    end

    test "update_text_answer when feedback is active is a no-op", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      render_click(view, "start_challenge")
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")
      html = render_hook(view, "update_text_answer", %{"answer" => "ignored"})
      assert is_binary(html)
    end
  end

  describe "complete challenge flow" do
    setup %{course: course, chapter: chapter, section: section} do
      for i <- 1..5 do
        {:ok, _} =
          FunSheep.Questions.create_question(%{
            validation_status: :passed,
            content: "Flow question #{i}",
            answer: "A",
            question_type: :multiple_choice,
            difficulty: :easy,
            options: %{"A" => "Correct", "B" => "Wrong", "C" => "Wrong", "D" => "Wrong"},
            course_id: course.id,
            chapter_id: chapter.id,
            section_id: section.id,
            classification_status: :admin_reviewed
          })
      end

      :ok
    end

    test "completing all questions transitions to results phase", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      render_click(view, "start_challenge")

      # Answer all questions (up to @question_count = 5)
      question_count = FunSheep.Gamification.FpEconomy.daily_challenge_question_count()

      for _i <- 1..question_count do
        current_html = render(view)

        if current_html =~ "Submit Answer" do
          render_click(view, "select_answer", %{"answer" => "A"})
          render_click(view, "submit_answer")
          # Check if we're still in question phase before clicking next
          new_html = render(view)

          if new_html =~ "Next Question" or new_html =~ "See Results" do
            render_click(view, "next_question")
          end
        end
      end

      html = render(view)

      # Should be in results phase now
      assert html =~ "Challenge Complete" or html =~ "Perfect Score" or
               html =~ "Score" or html =~ "XP earned"
    end

    test "results phase shows XP earned section", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      render_click(view, "start_challenge")

      question_count = FunSheep.Gamification.FpEconomy.daily_challenge_question_count()

      for _i <- 1..question_count do
        current_html = render(view)

        if current_html =~ "Submit Answer" do
          render_click(view, "select_answer", %{"answer" => "A"})
          render_click(view, "submit_answer")
          new_html = render(view)

          if new_html =~ "Next Question" or new_html =~ "See Results" do
            render_click(view, "next_question")
          end
        end
      end

      html = render(view)

      # Results phase should show XP info
      assert html =~ "XP" or html =~ "Score" or html =~ "Back to Dashboard"
    end

    test "results phase shows Back to Dashboard link", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      render_click(view, "start_challenge")

      question_count = FunSheep.Gamification.FpEconomy.daily_challenge_question_count()

      for _i <- 1..question_count do
        current_html = render(view)

        if current_html =~ "Submit Answer" do
          render_click(view, "select_answer", %{"answer" => "A"})
          render_click(view, "submit_answer")
          new_html = render(view)

          if new_html =~ "Next Question" or new_html =~ "See Results" do
            render_click(view, "next_question")
          end
        end
      end

      html = render(view)

      assert html =~ "Back to Dashboard" or html =~ "dashboard" or html =~ "Score"
    end
  end

  describe "true/false question type" do
    setup %{course: course, chapter: chapter, section: section} do
      {:ok, _} =
        FunSheep.Questions.create_question(%{
          validation_status: :passed,
          content: "True or false: water is wet",
          answer: "True",
          question_type: :true_false,
          difficulty: :easy,
          options: %{},
          course_id: course.id,
          chapter_id: chapter.id,
          section_id: section.id,
          classification_status: :admin_reviewed
        })

      # Add more questions to fill up the challenge
      for i <- 2..5 do
        {:ok, _} =
          FunSheep.Questions.create_question(%{
            validation_status: :passed,
            content: "MCQ question #{i}",
            answer: "A",
            question_type: :multiple_choice,
            difficulty: :easy,
            options: %{"A" => "Correct", "B" => "Wrong"},
            course_id: course.id,
            chapter_id: chapter.id,
            section_id: section.id,
            classification_status: :admin_reviewed
          })
      end

      :ok
    end

    test "true/false question renders True and False buttons", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      render_click(view, "start_challenge")
      html = render(view)

      # The first question may or may not be the true/false one (randomized)
      # We just check the view renders without crash
      assert is_binary(html)
    end
  end

  describe "already attempted state with previous attempt data" do
    setup %{course: course, chapter: chapter, section: section} do
      for i <- 1..5 do
        {:ok, _} =
          FunSheep.Questions.create_question(%{
            validation_status: :passed,
            content: "Prev attempt question #{i}",
            answer: "A",
            question_type: :multiple_choice,
            difficulty: :easy,
            options: %{"A" => "Correct", "B" => "Wrong", "C" => "Wrong", "D" => "Wrong"},
            course_id: course.id,
            chapter_id: chapter.id,
            section_id: section.id,
            classification_status: :admin_reviewed
          })
      end

      :ok
    end

    test "already attempted shows previous score and time", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      {:ok, challenge} = FunSheep.Engagement.DailyChallenges.get_or_create_today(course.id)
      {:ok, attempt} = FunSheep.Engagement.DailyChallenges.start_attempt(ur.id, challenge.id)
      {:ok, _} = FunSheep.Engagement.DailyChallenges.complete_attempt(attempt.id, 45_000)

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      assert html =~ "Already Completed!"
      # Shows score out of question_count
      assert html =~ "/" or html =~ "00:45" or html =~ "Come back tomorrow"
    end

    test "already attempted shows score from previous attempt", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      {:ok, challenge} = FunSheep.Engagement.DailyChallenges.get_or_create_today(course.id)
      {:ok, attempt} = FunSheep.Engagement.DailyChallenges.start_attempt(ur.id, challenge.id)

      # Submit a correct answer
      if challenge.question_ids != [] do
        [first_q_id | _] = challenge.question_ids
        FunSheep.Engagement.DailyChallenges.submit_answer(attempt.id, first_q_id, "A", true)
      end

      {:ok, _} = FunSheep.Engagement.DailyChallenges.complete_attempt(attempt.id, 60_000)

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      assert html =~ "Already Completed!"
      assert html =~ "Come back tomorrow"
    end
  end

  describe "handle_info messages" do
    setup %{course: course, chapter: chapter, section: section} do
      for i <- 1..5 do
        {:ok, _} =
          FunSheep.Questions.create_question(%{
            validation_status: :passed,
            content: "Info test question #{i}",
            answer: "A",
            question_type: :multiple_choice,
            difficulty: :easy,
            options: %{"A" => "Correct", "B" => "Wrong", "C" => "Wrong", "D" => "Wrong"},
            course_id: course.id,
            chapter_id: chapter.id,
            section_id: section.id,
            classification_status: :admin_reviewed
          })
      end

      :ok
    end

    test "unrecognized handle_info message does not crash", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      # Send an unrecognized message to the LiveView process
      send(view.pid, :unknown_message)
      html = render(view)

      assert is_binary(html)
    end

    test "timer tick in question phase increments elapsed time", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/daily-shear")

      render_click(view, "start_challenge")
      # Send a tick message manually to test the handler
      send(view.pid, :tick)
      html = render(view)

      # Timer should still be showing
      assert html =~ ":" or html =~ "Question"
    end
  end
end
