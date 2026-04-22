defmodule FunSheep.TutorContextTest do
  @moduledoc """
  Tests the hobbies + weak-skills enrichments in `Tutor.build_context/3`
  for North Star I-12.
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

    current_q = Questions.get_question_with_context!(hd(weak_qs).id)

    %{
      user_role: user_role,
      course: course,
      chapter: chapter,
      section_weak: section_weak,
      section_strong: section_strong,
      current_q: current_q
    }
  end

  test "build_context includes student's hobbies as a flat list", ctx do
    {:ok, hobby} = Learning.create_hobby(%{name: "KPOP", category: "music"})
    {:ok, _} = Learning.create_student_hobby(%{user_role_id: ctx.user_role.id, hobby_id: hobby.id})

    context = Tutor.build_context(ctx.current_q, ctx.course, ctx.user_role.id)
    assert "KPOP" in context.student.hobbies
  end

  test "empty hobbies list when student has none set", ctx do
    context = Tutor.build_context(ctx.current_q, ctx.course, ctx.user_role.id)
    assert context.student.hobbies == []
  end

  test "build_context surfaces weak-skill section names", ctx do
    context = Tutor.build_context(ctx.current_q, ctx.course, ctx.user_role.id)
    assert "Fractions" in context.student.weak_skills
    refute "Addition" in context.student.weak_skills
  end

  test "system prompt explicitly references hobbies + weak skills" do
    attrs = Tutor.assistant_attrs()
    assert attrs.system_prompt =~ "Personalization with Hobbies"
    assert attrs.system_prompt =~ "Weak Skills"
  end
end
