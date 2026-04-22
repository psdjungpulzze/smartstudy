defmodule FunSheep.TutorContextTest do
  @moduledoc """
  Tests the student-aware enrichments added to `Tutor.build_context/3` for
  North Star invariants I-12 (tutor prompt includes hobbies + weak skills)
  and I-15 (insufficient data shows up as empty lists, not fabrications).
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.{Courses, Learning, Questions, Tutor, ContentFixtures}

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter} =
      Courses.create_chapter(%{name: "Ch 1", position: 1, course_id: course.id})

    {:ok, section_weak} =
      Courses.create_section(%{name: "Fractions", position: 1, chapter_id: chapter.id})

    {:ok, section_strong} =
      Courses.create_section(%{name: "Addition", position: 2, chapter_id: chapter.id})

    # Weak-section fixture: 5 wrong out of 5 → deficit 1.0, well past 0.4 threshold.
    weak_qs =
      for i <- 1..5 do
        {:ok, q} =
          Questions.create_question(%{
            validation_status: :passed,
            content: "Fraction Q #{i}",
            answer: "A",
            question_type: :multiple_choice,
            difficulty: :medium,
            options: %{"A" => "a", "B" => "b"},
            course_id: course.id,
            chapter_id: chapter.id,
            section_id: section_weak.id,
            classification_status: :admin_reviewed
          })

        Questions.create_question_attempt(%{
          user_role_id: user_role.id,
          question_id: q.id,
          answer_given: "B",
          is_correct: false
        })

        q
      end

    # The "current" question the tutor is helping with.
    current_q = hd(weak_qs)

    %{
      user_role: user_role,
      course: course,
      chapter: chapter,
      section_weak: section_weak,
      section_strong: section_strong,
      current_q: Questions.get_question_with_context!(current_q.id)
    }
  end

  describe "build_context/3 — hobbies (I-12)" do
    test "includes the student's selected hobbies as a flat list", ctx do
      {:ok, hobby} =
        Learning.create_hobby(%{name: "KPOP", category: "music"})

      {:ok, _} =
        Learning.create_student_hobby(%{
          user_role_id: ctx.user_role.id,
          hobby_id: hobby.id
        })

      context = Tutor.build_context(ctx.current_q, ctx.course, ctx.user_role.id)

      assert "KPOP" in context.student.hobbies
    end

    test "returns empty list when the student has no hobbies set (I-15)", ctx do
      context = Tutor.build_context(ctx.current_q, ctx.course, ctx.user_role.id)
      assert context.student.hobbies == []
    end
  end

  describe "build_context/3 — weak skills (I-12)" do
    test "surfaces section names where the student is below mastery", ctx do
      context = Tutor.build_context(ctx.current_q, ctx.course, ctx.user_role.id)

      assert "Fractions" in context.student.weak_skills
      refute "Addition" in context.student.weak_skills
    end

    test "does not include skills with fewer than 2 attempts (I-15)", ctx do
      other_user = ContentFixtures.create_user_role()

      # One wrong attempt on section_strong isn't enough evidence.
      {:ok, q} =
        Questions.create_question(%{
          validation_status: :passed,
          content: "Strong Q 1",
          answer: "A",
          question_type: :multiple_choice,
          difficulty: :medium,
          options: %{"A" => "a", "B" => "b"},
          course_id: ctx.course.id,
          chapter_id: ctx.chapter.id,
          section_id: ctx.section_strong.id,
          classification_status: :admin_reviewed
        })

      Questions.create_question_attempt(%{
        user_role_id: other_user.id,
        question_id: q.id,
        answer_given: "B",
        is_correct: false
      })

      context = Tutor.build_context(ctx.current_q, ctx.course, other_user.id)
      refute "Addition" in context.student.weak_skills
    end
  end

  describe "system prompt explicitly opts into hobby-based analogies" do
    test "tutor attrs include the hobby instruction verbatim" do
      assert Tutor.assistant_attrs().system_prompt =~ "Personalization with Hobbies"
      assert Tutor.assistant_attrs().system_prompt =~ "hobbies"
      assert Tutor.assistant_attrs().system_prompt =~ "Weak Skills"
    end
  end
end
