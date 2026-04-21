defmodule FunSheep.Questions.ValidationTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Courses
  alias FunSheep.Questions
  alias FunSheep.Questions.Validation

  defp create_course do
    {:ok, course} =
      Courses.create_course(%{name: "Test Course", subject: "Biology", grade: "10"})

    course
  end

  defp create_question(course, attrs \\ %{}) do
    defaults = %{
      content: "What is photosynthesis?",
      answer: "Process by which plants make food from sunlight",
      question_type: :short_answer,
      difficulty: :medium,
      course_id: course.id
    }

    {:ok, q} = Questions.create_question(Map.merge(defaults, attrs))
    q
  end

  describe "apply_verdict/2 — status derivation" do
    test "approve + score >= 95 → :passed" do
      course = create_course()
      q = create_question(course)

      verdict = %{
        "verdict" => "approve",
        "topic_relevance_score" => 98,
        "topic_relevance_reason" => "on topic",
        "completeness" => %{"passed" => true, "issues" => []},
        "categorization" => %{"suggested_chapter_id" => nil, "confidence" => 60},
        "answer_correct" => %{"correct" => true, "corrected_answer" => nil},
        "explanation" => %{"valid" => true, "suggested_explanation" => nil}
      }

      assert {:ok, updated} = Validation.apply_verdict(q, verdict)
      assert updated.validation_status == :passed
      assert updated.validation_score == 98.0
      assert updated.validated_at != nil
    end

    test "approve but low score → :needs_review (score wins over verdict)" do
      course = create_course()
      q = create_question(course)

      verdict = %{
        "verdict" => "approve",
        "topic_relevance_score" => 80,
        "completeness" => %{"passed" => true, "issues" => []},
        "categorization" => %{},
        "answer_correct" => %{"correct" => true},
        "explanation" => %{"valid" => true}
      }

      assert {:ok, updated} = Validation.apply_verdict(q, verdict)
      assert updated.validation_status == :needs_review
    end

    test "needs_fix + score >= 70 → :needs_review" do
      course = create_course()
      q = create_question(course)

      verdict = %{
        "verdict" => "needs_fix",
        "topic_relevance_score" => 75,
        "completeness" => %{"passed" => true, "issues" => []},
        "answer_correct" => %{"correct" => false, "corrected_answer" => "Better answer"},
        "explanation" => %{"valid" => true}
      }

      assert {:ok, updated} = Validation.apply_verdict(q, verdict)
      assert updated.validation_status == :needs_review
    end

    test "needs_fix + score < 70 → :failed" do
      course = create_course()
      q = create_question(course)

      verdict = %{
        "verdict" => "needs_fix",
        "topic_relevance_score" => 40,
        "completeness" => %{"passed" => false, "issues" => ["missing options"]},
        "answer_correct" => %{"correct" => false},
        "explanation" => %{"valid" => false}
      }

      assert {:ok, updated} = Validation.apply_verdict(q, verdict)
      assert updated.validation_status == :failed
    end

    test "reject → :failed regardless of score" do
      course = create_course()
      q = create_question(course)

      verdict = %{
        "verdict" => "reject",
        "topic_relevance_score" => 50,
        "completeness" => %{"passed" => false, "issues" => []},
        "answer_correct" => %{"correct" => false},
        "explanation" => %{"valid" => false}
      }

      assert {:ok, updated} = Validation.apply_verdict(q, verdict)
      assert updated.validation_status == :failed
    end

    test "stores the full verdict in validation_report for audit" do
      course = create_course()
      q = create_question(course)

      verdict = %{
        "verdict" => "approve",
        "topic_relevance_score" => 97,
        "topic_relevance_reason" => "tests photosynthesis concept",
        "completeness" => %{"passed" => true, "issues" => []}
      }

      assert {:ok, updated} = Validation.apply_verdict(q, verdict)
      assert updated.validation_report["topic_relevance_reason"] == "tests photosynthesis concept"
    end
  end

  describe "apply_verdict/2 — side-effects" do
    test "accepts suggested chapter when confidence >= 80" do
      course = create_course()
      {:ok, ch1} = Courses.create_chapter(%{name: "Ch1", position: 1, course_id: course.id})
      {:ok, ch2} = Courses.create_chapter(%{name: "Ch2", position: 2, course_id: course.id})

      q = create_question(course, %{chapter_id: ch1.id})

      verdict = %{
        "verdict" => "approve",
        "topic_relevance_score" => 96,
        "categorization" => %{"suggested_chapter_id" => ch2.id, "confidence" => 90},
        "completeness" => %{"passed" => true, "issues" => []},
        "answer_correct" => %{"correct" => true},
        "explanation" => %{"valid" => true}
      }

      assert {:ok, updated} = Validation.apply_verdict(q, verdict)
      assert updated.chapter_id == ch2.id
    end

    test "ignores suggested chapter when confidence < 80" do
      course = create_course()
      {:ok, ch1} = Courses.create_chapter(%{name: "Ch1", position: 1, course_id: course.id})
      {:ok, ch2} = Courses.create_chapter(%{name: "Ch2", position: 2, course_id: course.id})

      q = create_question(course, %{chapter_id: ch1.id})

      verdict = %{
        "verdict" => "approve",
        "topic_relevance_score" => 96,
        "categorization" => %{"suggested_chapter_id" => ch2.id, "confidence" => 60},
        "completeness" => %{"passed" => true, "issues" => []},
        "answer_correct" => %{"correct" => true},
        "explanation" => %{"valid" => true}
      }

      assert {:ok, updated} = Validation.apply_verdict(q, verdict)
      assert updated.chapter_id == ch1.id
    end

    test "fills missing explanation from validator suggestion" do
      course = create_course()
      q = create_question(course, %{explanation: nil})

      verdict = %{
        "verdict" => "approve",
        "topic_relevance_score" => 97,
        "completeness" => %{"passed" => true, "issues" => []},
        "answer_correct" => %{"correct" => true},
        "explanation" => %{
          "valid" => true,
          "suggested_explanation" => "Plants convert light energy to chemical energy."
        }
      }

      assert {:ok, updated} = Validation.apply_verdict(q, verdict)
      assert updated.explanation == "Plants convert light energy to chemical energy."
    end

    test "does NOT overwrite an existing explanation" do
      course = create_course()
      q = create_question(course, %{explanation: "Original explanation."})

      verdict = %{
        "verdict" => "approve",
        "topic_relevance_score" => 97,
        "completeness" => %{"passed" => true, "issues" => []},
        "answer_correct" => %{"correct" => true},
        "explanation" => %{
          "valid" => true,
          "suggested_explanation" => "Different explanation."
        }
      }

      assert {:ok, updated} = Validation.apply_verdict(q, verdict)
      assert updated.explanation == "Original explanation."
    end
  end

  describe "thresholds/0" do
    test "exposes numeric boundaries" do
      thresholds = Validation.thresholds()
      assert thresholds.passed == 95.0
      assert thresholds.review == 70.0
    end
  end
end
