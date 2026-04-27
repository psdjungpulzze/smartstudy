defmodule FunSheep.Questions.AdminReviewTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.{Courses, Questions}

  defp create_course do
    {:ok, course} = Courses.create_course(%{name: "Bio", subject: "Biology", grade: "10"})
    course
  end

  defp create_needs_review_question(course, attrs \\ %{}) do
    defaults = %{
      content: "What is a cell?",
      answer: "Basic unit",
      question_type: :short_answer,
      difficulty: :medium,
      course_id: course.id,
      validation_status: :needs_review,
      validation_score: 72.0,
      validation_report: %{"topic_relevance_score" => 72, "verdict" => "needs_fix"}
    }

    {:ok, q} = Questions.create_question(Map.merge(defaults, attrs))
    q
  end

  describe "list_all_questions_needing_review/0" do
    test "returns only needs_review questions" do
      course = create_course()
      create_needs_review_question(course, %{content: "Review me"})
      create_needs_review_question(course, %{content: "Also me"})

      Questions.create_question(%{
        content: "Passed",
        answer: "X",
        question_type: :short_answer,
        difficulty: :easy,
        course_id: course.id,
        validation_status: :passed
      })

      Questions.create_question(%{
        content: "Failed",
        answer: "X",
        question_type: :short_answer,
        difficulty: :easy,
        course_id: course.id,
        validation_status: :failed
      })

      results = Questions.list_all_questions_needing_review()
      assert length(results) == 2

      contents = Enum.map(results, & &1.content)
      assert "Review me" in contents
      assert "Also me" in contents
    end

    test "preloads course and chapter" do
      course = create_course()
      {:ok, chapter} = Courses.create_chapter(%{name: "Ch1", position: 1, course_id: course.id})
      create_needs_review_question(course, %{chapter_id: chapter.id})

      [q] = Questions.list_all_questions_needing_review()
      assert q.course.id == course.id
      assert q.chapter.id == chapter.id
    end
  end

  describe "count_questions_needing_review/0" do
    test "returns the count of needs_review questions" do
      course = create_course()
      create_needs_review_question(course)
      create_needs_review_question(course)
      create_needs_review_question(course)

      assert Questions.count_questions_needing_review() == 3
    end

    test "returns 0 when none need review" do
      assert Questions.count_questions_needing_review() == 0
    end
  end

  describe "admin_approve_question/2" do
    test "flips status to :passed" do
      course = create_course()
      q = create_needs_review_question(course)

      assert {:ok, updated} = Questions.admin_approve_question(q, "reviewer-123")
      assert updated.validation_status == :passed
      assert updated.validated_at != nil
    end

    test "records the admin decision in the report" do
      course = create_course()
      q = create_needs_review_question(course)

      {:ok, updated} = Questions.admin_approve_question(q, "reviewer-123")

      decision = updated.validation_report["admin_decision"]
      assert decision["action"] == "approve"
      assert decision["reviewer_id"] == "reviewer-123"
      assert decision["at"]
    end

    test "preserves the original validator findings" do
      course = create_course()
      q = create_needs_review_question(course)

      {:ok, updated} = Questions.admin_approve_question(q, nil)

      # Original findings still present
      assert updated.validation_report["topic_relevance_score"] == 72
      assert updated.validation_report["verdict"] == "needs_fix"
    end

    test "approved question becomes visible to students" do
      course = create_course()

      {:ok, q} =
        Questions.create_question(%{
          content: "What is osmosis?",
          answer: "Water diffusion",
          question_type: :short_answer,
          difficulty: :medium,
          course_id: course.id,
          validation_status: :pending
        })

      # Before approval — :pending is hidden from students
      assert Questions.list_questions_by_course(course.id) == []

      Questions.admin_approve_question(q)

      # After approval — :passed is visible
      assert [visible] = Questions.list_questions_by_course(course.id)
      assert visible.id == q.id
    end
  end

  describe "admin_reject_question/2" do
    test "flips status to :failed" do
      course = create_course()
      q = create_needs_review_question(course)

      assert {:ok, updated} = Questions.admin_reject_question(q, "reviewer-456")
      assert updated.validation_status == :failed
    end

    test "records the rejection in the report" do
      course = create_course()
      q = create_needs_review_question(course)

      {:ok, updated} = Questions.admin_reject_question(q, "reviewer-456")

      decision = updated.validation_report["admin_decision"]
      assert decision["action"] == "reject"
      assert decision["reviewer_id"] == "reviewer-456"
    end

    test "rejected question stays hidden from students" do
      course = create_course()
      q = create_needs_review_question(course)

      Questions.admin_reject_question(q)

      assert Questions.list_questions_by_course(course.id) == []
    end
  end

  describe "admin_edit_and_approve/3" do
    test "updates content + marks passed" do
      course = create_course()
      q = create_needs_review_question(course)

      assert {:ok, updated} =
               Questions.admin_edit_and_approve(
                 q,
                 %{content: "Better question", answer: "Better answer"},
                 "reviewer-789"
               )

      assert updated.content == "Better question"
      assert updated.answer == "Better answer"
      assert updated.validation_status == :passed
    end

    test "accepts an explanation field" do
      course = create_course()
      q = create_needs_review_question(course)

      {:ok, updated} =
        Questions.admin_edit_and_approve(q, %{
          content: q.content,
          answer: q.answer,
          explanation: "Clear explanation for the student."
        })

      assert updated.explanation == "Clear explanation for the student."
    end

    test "records edit_and_approve in the decision log" do
      course = create_course()
      q = create_needs_review_question(course)

      {:ok, updated} =
        Questions.admin_edit_and_approve(
          q,
          %{content: "Edited", answer: "X"},
          "admin-1"
        )

      assert updated.validation_report["admin_decision"]["action"] == "edit_and_approve"
      assert updated.validation_report["admin_decision"]["reviewer_id"] == "admin-1"
    end
  end
end
