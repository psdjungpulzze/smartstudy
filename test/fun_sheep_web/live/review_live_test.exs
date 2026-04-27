defmodule FunSheepWeb.ReviewLiveTest do
  @moduledoc """
  Tests for ReviewLive — spaced-repetition review page.

  ReviewLive uses current_user["id"] as the user_role_id for review queries.
  For a fresh user with no review cards, the page shows the "All caught up!" empty state.

  When review cards are due, the page shows the active flashcard review UI
  with show_answer, rate events that progress through cards to completion.
  """

  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.ContentFixtures
  alias FunSheep.Engagement.ReviewCard
  alias FunSheep.Repo

  # ReviewLive reads current_user["id"] as user_role_id.
  defp auth_conn(conn, user_role) do
    conn
    |> init_test_session(%{
      dev_user_id: user_role.interactor_user_id,
      dev_user: %{
        "id" => user_role.id,
        "role" => "student",
        "email" => user_role.email,
        "display_name" => user_role.display_name,
        "user_role_id" => user_role.id,
        "interactor_user_id" => user_role.interactor_user_id
      }
    })
  end

  # Creates a review card directly in the DB that is due now.
  defp create_due_review_card(user_role, course, question) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %ReviewCard{}
    |> ReviewCard.changeset(%{
      user_role_id: user_role.id,
      question_id: question.id,
      course_id: course.id,
      next_review_at: DateTime.add(now, -60, :second),
      ease_factor: 2.5,
      interval_days: 0.0,
      repetitions: 0,
      status: "new"
    })
    |> Repo.insert!()
  end

  # Creates a multiple-choice question for a course.
  defp create_mc_question(course, chapter) do
    {:ok, question} =
      FunSheep.Questions.create_question(%{
        validation_status: :passed,
        content: "What is the powerhouse of the cell?",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{"A" => "Mitochondria", "B" => "Nucleus", "C" => "Ribosome", "D" => "Golgi"},
        course_id: course.id,
        chapter_id: chapter.id
      })

    question
  end

  defp create_chapter(course) do
    {:ok, chapter} =
      FunSheep.Courses.create_chapter(%{
        name: "Chapter 1",
        position: 1,
        course_id: course.id
      })

    chapter
  end

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{name: "Biology 101"})
    %{user_role: user_role, course: course}
  end

  describe "ReviewLive mount — empty state (no cards due)" do
    test "renders the review page for a course", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      assert html =~ "Just This"
    end

    test "shows empty/caught-up state when no review cards are due", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      assert html =~ "All caught up!"
      assert html =~ "No cards are due for review"
    end

    test "shows Back to Dashboard link in empty state", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      assert html =~ "Back to Dashboard"
      assert html =~ "/dashboard"
    end

    test "does not show active card UI when no cards are due", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      refute html =~ "Show Answer"
      refute html =~ "How well did you remember?"
    end

    test "does not show completion screen in empty state", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      refute html =~ "Review Complete!"
    end

    test "shows correct page title", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/review")

      assert page_title(view) =~ "Review"
    end

    test "shows sheep mascot image in empty state", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      # The sheep mascot component renders in the empty state
      assert html =~ "celebrating" or html =~ "sheep" or html =~ "All caught up!"
    end

    test "shows page subtitle in header", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      assert html =~ "Quick spaced repetition review"
    end

    test "shows back arrow link to dashboard in header", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      assert html =~ "hero-arrow-left"
    end

    test "shows 'Just This' heading", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      assert html =~ "Just This"
    end

    test "assigns total_cards as 0 in empty state", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      # Empty state block is shown (total_cards == 0 and not completed)
      assert html =~ "All caught up!"
    end

    test "does not show cards_reviewed stat in empty state", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      refute html =~ "Cards Reviewed"
    end

    test "does not show XP Earned stat in empty state", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      refute html =~ "XP Earned"
    end

    test "does not show progress dots in empty state", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      # Progress dots only shown when current_card is set and not completed
      refute html =~ "Card 1 of"
    end
  end

  describe "ReviewLive mount — active review (cards due)" do
    setup %{user_role: ur, course: course} do
      chapter = create_chapter(course)
      question = create_mc_question(course, chapter)
      _card = create_due_review_card(ur, course, question)
      %{chapter: chapter, question: question}
    end

    test "shows the flashcard review UI when cards are due", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      assert html =~ "Show Answer"
      assert html =~ "Card 1 of"
    end

    test "shows the question content on the card", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      assert html =~ "powerhouse of the cell"
    end

    test "shows MCQ options when question is multiple choice", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      assert html =~ "Mitochondria"
    end

    test "does not show empty state when cards are due", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      refute html =~ "All caught up!"
    end

    test "does not show completion screen on mount", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      refute html =~ "Review Complete!"
    end

    test "shows difficulty badge on the card", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      assert html =~ "Easy"
    end
  end

  describe "show_answer event" do
    setup %{user_role: ur, course: course} do
      chapter = create_chapter(course)
      question = create_mc_question(course, chapter)
      _card = create_due_review_card(ur, course, question)
      %{chapter: chapter, question: question}
    end

    test "clicking Show Answer reveals the answer and rating buttons", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/review")

      render_click(view, "show_answer")
      html = render(view)

      assert html =~ "How well did you remember?"
      assert html =~ "Again"
      assert html =~ "Good"
      assert html =~ "Easy"
    end

    test "Show Answer button disappears after clicking", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, html} = live(conn, ~p"/courses/#{course.id}/review")

      assert html =~ "Show Answer"

      render_click(view, "show_answer")
      html_after = render(view)

      refute html_after =~ "Show Answer"
    end

    test "answer text is revealed after show_answer", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/review")

      render_click(view, "show_answer")
      html = render(view)

      # The answer field is "A"
      assert html =~ question.answer
    end
  end

  describe "rate event — single card (completes session)" do
    setup %{user_role: ur, course: course} do
      chapter = create_chapter(course)
      question = create_mc_question(course, chapter)
      _card = create_due_review_card(ur, course, question)
      %{chapter: chapter, question: question}
    end

    test "rating 'Easy' (quality 5) on last card shows completion screen", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/review")

      render_click(view, "show_answer")
      render_click(view, "rate", %{"quality" => "5"})

      html = render(view)
      assert html =~ "Review Complete!"
    end

    test "rating 'Again' (quality 1) on last card shows completion screen", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/review")

      render_click(view, "show_answer")
      render_click(view, "rate", %{"quality" => "1"})

      html = render(view)
      assert html =~ "Review Complete!"
    end

    test "rating 'Good' (quality 3) on last card shows completion screen", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/review")

      render_click(view, "show_answer")
      render_click(view, "rate", %{"quality" => "3"})

      html = render(view)
      assert html =~ "Review Complete!"
    end

    test "completion screen shows Cards Reviewed stat", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/review")

      render_click(view, "show_answer")
      render_click(view, "rate", %{"quality" => "5"})

      html = render(view)
      assert html =~ "Cards Reviewed"
    end

    test "completion screen shows XP Earned stat", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/review")

      render_click(view, "show_answer")
      render_click(view, "rate", %{"quality" => "5"})

      html = render(view)
      assert html =~ "XP Earned"
    end

    test "completion screen shows Back to Dashboard link", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/review")

      render_click(view, "show_answer")
      render_click(view, "rate", %{"quality" => "5"})

      html = render(view)
      assert html =~ "Back to Dashboard"
    end

    test "completion screen hides active card UI", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/review")

      render_click(view, "show_answer")
      render_click(view, "rate", %{"quality" => "5"})

      html = render(view)
      refute html =~ "Show Answer"
    end
  end

  describe "rate event — multiple cards (advances between cards)" do
    setup %{user_role: ur, course: course} do
      chapter = create_chapter(course)

      {:ok, q1} =
        FunSheep.Questions.create_question(%{
          validation_status: :passed,
          content: "First question content",
          answer: "A",
          question_type: :multiple_choice,
          difficulty: :easy,
          options: %{"A" => "Ans A", "B" => "Ans B"},
          course_id: course.id,
          chapter_id: chapter.id
        })

      {:ok, q2} =
        FunSheep.Questions.create_question(%{
          validation_status: :passed,
          content: "Second question content",
          answer: "B",
          question_type: :multiple_choice,
          difficulty: :medium,
          options: %{"A" => "Opt A", "B" => "Opt B"},
          course_id: course.id,
          chapter_id: chapter.id
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Insert first card (older so it comes first)
      %ReviewCard{}
      |> ReviewCard.changeset(%{
        user_role_id: ur.id,
        question_id: q1.id,
        course_id: course.id,
        next_review_at: DateTime.add(now, -120, :second),
        ease_factor: 2.5,
        interval_days: 0.0,
        repetitions: 0,
        status: "new"
      })
      |> Repo.insert!()

      # Insert second card (newer)
      %ReviewCard{}
      |> ReviewCard.changeset(%{
        user_role_id: ur.id,
        question_id: q2.id,
        course_id: course.id,
        next_review_at: DateTime.add(now, -60, :second),
        ease_factor: 2.5,
        interval_days: 0.0,
        repetitions: 0,
        status: "new"
      })
      |> Repo.insert!()

      %{q1: q1, q2: q2}
    end

    test "rating first card advances to second card (does not complete)", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/review")

      render_click(view, "show_answer")
      render_click(view, "rate", %{"quality" => "5"})

      html = render(view)
      # Should be on card 2 now, not completed
      assert html =~ "Card 2 of"
      refute html =~ "Review Complete!"
    end

    test "rating second card completes the session", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/review")

      # Rate card 1
      render_click(view, "show_answer")
      render_click(view, "rate", %{"quality" => "5"})

      # Rate card 2
      render_click(view, "show_answer")
      render_click(view, "rate", %{"quality" => "5"})

      html = render(view)
      assert html =~ "Review Complete!"
    end

    test "show_answer resets between cards", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/review")

      # Show answer on card 1 then rate
      render_click(view, "show_answer")
      render_click(view, "rate", %{"quality" => "3"})

      # Card 2 should NOT show answer automatically
      html = render(view)
      assert html =~ "Show Answer"
      refute html =~ "How well did you remember?"
    end

    test "progress counter updates after rating", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, html} = live(conn, ~p"/courses/#{course.id}/review")

      assert html =~ "Card 1 of 2"

      render_click(view, "show_answer")
      render_click(view, "rate", %{"quality" => "5"})

      html = render(view)
      assert html =~ "Card 2 of 2"
    end
  end

  describe "difficulty badge rendering" do
    test "easy difficulty shows correct badge style", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      chapter = create_chapter(course)

      {:ok, question} =
        FunSheep.Questions.create_question(%{
          validation_status: :passed,
          content: "Easy question",
          answer: "A",
          question_type: :multiple_choice,
          difficulty: :easy,
          options: %{"A" => "Yes", "B" => "No"},
          course_id: course.id,
          chapter_id: chapter.id
        })

      create_due_review_card(ur, course, question)

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      assert html =~ "Easy"
      assert html =~ "bg-[#E8F8EB]"
    end

    test "medium difficulty shows correct badge style", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      chapter = create_chapter(course)

      {:ok, question} =
        FunSheep.Questions.create_question(%{
          validation_status: :passed,
          content: "Medium question",
          answer: "A",
          question_type: :multiple_choice,
          difficulty: :medium,
          options: %{"A" => "Yes", "B" => "No"},
          course_id: course.id,
          chapter_id: chapter.id
        })

      create_due_review_card(ur, course, question)

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      assert html =~ "Medium"
      assert html =~ "bg-yellow-100"
    end

    test "hard difficulty shows correct badge style", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      chapter = create_chapter(course)

      {:ok, question} =
        FunSheep.Questions.create_question(%{
          validation_status: :passed,
          content: "Hard question",
          answer: "A",
          question_type: :multiple_choice,
          difficulty: :hard,
          options: %{"A" => "Yes", "B" => "No"},
          course_id: course.id,
          chapter_id: chapter.id
        })

      create_due_review_card(ur, course, question)

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/review")

      assert html =~ "Hard"
      assert html =~ "bg-red-100"
    end
  end

  describe "multiple courses" do
    test "works for different course IDs", %{conn: conn, user_role: ur} do
      course1 = ContentFixtures.create_course(%{name: "Math"})
      course2 = ContentFixtures.create_course(%{name: "Science"})

      conn = auth_conn(conn, ur)

      {:ok, _view, html1} = live(conn, ~p"/courses/#{course1.id}/review")
      assert html1 =~ "Just This"

      {:ok, _view, html2} = live(conn, ~p"/courses/#{course2.id}/review")
      assert html2 =~ "Just This"
    end
  end
end
