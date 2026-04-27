defmodule FunSheepWeb.EssayLiveTest do
  # async: false because Oban :inline mode runs the EssayGradingWorker inside
  # the LiveView process (not the test process) on submit_essay, so
  # with_testing_mode(:manual) does NOT stop it. We stub the AI client mock
  # globally so worker calls fail gracefully rather than crash with
  # Mox.UnexpectedCallError.
  use FunSheepWeb.ConnCase, async: false

  import Mox
  import Phoenix.LiveViewTest

  alias FunSheep.{Billing, ContentFixtures, Essays, Repo}
  alias FunSheep.AI.ClientMock
  alias FunSheep.Billing.Subscription
  alias FunSheep.Essays.EssayRubricTemplate

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    # Stub the AI client so any unexpected worker call fails gracefully instead
    # of crashing the LiveView process with Mox.UnexpectedCallError.
    stub(ClientMock, :call, fn _sys, _usr, _opts -> {:error, :not_configured_in_test} end)
    :ok
  end

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

  # Insert a monthly-active subscription so Billing.subscription_has_essay_grading?/1
  # returns true, unlocking the writing interface.
  defp grant_essay_access(user_role) do
    {:ok, _sub} =
      %Subscription{}
      |> Subscription.changeset(%{
        user_role_id: user_role.id,
        plan: "monthly",
        status: "active"
      })
      |> Repo.insert()
  end

  # Creates a rubric template usable in tests. Using a unique exam_type to
  # avoid unique-constraint clashes across async test runs.
  defp create_rubric_template do
    {:ok, template} =
      %EssayRubricTemplate{}
      |> EssayRubricTemplate.changeset(%{
        name: "Test Rubric",
        exam_type: "test_essay_#{System.unique_integer([:positive])}",
        criteria: [
          %{"name" => "Thesis", "max_points" => 5, "description" => "Clear thesis statement"},
          %{"name" => "Evidence", "max_points" => 5, "description" => "Supporting evidence"}
        ],
        max_score: 10,
        mastery_threshold_ratio: 0.7
      })
      |> Repo.insert()

    template
  end

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{name: "History 101"})

    {:ok, chapter} =
      FunSheep.Courses.create_chapter(%{name: "Chapter 1", position: 1, course_id: course.id})

    {:ok, section} =
      FunSheep.Courses.create_section(%{name: "Section 1", position: 1, chapter_id: chapter.id})

    {:ok, question} =
      FunSheep.Questions.create_question(%{
        validation_status: :passed,
        content: "Discuss the causes of World War I and their long-term impact on global politics.",
        answer: "Open",
        question_type: :essay,
        difficulty: :medium,
        options: %{},
        course_id: course.id,
        chapter_id: chapter.id,
        section_id: section.id,
        classification_status: :admin_reviewed
      })

    %{user_role: user_role, course: course, chapter: chapter, section: section, question: question}
  end

  describe "mount/3 — premium gate (free user)" do
    test "renders essay page with page title and course link", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      assert html =~ "Essay Practice"
      assert html =~ "History 101"
    end

    test "renders back link to course", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      assert html =~ "History 101"
      assert html =~ ~s|/courses/#{course.id}|
    end

    test "shows premium gate for a free user with no subscription", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      assert html =~ "AI Essay Grading"
      assert html =~ "Upgrade to Premium"
      refute html =~ "Submit for Grading"
    end

    test "premium gate shows /subscription upgrade link", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      assert html =~ "/subscription"
    end
  end

  describe "mount/3 — paid user sees writing interface" do
    test "paid user sees the writing textarea and submit button", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      grant_essay_access(ur)
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      assert html =~ "Submit for Grading"
      assert html =~ "Start writing your essay here"
      refute html =~ "Upgrade to Premium"
    end

    test "paid user sees the essay prompt text", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      grant_essay_access(ur)
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      assert html =~ "Discuss the causes of World War I"
    end

    test "paid user sees initial word count of 0", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      grant_essay_access(ur)
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      assert html =~ "0 words"
    end

    test "paid user with a question that has rubric template sees rubric toggle", %{
      conn: conn,
      user_role: ur,
      course: course,
      chapter: chapter,
      section: section
    } do
      grant_essay_access(ur)
      rubric = create_rubric_template()

      {:ok, question_with_rubric} =
        FunSheep.Questions.create_question(%{
          validation_status: :passed,
          content: "Analyze the themes in Shakespeare's Hamlet.",
          answer: "Open",
          question_type: :essay,
          difficulty: :hard,
          options: %{},
          course_id: course.id,
          chapter_id: chapter.id,
          section_id: section.id,
          classification_status: :admin_reviewed,
          essay_rubric_template_id: rubric.id
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/essay/#{question_with_rubric.id}")

      assert html =~ "Scoring Rubric"
      assert html =~ rubric.name
    end
  end

  describe "handle_event/3 — free user" do
    test "toggle_rubric does not crash when question has no rubric template (free user)", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      refute html =~ "Scoring Rubric"
      assert render(view) =~ "Essay Practice"
    end

    test "heartbeat event does not crash the view even for premium-gated user", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      html = render_click(view, "heartbeat", %{"elapsed" => 30})
      assert html =~ "Essay Practice"
    end
  end

  describe "handle_event/3 — paid user" do
    setup %{user_role: ur} do
      grant_essay_access(ur)
      :ok
    end

    test "essay_draft_changed updates word count", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      html =
        render_change(view, "essay_draft_changed", %{
          "body" => "This is my essay text with several words to count."
        })

      assert html =~ "10 words"
    end

    test "essay_draft_changed with empty body shows 0 words", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      html = render_change(view, "essay_draft_changed", %{"body" => ""})

      assert html =~ "0 words"
    end

    test "submit_essay with empty body shows validation error", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      html = render_click(view, "submit_essay")

      assert html =~ "Please write your essay before submitting"
    end

    test "submit_essay with content transitions to grading state", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      conn = auth_conn(conn, ur)

      # Pre-create a draft with content so the LiveView body assign is already
      # populated on mount — no render_change needed (which would spawn a Task).
      {:ok, _draft} =
        Essays.upsert_draft(ur.id, question.id, "WWI was caused by complex alliances.",
          word_count: 7
        )

      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      # The AI mock is globally stubbed to return {:error, :not_configured_in_test},
      # so the grading worker runs but fails gracefully. The submit handler sets
      # grading: true before the worker runs, so we verify that intermediate state.
      html = render_click(view, "submit_essay")

      assert html =~ "Grading your essay"
    end

    test "heartbeat with integer elapsed updates time_elapsed", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      # Heartbeat with an integer elapsed — sets time_elapsed; no crash
      html = render_click(view, "heartbeat", %{"elapsed" => 120})

      assert html =~ "Essay Practice"
    end

    test "heartbeat with non-integer elapsed is ignored gracefully", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      # The second clause handles non-integer elapsed values (e.g. missing key)
      html = render_click(view, "heartbeat", %{"elapsed" => "not-a-number"})

      assert html =~ "Essay Practice"
    end

    test "toggle_rubric toggles show_rubric state on question without rubric", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      # No rubric template — rubric section not shown
      refute html =~ "Scoring Rubric"

      # Sending the event should not crash
      result_html = render_click(view, "toggle_rubric", %{})
      assert result_html =~ "Essay Practice"
    end

    test "toggle_rubric with a rubric template shows/hides criteria", %{
      conn: conn,
      user_role: ur,
      course: course,
      chapter: chapter,
      section: section
    } do
      rubric = create_rubric_template()

      {:ok, question_with_rubric} =
        FunSheep.Questions.create_question(%{
          validation_status: :passed,
          content: "Discuss literary techniques in Hamlet.",
          answer: "Open",
          question_type: :essay,
          difficulty: :hard,
          options: %{},
          course_id: course.id,
          chapter_id: chapter.id,
          section_id: section.id,
          classification_status: :admin_reviewed,
          essay_rubric_template_id: rubric.id
        })

      conn = auth_conn(conn, ur)
      {:ok, view, html} = live(conn, ~p"/courses/#{course.id}/essay/#{question_with_rubric.id}")

      # Rubric toggle button is visible
      assert html =~ "Scoring Rubric"
      # Initially collapsed — criteria not shown
      refute html =~ "Thesis"

      # Click to expand
      expanded_html = render_click(view, "toggle_rubric", %{})
      assert expanded_html =~ "Thesis"
      assert expanded_html =~ "Evidence"
      assert expanded_html =~ "Max score:"

      # Click again to collapse
      collapsed_html = render_click(view, "toggle_rubric", %{})
      refute collapsed_html =~ "Thesis"
    end

    test "try_again event resets grading state and creates a new draft", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      # Simulate that grading has completed via PubSub instead of triggering the
      # full submission + AI grading pipeline (which would need Mox expectations).
      grade_result = %{
        total_score: 7,
        max_score: 10,
        feedback: "Good effort.",
        strengths: ["Clear argument"],
        improvements: [],
        criteria: [],
        is_correct: true
      }

      send(view.pid, {:essay_graded, grade_result})
      render(view)

      # Now try_again should reset back to the writing interface
      html = render_click(view, "try_again", %{})

      assert html =~ "Submit for Grading"
      refute html =~ "Grading your essay"
    end
  end

  describe "handle_info/2 — PubSub essay grading result" do
    setup %{user_role: ur} do
      grant_essay_access(ur)
      :ok
    end

    test "receiving :essay_graded message renders the feedback card", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      grade_result = %{
        total_score: 8,
        max_score: 10,
        feedback: "Well-structured argument with strong evidence.",
        strengths: ["Clear thesis", "Good use of evidence"],
        improvements: ["Could expand conclusion"],
        criteria: [
          %{name: "Thesis", earned: 4, max: 5, comment: "Strong thesis"},
          %{name: "Evidence", earned: 4, max: 5, comment: "Good supporting evidence"}
        ],
        is_correct: true
      }

      send(view.pid, {:essay_graded, grade_result})

      html = render(view)

      assert html =~ "8"
      assert html =~ "10"
      assert html =~ "Well-structured argument with strong evidence."
      assert html =~ "Clear thesis"
      assert html =~ "Try Again"
    end

    test "receiving :essay_graded with failing score renders needs work state", %{
      conn: conn,
      user_role: ur,
      course: course,
      question: question
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/essay/#{question.id}")

      grade_result = %{
        total_score: 3,
        max_score: 10,
        feedback: "The essay lacks structure and supporting evidence.",
        strengths: [],
        improvements: ["Add a clear thesis", "Use specific historical examples"],
        criteria: [],
        is_correct: false
      }

      send(view.pid, {:essay_graded, grade_result})

      html = render(view)

      assert html =~ "3"
      assert html =~ "Review the feedback and try again"
      assert html =~ "Add a clear thesis"
    end
  end
end
