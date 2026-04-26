defmodule FunSheep.Assessments.HasAnyAttemptTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Assessments
  alias FunSheep.ContentFixtures

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter} =
      FunSheep.Courses.create_chapter(%{
        name: "Chapter 1",
        position: 1,
        course_id: course.id
      })

    %{user_role: user_role, course: course, chapter: chapter}
  end

  describe "has_any_attempt?/2" do
    test "returns false when no attempts exist", %{user_role: ur, course: c} do
      refute Assessments.has_any_attempt?(ur.id, c.id)
    end

    test "returns true after a question attempt in the course", %{user_role: ur, course: c, chapter: ch} do
      {:ok, question} =
        FunSheep.Questions.create_question(%{
          content: "What is 2 + 2?",
          answer: "B",
          course_id: c.id,
          chapter_id: ch.id,
          difficulty: :easy,
          question_type: :multiple_choice,
          options: %{"A" => "3", "B" => "4"},
          validation_status: :approved
        })

      {:ok, _attempt} =
        FunSheep.Questions.create_question_attempt(%{
          user_role_id: ur.id,
          question_id: question.id,
          answer_given: "B",
          is_correct: true
        })

      assert Assessments.has_any_attempt?(ur.id, c.id)
    end

    test "returns false for a user who has no attempts in this course", %{course: c, chapter: ch} do
      attempter = ContentFixtures.create_user_role()
      non_attempter = ContentFixtures.create_user_role()

      {:ok, question} =
        FunSheep.Questions.create_question(%{
          content: "What is 2 + 2?",
          answer: "B",
          course_id: c.id,
          chapter_id: ch.id,
          difficulty: :easy,
          question_type: :multiple_choice,
          options: %{"A" => "3", "B" => "4"},
          validation_status: :approved
        })

      {:ok, _} =
        FunSheep.Questions.create_question_attempt(%{
          user_role_id: attempter.id,
          question_id: question.id,
          answer_given: "B",
          is_correct: true
        })

      refute Assessments.has_any_attempt?(non_attempter.id, c.id)
    end
  end
end
