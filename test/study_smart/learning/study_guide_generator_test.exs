defmodule StudySmart.Learning.StudyGuideGeneratorTest do
  use StudySmart.DataCase, async: true

  alias StudySmart.Learning.StudyGuideGenerator
  alias StudySmart.{Assessments, ContentFixtures}

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter1} =
      StudySmart.Courses.create_chapter(%{
        name: "Cells",
        position: 1,
        course_id: course.id
      })

    {:ok, chapter2} =
      StudySmart.Courses.create_chapter(%{
        name: "Genetics",
        position: 2,
        course_id: course.id
      })

    {:ok, schedule} =
      Assessments.create_test_schedule(%{
        name: "Bio Final",
        test_date: Date.add(Date.utc_today(), 14),
        scope: %{"chapter_ids" => [chapter1.id, chapter2.id]},
        user_role_id: user_role.id,
        course_id: course.id
      })

    %{
      user_role: user_role,
      course: course,
      chapter1: chapter1,
      chapter2: chapter2,
      schedule: schedule
    }
  end

  describe "generate/2" do
    test "creates study guide with correct structure", ctx do
      %{user_role: ur, schedule: schedule} = ctx

      assert {:ok, guide} = StudyGuideGenerator.generate(ur.id, schedule.id)
      assert guide.user_role_id == ur.id
      assert guide.test_schedule_id == schedule.id

      content = guide.content
      assert content["title"] == "Study Guide: Bio Final"
      assert content["generated_for"] =~ "Test Course"
      assert content["aggregate_score"] == 0
      assert is_list(content["sections"])
    end

    test "includes weak chapters in sections", ctx do
      %{user_role: ur, schedule: schedule, chapter1: ch1, chapter2: ch2} = ctx

      assert {:ok, guide} = StudyGuideGenerator.generate(ur.id, schedule.id)
      sections = guide.content["sections"]

      chapter_names = Enum.map(sections, & &1["chapter_name"])
      assert "Cells" in chapter_names
      assert "Genetics" in chapter_names

      chapter_ids = Enum.map(sections, & &1["chapter_id"])
      assert ch1.id in chapter_ids
      assert ch2.id in chapter_ids
    end

    test "generates with readiness data", ctx do
      %{user_role: ur, course: course, chapter1: ch1, schedule: schedule} = ctx

      # Create a question and correct attempt for chapter1 (100%)
      {:ok, q} =
        StudySmart.Questions.create_question(%{
          content: "What is a cell?",
          answer: "Basic unit of life",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          chapter_id: ch1.id
        })

      StudySmart.Questions.create_question_attempt(%{
        user_role_id: ur.id,
        question_id: q.id,
        answer_given: "Basic unit of life",
        is_correct: true
      })

      # Calculate readiness so ch1 is at 100% (above 80 threshold)
      {:ok, _readiness} = Assessments.calculate_and_save_readiness(ur.id, schedule.id)

      assert {:ok, guide} = StudyGuideGenerator.generate(ur.id, schedule.id)
      sections = guide.content["sections"]

      # Chapter 1 at 100% should NOT be in weak chapters (>= 80% threshold)
      chapter_names = Enum.map(sections, & &1["chapter_name"])
      refute "Cells" in chapter_names
      # Chapter 2 at 0% should be in weak chapters
      assert "Genetics" in chapter_names
    end

    test "includes wrong questions in sections", ctx do
      %{user_role: ur, course: course, chapter1: ch1, schedule: schedule} = ctx

      {:ok, q} =
        StudySmart.Questions.create_question(%{
          content: "What is mitosis?",
          answer: "Cell division",
          question_type: :short_answer,
          difficulty: :medium,
          course_id: course.id,
          chapter_id: ch1.id
        })

      StudySmart.Questions.create_question_attempt(%{
        user_role_id: ur.id,
        question_id: q.id,
        answer_given: "Wrong answer",
        is_correct: false
      })

      assert {:ok, guide} = StudyGuideGenerator.generate(ur.id, schedule.id)

      cells_section =
        Enum.find(guide.content["sections"], fn s -> s["chapter_name"] == "Cells" end)

      assert cells_section
      assert length(cells_section["wrong_questions"]) == 1
      wrong_q = hd(cells_section["wrong_questions"])
      assert wrong_q["content"] == "What is mitosis?"
      assert wrong_q["answer"] == "Cell division"
    end
  end

  describe "identify_weak_chapters/2" do
    test "returns all chapters when no readiness", _ctx do
      chapters = [%{id: "a", name: "A"}, %{id: "b", name: "B"}]
      result = StudyGuideGenerator.identify_weak_chapters(nil, chapters)
      assert length(result) == 2
    end

    test "filters chapters above 80% threshold" do
      readiness = %{chapter_scores: %{"a" => 90.0, "b" => 50.0, "c" => 20.0}}
      chapters = [%{id: "a", name: "A"}, %{id: "b", name: "B"}, %{id: "c", name: "C"}]

      result = StudyGuideGenerator.identify_weak_chapters(readiness, chapters)
      ids = Enum.map(result, fn {ch, _score} -> ch.id end)

      refute "a" in ids
      assert "b" in ids
      assert "c" in ids
    end

    test "sorts by score ascending" do
      readiness = %{chapter_scores: %{"a" => 60.0, "b" => 30.0}}
      chapters = [%{id: "a", name: "A"}, %{id: "b", name: "B"}]

      result = StudyGuideGenerator.identify_weak_chapters(readiness, chapters)
      scores = Enum.map(result, fn {_ch, score} -> score end)

      assert scores == [30.0, 60.0]
    end
  end

  describe "priority_label/1" do
    test "returns Critical for scores below 30" do
      assert StudyGuideGenerator.priority_label(0) == "Critical"
      assert StudyGuideGenerator.priority_label(29) == "Critical"
    end

    test "returns High for scores 30-49" do
      assert StudyGuideGenerator.priority_label(30) == "High"
      assert StudyGuideGenerator.priority_label(49) == "High"
    end

    test "returns Medium for scores 50-69" do
      assert StudyGuideGenerator.priority_label(50) == "Medium"
      assert StudyGuideGenerator.priority_label(69) == "Medium"
    end

    test "returns Low for scores 70+" do
      assert StudyGuideGenerator.priority_label(70) == "Low"
      assert StudyGuideGenerator.priority_label(100) == "Low"
    end
  end
end
