defmodule FunSheep.Questions.ValidationThresholdsTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.{Courses, Questions}
  alias FunSheep.Questions.Validation
  alias FunSheep.ContentFixtures

  # Build a minimal verdict map that looks like a real LLM response
  defp verdict(overrides \\ %{}) do
    Map.merge(
      %{
        "topic_relevance_score" => 80,
        "topic_relevance_reason" => "on topic",
        "completeness" => %{"passed" => true, "issues" => []},
        "categorization" => %{"suggested_chapter_id" => nil, "confidence" => 50},
        "answer_correct" => %{"correct" => true, "corrected_answer" => nil},
        "explanation" => %{"valid" => true, "suggested_explanation" => nil},
        "verdict" => "approve"
      },
      overrides
    )
  end

  setup do
    course = ContentFixtures.create_course()
    {:ok, chapter} = Courses.create_chapter(%{name: "Ch1", position: 1, course_id: course.id})
    %{course: course, chapter: chapter}
  end

  defp create_question(course, chapter, extra_attrs \\ []) do
    {:ok, q} =
      Questions.create_question(
        Map.merge(
          %{
            content: "What is 2 + 2?",
            answer: "4",
            question_type: :short_answer,
            difficulty: :easy,
            course_id: course.id,
            chapter_id: chapter.id,
            validation_status: :pending
          },
          Enum.into(extra_attrs, %{})
        )
      )

    q
  end

  describe "apply_verdict/3 with nil thresholds (default behaviour — AI-generated path)" do
    test "score 80 with approve verdict → :needs_review (default threshold 95)", %{course: c, chapter: ch} do
      question = create_question(c, ch)
      {:ok, updated} = Validation.apply_verdict(question, verdict(%{"topic_relevance_score" => 80}))
      assert updated.validation_status == :needs_review
    end

    test "score 96 with approve verdict → :passed", %{course: c, chapter: ch} do
      question = create_question(c, ch)
      {:ok, updated} = Validation.apply_verdict(question, verdict(%{"topic_relevance_score" => 96}))
      assert updated.validation_status == :passed
    end

    test "score 75 with needs_fix verdict → :needs_review (review threshold 70)", %{course: c, chapter: ch} do
      question = create_question(c, ch)
      {:ok, updated} = Validation.apply_verdict(question, verdict(%{"topic_relevance_score" => 75, "verdict" => "needs_fix"}))
      assert updated.validation_status == :needs_review
    end

    test "score 60 with needs_fix verdict → :failed (below review threshold 70)", %{course: c, chapter: ch} do
      question = create_question(c, ch)
      {:ok, updated} = Validation.apply_verdict(question, verdict(%{"topic_relevance_score" => 60, "verdict" => "needs_fix"}))
      assert updated.validation_status == :failed
    end

    test "reject verdict → always :failed regardless of score", %{course: c, chapter: ch} do
      question = create_question(c, ch)
      {:ok, updated} = Validation.apply_verdict(question, verdict(%{"topic_relevance_score" => 99, "verdict" => "reject"}))
      assert updated.validation_status == :failed
    end
  end

  describe "apply_verdict/3 with Tier 1 thresholds (75.0 / 60.0)" do
    @tier1 %{passed_threshold: 75.0, review_threshold: 60.0}

    test "score 80 with approve verdict → :passed (80 >= 75)", %{course: c, chapter: ch} do
      question = create_question(c, ch)
      {:ok, updated} = Validation.apply_verdict(question, verdict(%{"topic_relevance_score" => 80}), @tier1)
      assert updated.validation_status == :passed
    end

    test "score 74 with approve verdict → :needs_review (74 < 75)", %{course: c, chapter: ch} do
      question = create_question(c, ch)
      {:ok, updated} = Validation.apply_verdict(question, verdict(%{"topic_relevance_score" => 74}), @tier1)
      assert updated.validation_status == :needs_review
    end

    test "score 65 with needs_fix verdict → :needs_review (65 >= 60)", %{course: c, chapter: ch} do
      question = create_question(c, ch)
      {:ok, updated} = Validation.apply_verdict(question, verdict(%{"topic_relevance_score" => 65, "verdict" => "needs_fix"}), @tier1)
      assert updated.validation_status == :needs_review
    end

    test "score 55 with needs_fix verdict → :failed (55 < 60)", %{course: c, chapter: ch} do
      question = create_question(c, ch)
      {:ok, updated} = Validation.apply_verdict(question, verdict(%{"topic_relevance_score" => 55, "verdict" => "needs_fix"}), @tier1)
      assert updated.validation_status == :failed
    end

    test "reject always fails even for Tier 1", %{course: c, chapter: ch} do
      question = create_question(c, ch)
      {:ok, updated} = Validation.apply_verdict(question, verdict(%{"topic_relevance_score" => 99, "verdict" => "reject"}), @tier1)
      assert updated.validation_status == :failed
    end
  end

  describe "apply_verdict/3 with Tier 2 thresholds (82.0 / 65.0)" do
    @tier2 %{passed_threshold: 82.0, review_threshold: 65.0}

    test "score 85 with approve → :passed", %{course: c, chapter: ch} do
      question = create_question(c, ch)
      {:ok, updated} = Validation.apply_verdict(question, verdict(%{"topic_relevance_score" => 85}), @tier2)
      assert updated.validation_status == :passed
    end

    test "score 80 with approve → :needs_review (80 < 82)", %{course: c, chapter: ch} do
      question = create_question(c, ch)
      {:ok, updated} = Validation.apply_verdict(question, verdict(%{"topic_relevance_score" => 80}), @tier2)
      assert updated.validation_status == :needs_review
    end
  end

  describe "apply_verdict/3 with Tier 4 thresholds (95.0 / 70.0) — same as default" do
    @tier4 %{passed_threshold: 95.0, review_threshold: 70.0}

    test "score 80 with approve → :needs_review (same as default)", %{course: c, chapter: ch} do
      question = create_question(c, ch)
      {:ok, updated} = Validation.apply_verdict(question, verdict(%{"topic_relevance_score" => 80}), @tier4)
      assert updated.validation_status == :needs_review
    end

    test "score 96 with approve → :passed (same as default)", %{course: c, chapter: ch} do
      question = create_question(c, ch)
      {:ok, updated} = Validation.apply_verdict(question, verdict(%{"topic_relevance_score" => 96}), @tier4)
      assert updated.validation_status == :passed
    end
  end

  describe "regression: two-arg apply_verdict/2 still works with 95.0 threshold" do
    test "score 80 still goes to :needs_review when called without thresholds", %{course: c, chapter: ch} do
      question = create_question(c, ch, source_type: :ai_generated)
      {:ok, updated} = Validation.apply_verdict(question, verdict(%{"topic_relevance_score" => 80}))
      assert updated.validation_status == :needs_review
    end

    test "score 96 still goes to :passed when called without thresholds", %{course: c, chapter: ch} do
      question = create_question(c, ch, source_type: :ai_generated)
      {:ok, updated} = Validation.apply_verdict(question, verdict(%{"topic_relevance_score" => 96}))
      assert updated.validation_status == :passed
    end
  end
end
