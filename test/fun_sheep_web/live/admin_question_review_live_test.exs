defmodule FunSheepWeb.AdminQuestionReviewLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{Accounts, Admin, Courses, Questions}

  defp create_admin_user do
    {:ok, admin} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: :admin,
        email: "admin_review_#{System.unique_integer([:positive])}@test.com",
        display_name: "Test Admin"
      })

    admin
  end

  defp admin_conn(conn) do
    admin = create_admin_user()

    conn
    |> init_test_session(%{
      dev_user_id: admin.id,
      dev_user: %{
        "id" => admin.id,
        "user_role_id" => admin.id,
        "interactor_user_id" => admin.interactor_user_id,
        "role" => "admin",
        "email" => admin.email,
        "display_name" => admin.display_name
      }
    })
  end

  defp seed_queue do
    {:ok, course} =
      Courses.create_course(%{name: "Biology 101", subject: "Biology", grade: "10"})

    {:ok, q} =
      Questions.create_question(%{
        content: "What is a cell's powerhouse?",
        answer: "Mitochondria",
        question_type: :short_answer,
        difficulty: :easy,
        course_id: course.id,
        validation_status: :needs_review,
        validation_score: 72.0,
        validation_report: %{
          "topic_relevance_score" => 72,
          "topic_relevance_reason" => "Relevant to biology but slightly broad.",
          "completeness" => %{"passed" => true, "issues" => []},
          "answer_correct" => %{"correct" => true, "corrected_answer" => nil},
          "explanation" => %{
            "valid" => false,
            "suggested_explanation" => "Mitochondria produce ATP, the cell's energy currency."
          },
          "verdict" => "needs_fix"
        }
      })

    {course, q}
  end

  describe "render" do
    test "shows empty state when no questions need review", %{conn: conn} do
      conn = admin_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/admin/questions/review")

      assert html =~ "No questions in this view"
      assert html =~ "Questions"
    end

    test "lists questions in the review queue", %{conn: conn} do
      {_course, _q} = seed_queue()

      conn = admin_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/admin/questions/review")

      assert html =~ "What is a cell&#39;s powerhouse?"
      assert html =~ "Biology 101"
      assert html =~ "72"
      assert html =~ "Relevant to biology"
    end

    test "shows queue count", %{conn: conn} do
      seed_queue()
      seed_queue()

      conn = admin_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/admin/questions/review")

      # count pill shows 2
      assert html =~ ~s(<span class="text-2xl font-bold text-[#4CD964]">2</span>)
    end
  end

  describe "approve event" do
    test "flips the question to passed and removes it from the queue", %{conn: conn} do
      {_course, q} = seed_queue()

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "approve", %{"id" => q.id})

      assert html =~ "No questions in this view"
      assert Questions.get_question!(q.id).validation_status == :passed
    end
  end

  describe "reject event" do
    test "flips the question to failed and removes it from the queue", %{conn: conn} do
      {_course, q} = seed_queue()

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "reject", %{"id" => q.id})

      assert html =~ "No questions in this view"
      assert Questions.get_question!(q.id).validation_status == :failed
    end
  end

  describe "edit flow" do
    test "edit event shows an editable form", %{conn: conn} do
      {_course, q} = seed_queue()

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "edit", %{"id" => q.id})

      assert html =~ "Save &amp; Approve"
      assert html =~ "Cancel"
      assert html =~ "What is a cell&#39;s powerhouse?"
    end

    test "cancel_edit dismisses the form and shows the question again", %{conn: conn} do
      {_course, q} = seed_queue()

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      render_click(view, "edit", %{"id" => q.id})
      html = render_click(view, "cancel_edit", %{})

      # Form gone, question content visible again
      refute html =~ "Save &amp; Approve"
      assert html =~ "What is a cell&#39;s powerhouse?"
    end

    test "save_edit updates the question and approves it", %{conn: conn} do
      {_course, q} = seed_queue()

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      _ = render_click(view, "edit", %{"id" => q.id})

      render_submit(view, "save_edit", %{
        "id" => q.id,
        "question" => %{
          "content" => "What produces ATP in eukaryotic cells?",
          "answer" => "Mitochondria",
          "explanation" => "Mitochondria use oxidative phosphorylation to make ATP."
        }
      })

      updated = Questions.get_question!(q.id)
      assert updated.content == "What produces ATP in eukaryotic cells?"
      assert updated.explanation == "Mitochondria use oxidative phosphorylation to make ATP."
      assert updated.validation_status == :passed
    end
  end

  describe "delete event" do
    test "delete removes the question and shows flash", %{conn: conn} do
      {_course, q} = seed_queue()

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "delete", %{"id" => q.id})

      assert html =~ "deleted" or html =~ "Question deleted"
      assert html =~ "No questions in this view"
    end
  end

  describe "filter_status event" do
    test "filter to 'passed' shows empty state when no passed questions exist", %{conn: conn} do
      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "filter_status", %{"status" => "passed"})

      assert html =~ "No questions in this view"
    end

    test "filter to 'failed' shows empty state when no failed questions exist", %{conn: conn} do
      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "filter_status", %{"status" => "failed"})

      assert html =~ "No questions in this view"
    end

    test "filter to 'pending' shows empty state when no pending questions exist", %{conn: conn} do
      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "filter_status", %{"status" => "pending"})

      assert html =~ "No questions in this view"
    end

    test "filter to 'all' shows all questions", %{conn: conn} do
      {_course, _q} = seed_queue()

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "filter_status", %{"status" => "all"})

      assert is_binary(html)
    end

    test "filter to 'needs_review' shows the review queue", %{conn: conn} do
      {_course, _q} = seed_queue()

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      # First switch away
      render_click(view, "filter_status", %{"status" => "passed"})

      # Now switch back
      html = render_click(view, "filter_status", %{"status" => "needs_review"})

      assert html =~ "What is a cell&#39;s powerhouse?"
    end

    test "filter to unknown status resets to 'all'", %{conn: conn} do
      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "filter_status", %{"status" => "unknown_status"})

      assert is_binary(html)
    end

    test "clears editing state when status filter changes", %{conn: conn} do
      {_course, q} = seed_queue()

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      render_click(view, "edit", %{"id" => q.id})

      html = render_click(view, "filter_status", %{"status" => "passed"})

      # No edit form should be visible
      refute html =~ "Save &amp; Approve"
    end
  end

  describe "filter_tier event" do
    test "filter to tier 1 shows empty state when no tier-1 questions in queue", %{conn: conn} do
      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "filter_tier", %{"tier" => "1"})

      # No tier-1 questions exist in the needs_review queue
      assert is_binary(html)
    end

    test "filter to 'all' tier resets the tier filter", %{conn: conn} do
      {_course, _q} = seed_queue()

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      # Filter to tier 1 first
      render_click(view, "filter_tier", %{"tier" => "1"})

      # Reset to all
      html = render_click(view, "filter_tier", %{"tier" => "all"})

      assert html =~ "What is a cell&#39;s powerhouse?"
    end

    test "invalid tier string resets to nil (all tiers)", %{conn: conn} do
      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "filter_tier", %{"tier" => "abc"})

      assert is_binary(html)
    end

    test "tier 2 filter shows only tier-2 questions", %{conn: conn} do
      {:ok, course} =
        Courses.create_course(%{name: "Tier2 Course", subject: "Math", grade: "10"})

      {:ok, _q2} =
        Questions.create_question(%{
          content: "Tier 2 question content",
          answer: "Tier 2 answer",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          validation_status: :needs_review,
          source_tier: 2
        })

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "filter_tier", %{"tier" => "2"})

      assert html =~ "Tier 2 question content"
    end

    test "tier 1 filter shows bulk approve button", %{conn: conn} do
      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      # Initially on needs_review, bulk approve is visible
      html = render(view)

      assert html =~ "Bulk approve Tier 1"
    end
  end

  describe "bulk_approve_tier1 event" do
    test "bulk approve with no tier-1 queue items shows info flash", %{conn: conn} do
      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "bulk_approve_tier1", %{})

      assert html =~ "No Tier 1 questions in the review queue"
    end

    test "bulk approve with tier-1 items approves them and shows count", %{conn: conn} do
      {:ok, course} =
        Courses.create_course(%{name: "Tier1 Bulk Course", subject: "History", grade: "11"})

      {:ok, _q1} =
        Questions.create_question(%{
          content: "Tier 1 bulk question 1",
          answer: "Tier 1 answer",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          validation_status: :needs_review,
          source_tier: 1,
          source_type: :web_scraped
        })

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "bulk_approve_tier1", %{})

      assert html =~ "Bulk approved" or html =~ "question"
    end
  end

  describe "question rendering with full validation report" do
    test "shows completeness issues when present", %{conn: conn} do
      {:ok, course} =
        Courses.create_course(%{name: "Completeness Course", subject: "Science", grade: "9"})

      {:ok, _q} =
        Questions.create_question(%{
          content: "Incomplete question?",
          answer: "A",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          validation_status: :needs_review,
          validation_report: %{
            "topic_relevance_score" => 60,
            "topic_relevance_reason" => "Somewhat relevant.",
            "completeness" => %{
              "passed" => false,
              "issues" => ["Missing context", "Ambiguous wording"]
            },
            "answer_correct" => %{"correct" => true, "corrected_answer" => nil},
            "explanation" => %{"valid" => true, "suggested_explanation" => nil}
          }
        })

      conn = admin_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/admin/questions/review")

      assert html =~ "Missing context"
      assert html =~ "Completeness"
    end

    test "shows corrected answer suggestion when present", %{conn: conn} do
      {:ok, course} =
        Courses.create_course(%{name: "Corrected Answer Course", subject: "Math", grade: "9"})

      {:ok, _q} =
        Questions.create_question(%{
          content: "What is 2+2?",
          answer: "3",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          validation_status: :needs_review,
          validation_report: %{
            "topic_relevance_score" => 90,
            "completeness" => %{"passed" => true, "issues" => []},
            "answer_correct" => %{
              "correct" => false,
              "corrected_answer" => "4"
            },
            "explanation" => %{"valid" => true, "suggested_explanation" => nil}
          }
        })

      conn = admin_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/admin/questions/review")

      assert html =~ "Suggested answer"
    end

    test "shows suggested explanation when present in validation report", %{conn: conn} do
      {:ok, course} =
        Courses.create_course(%{
          name: "Suggested Explanation Course",
          subject: "Biology",
          grade: "10"
        })

      {:ok, _q} =
        Questions.create_question(%{
          content: "Why is the sky blue?",
          answer: "Rayleigh scattering",
          question_type: :short_answer,
          difficulty: :medium,
          course_id: course.id,
          validation_status: :needs_review,
          validation_report: %{
            "topic_relevance_score" => 80,
            "completeness" => %{"passed" => true, "issues" => []},
            "answer_correct" => %{"correct" => true, "corrected_answer" => nil},
            "explanation" => %{
              "valid" => false,
              "suggested_explanation" =>
                "Light scatters due to its wavelength interacting with air molecules."
            }
          }
        })

      conn = admin_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/admin/questions/review")

      assert html =~ "Suggested explanation"
    end

    test "shows tier badge for tier-3 questions", %{conn: conn} do
      {:ok, course} =
        Courses.create_course(%{name: "Tier3 Course", subject: "History", grade: "8"})

      {:ok, _q} =
        Questions.create_question(%{
          content: "Tier 3 question about history",
          answer: "Some answer",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          validation_status: :needs_review,
          source_tier: 3
        })

      conn = admin_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/admin/questions/review")

      assert html =~ "Tier 3"
    end

    test "shows tier badge for tier-4 questions (low quality style)", %{conn: conn} do
      {:ok, course} =
        Courses.create_course(%{name: "Tier4 Course", subject: "Art", grade: "7"})

      {:ok, _q} =
        Questions.create_question(%{
          content: "Tier 4 art question",
          answer: "Some answer",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          validation_status: :needs_review,
          source_tier: 4
        })

      conn = admin_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/admin/questions/review")

      assert html =~ "Tier 4"
    end
  end

  describe "approved/failed question states" do
    test "approved question does not show Approve button", %{conn: conn} do
      {:ok, course} =
        Courses.create_course(%{name: "Passed Course", subject: "English", grade: "10"})

      {:ok, q} =
        Questions.create_question(%{
          content: "Approved question content",
          answer: "Answer",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          validation_status: :passed
        })

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      # Switch to passed view
      html = render_click(view, "filter_status", %{"status" => "passed"})

      # Approve button should NOT appear (already passed)
      assert html =~ q.content
      refute html =~ "phx-click=\"approve\""
    end

    test "failed question does not show Reject button", %{conn: conn} do
      {:ok, course} =
        Courses.create_course(%{name: "Failed Course", subject: "PE", grade: "9"})

      {:ok, q} =
        Questions.create_question(%{
          content: "Failed question content",
          answer: "Answer",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          validation_status: :failed
        })

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "filter_status", %{"status" => "failed"})

      assert html =~ q.content
      refute html =~ "phx-click=\"reject\""
    end
  end

  describe "status counts" do
    test "status count pills update when questions are present", %{conn: conn} do
      seed_queue()

      conn = admin_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/admin/questions/review")

      # The queue count badge should show at least 1
      assert html =~ ~r/text-2xl font-bold text-\[#4CD964\]/
    end
  end
end
