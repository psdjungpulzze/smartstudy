defmodule FunSheep.Questions.AdminQuestionActionsTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.{Questions, Courses}
  alias FunSheep.Questions.Deduplicator

  defp create_course(name) do
    {:ok, course} =
      Courses.create_course(%{name: name, subject: "Biology", grade: "10"})

    course
  end

  defp create_question(attrs) do
    {:ok, q} = Questions.create_question(attrs)
    q
  end

  defp web_scraped_attrs(course_id, content, tier, status \\ :needs_review) do
    %{
      content: content,
      answer: "An answer",
      question_type: :short_answer,
      difficulty: :easy,
      course_id: course_id,
      source_type: :web_scraped,
      source_tier: tier,
      validation_status: status,
      content_fingerprint: Deduplicator.fingerprint(content)
    }
  end

  describe "list_all_questions_for_admin/2" do
    test "with no filters returns all questions preloaded with course" do
      course = create_course("List All Course")

      q1 = create_question(web_scraped_attrs(course.id, "What is photosynthesis?", 1, :needs_review))
      q2 = create_question(web_scraped_attrs(course.id, "Describe osmosis in cells.", 2, :passed))

      results = Questions.list_all_questions_for_admin(nil, nil)
      result_ids = Enum.map(results, & &1.id)

      assert q1.id in result_ids
      assert q2.id in result_ids

      # All results should have the course preloaded
      assert Enum.all?(results, fn q ->
               match?(%{course: %Courses.Course{}}, q)
             end)
    end

    test "with status filter returns only matching status questions" do
      course = create_course("Status Filter Course")

      q_review = create_question(web_scraped_attrs(course.id, "What is meiosis?", 1, :needs_review))
      q_passed = create_question(web_scraped_attrs(course.id, "What is mitosis?", 1, :passed))

      results = Questions.list_all_questions_for_admin(:needs_review, nil)
      result_ids = Enum.map(results, & &1.id)

      assert q_review.id in result_ids
      refute q_passed.id in result_ids
    end

    test "with tier filter returns only questions at that tier" do
      course = create_course("Tier Filter Course")

      q_tier1 = create_question(web_scraped_attrs(course.id, "Tier 1 question about ATP", 1))
      q_tier2 = create_question(web_scraped_attrs(course.id, "Tier 2 question about ADP", 2))

      results = Questions.list_all_questions_for_admin(nil, 1)
      result_ids = Enum.map(results, & &1.id)

      assert q_tier1.id in result_ids
      refute q_tier2.id in result_ids
    end

    test "with both status and tier filters returns only questions matching both" do
      course = create_course("Combined Filter Course")

      q_match =
        create_question(web_scraped_attrs(course.id, "Needs review tier 1 question about RNA", 1, :needs_review))

      q_wrong_status =
        create_question(web_scraped_attrs(course.id, "Passed tier 1 question about DNA", 1, :passed))

      q_wrong_tier =
        create_question(web_scraped_attrs(course.id, "Needs review tier 2 question about lipids", 2, :needs_review))

      results = Questions.list_all_questions_for_admin(:needs_review, 1)
      result_ids = Enum.map(results, & &1.id)

      assert q_match.id in result_ids
      refute q_wrong_status.id in result_ids
      refute q_wrong_tier.id in result_ids
    end
  end

  describe "bulk_approve_web_tier1_questions/1" do
    test "approves needs_review web_scraped tier-1 questions and returns {:ok, count}" do
      course = create_course("Bulk Approve Course")

      q1 = create_question(web_scraped_attrs(course.id, "Bulk tier 1 Q1 about enzymes", 1, :needs_review))
      q2 = create_question(web_scraped_attrs(course.id, "Bulk tier 1 Q2 about proteins", 1, :needs_review))

      assert {:ok, 2} = Questions.bulk_approve_web_tier1_questions(nil)

      assert Questions.get_question!(q1.id).validation_status == :passed
      assert Questions.get_question!(q2.id).validation_status == :passed
    end

    test "returns {:ok, 0} when no qualifying questions exist" do
      course = create_course("No Tier 1 Course")

      # Create a tier-2 web_scraped question — should NOT be bulk-approved
      _q_tier2 =
        create_question(web_scraped_attrs(course.id, "Tier 2 question about carbohydrates", 2, :needs_review))

      assert {:ok, 0} = Questions.bulk_approve_web_tier1_questions(nil)
    end

    test "does not approve tier-2 questions" do
      course = create_course("Tier 2 Guard Course")

      q_tier2 =
        create_question(web_scraped_attrs(course.id, "Tier 2 needs review question about fats", 2, :needs_review))

      q_tier1 =
        create_question(web_scraped_attrs(course.id, "Tier 1 needs review question about glucose", 1, :needs_review))

      {:ok, count} = Questions.bulk_approve_web_tier1_questions(nil)

      assert count == 1
      assert Questions.get_question!(q_tier1.id).validation_status == :passed
      assert Questions.get_question!(q_tier2.id).validation_status == :needs_review
    end

    test "does not approve non-web_scraped questions even if they are tier 1" do
      course = create_course("Non Web Scraped Course")

      {:ok, q_ai} =
        Questions.create_question(%{
          content: "AI generated tier 1 question about viruses",
          answer: "Viruses replicate in host cells",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          source_type: :ai_generated,
          source_tier: 1,
          validation_status: :needs_review
        })

      _q_web =
        create_question(
          web_scraped_attrs(course.id, "Web scraped tier 1 question about bacteria", 1, :needs_review)
        )

      {:ok, count} = Questions.bulk_approve_web_tier1_questions(nil)

      assert count == 1
      assert Questions.get_question!(q_ai.id).validation_status == :needs_review
    end

    test "does not approve already-passed questions" do
      course = create_course("Already Passed Course")

      q_already_passed =
        create_question(
          web_scraped_attrs(course.id, "Already passed tier 1 question about fungi", 1, :passed)
        )

      q_review =
        create_question(
          web_scraped_attrs(course.id, "Needs review tier 1 question about algae", 1, :needs_review)
        )

      {:ok, count} = Questions.bulk_approve_web_tier1_questions(nil)

      assert count == 1
      assert Questions.get_question!(q_already_passed.id).validation_status == :passed
      assert Questions.get_question!(q_review.id).validation_status == :passed
    end

    test "accepts an optional reviewer_id without error" do
      course = create_course("Reviewer ID Course")

      _q =
        create_question(
          web_scraped_attrs(course.id, "Reviewer ID test question about plant cells", 1, :needs_review)
        )

      assert {:ok, 1} = Questions.bulk_approve_web_tier1_questions("reviewer-abc-123")
    end
  end
end
