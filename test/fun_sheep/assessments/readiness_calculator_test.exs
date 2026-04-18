defmodule FunSheep.Assessments.ReadinessCalculatorTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Assessments.ReadinessCalculator
  alias FunSheep.ContentFixtures

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter1} =
      FunSheep.Courses.create_chapter(%{
        name: "Chapter 1",
        position: 1,
        course_id: course.id
      })

    {:ok, chapter2} =
      FunSheep.Courses.create_chapter(%{
        name: "Chapter 2",
        position: 2,
        course_id: course.id
      })

    {:ok, schedule} =
      FunSheep.Assessments.create_test_schedule(%{
        name: "Test",
        test_date: Date.add(Date.utc_today(), 7),
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

  describe "calculate/2" do
    test "returns 0 with no attempts", %{user_role: ur, schedule: schedule} do
      result = ReadinessCalculator.calculate(ur.id, schedule)

      assert result.aggregate_score == 0.0
      assert map_size(result.chapter_scores) == 2

      Enum.each(result.chapter_scores, fn {_id, score} ->
        assert score == 0.0
      end)
    end

    test "calculates correct percentage with mixed attempts", ctx do
      %{user_role: ur, course: course, chapter1: ch1, schedule: schedule} = ctx

      {:ok, q1} =
        FunSheep.Questions.create_question(%{
          content: "Q1",
          answer: "A",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          chapter_id: ch1.id
        })

      # 2 correct, 1 incorrect = 66.7%
      FunSheep.Questions.create_question_attempt(%{
        user_role_id: ur.id,
        question_id: q1.id,
        answer_given: "A",
        is_correct: true
      })

      {:ok, q2} =
        FunSheep.Questions.create_question(%{
          content: "Q2",
          answer: "B",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          chapter_id: ch1.id
        })

      FunSheep.Questions.create_question_attempt(%{
        user_role_id: ur.id,
        question_id: q2.id,
        answer_given: "B",
        is_correct: true
      })

      FunSheep.Questions.create_question_attempt(%{
        user_role_id: ur.id,
        question_id: q1.id,
        answer_given: "wrong",
        is_correct: false
      })

      result = ReadinessCalculator.calculate(ur.id, schedule)

      assert result.chapter_scores[ch1.id] == 66.7
      # aggregate = (66.7 + 0.0) / 2 ~ 33.3-33.4 depending on rounding
      assert_in_delta result.aggregate_score, 33.35, 0.1
    end

    test "aggregate score averages chapter scores", ctx do
      %{user_role: ur, course: course, chapter1: ch1, chapter2: ch2, schedule: schedule} = ctx

      # Chapter 1: 1 correct out of 1 = 100%
      {:ok, q1} =
        FunSheep.Questions.create_question(%{
          content: "Q1",
          answer: "A",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          chapter_id: ch1.id
        })

      FunSheep.Questions.create_question_attempt(%{
        user_role_id: ur.id,
        question_id: q1.id,
        answer_given: "A",
        is_correct: true
      })

      # Chapter 2: 1 correct out of 2 = 50%
      {:ok, q2} =
        FunSheep.Questions.create_question(%{
          content: "Q2",
          answer: "B",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          chapter_id: ch2.id
        })

      FunSheep.Questions.create_question_attempt(%{
        user_role_id: ur.id,
        question_id: q2.id,
        answer_given: "B",
        is_correct: true
      })

      FunSheep.Questions.create_question_attempt(%{
        user_role_id: ur.id,
        question_id: q2.id,
        answer_given: "wrong",
        is_correct: false
      })

      result = ReadinessCalculator.calculate(ur.id, schedule)

      assert result.chapter_scores[ch1.id] == 100.0
      assert result.chapter_scores[ch2.id] == 50.0
      # (100 + 50) / 2 = 75.0
      assert result.aggregate_score == 75.0
    end
  end
end
