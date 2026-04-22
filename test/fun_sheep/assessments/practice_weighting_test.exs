defmodule FunSheep.Assessments.PracticeWeightingTest do
  @moduledoc """
  Per-skill weighting (I-5), deliberate interleaving (I-6), and mid-session
  re-ranking (I-7).
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.Assessments.PracticeEngine
  alias FunSheep.{Courses, Questions, ContentFixtures}

  defp mk_question(course, chapter, section, content) do
    {:ok, q} =
      Questions.create_question(%{
        validation_status: :passed,
        content: content,
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :medium,
        options: %{"A" => "a", "B" => "b"},
        course_id: course.id,
        chapter_id: chapter.id,
        section_id: section.id,
        classification_status: :admin_reviewed
      })

    q
  end

  defp record_wrong(user_role, question) do
    {:ok, _} =
      Questions.create_question_attempt(%{
        user_role_id: user_role.id,
        question_id: question.id,
        answer_given: "B",
        is_correct: false
      })
  end

  defp record_correct(user_role, question) do
    {:ok, _} =
      Questions.create_question_attempt(%{
        user_role_id: user_role.id,
        question_id: question.id,
        answer_given: "A",
        is_correct: true
      })
  end

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter} =
      Courses.create_chapter(%{name: "Ch 1", position: 1, course_id: course.id})

    {:ok, weak_section} =
      Courses.create_section(%{name: "Weak Skill", position: 1, chapter_id: chapter.id})

    {:ok, mastered_section} =
      Courses.create_section(%{name: "Mastered Skill", position: 2, chapter_id: chapter.id})

    weak_qs =
      for i <- 1..6 do
        q = mk_question(course, chapter, weak_section, "weak-#{i}")
        record_wrong(user_role, q)
        q
      end

    mastered_qs =
      for i <- 1..4 do
        q = mk_question(course, chapter, mastered_section, "mastered-#{i}")
        record_correct(user_role, q)
        q
      end

    %{
      user_role: user_role,
      course: course,
      weak_section: weak_section,
      mastered_section: mastered_section,
      weak_qs: weak_qs,
      mastered_qs: mastered_qs
    }
  end

  describe "I-5: weighting by per-skill deficit" do
    test "deficits populated per-section", ctx do
      state = PracticeEngine.start_practice(ctx.user_role.id, ctx.course.id)

      assert state.skill_deficits[ctx.weak_section.id].deficit == 1.0
      assert state.skill_deficits[ctx.mastered_section.id].deficit == 0.0
    end

    test "no interleave -> only weak questions", ctx do
      state =
        PracticeEngine.start_practice(ctx.user_role.id, ctx.course.id, %{
          limit: 3,
          interleave_ratio: 0.0
        })

      weak_ids = MapSet.new(ctx.weak_qs, & &1.id)

      assert length(state.questions) > 0

      Enum.each(state.questions, fn q ->
        assert MapSet.member?(weak_ids, q.id)
      end)
    end
  end

  describe "I-6: deliberate interleaving" do
    test "session includes both weak + review at configured ratio", ctx do
      state =
        PracticeEngine.start_practice(ctx.user_role.id, ctx.course.id, %{
          limit: 4,
          interleave_ratio: 0.5
        })

      weak_ids = MapSet.new(ctx.weak_qs, & &1.id)
      mastered_ids = MapSet.new(ctx.mastered_qs, & &1.id)

      {weak, mastered} =
        Enum.split_with(state.questions, fn q -> MapSet.member?(weak_ids, q.id) end)

      assert length(weak) >= 1
      assert length(mastered) >= 1

      Enum.each(mastered, fn q -> assert MapSet.member?(mastered_ids, q.id) end)
    end

    test "no review questions when ratio is 0", ctx do
      state =
        PracticeEngine.start_practice(ctx.user_role.id, ctx.course.id, %{
          limit: 4,
          interleave_ratio: 0.0
        })

      mastered_ids = MapSet.new(ctx.mastered_qs, & &1.id)

      Enum.each(state.questions, fn q -> refute MapSet.member?(mastered_ids, q.id) end)
    end

    test "empty session when no weak skills exist", ctx do
      fresh = ContentFixtures.create_user_role()
      state = PracticeEngine.start_practice(fresh.id, ctx.course.id)
      assert state.questions == []
    end
  end

  describe "I-7: mid-session re-rank" do
    test "deficit updates after an answer", ctx do
      state =
        PracticeEngine.start_practice(ctx.user_role.id, ctx.course.id, %{
          limit: 4,
          interleave_ratio: 0.0
        })

      assert state.skill_deficits[ctx.weak_section.id].deficit == 1.0
      first = hd(state.questions)
      state = PracticeEngine.record_answer(state, first.id, "A", true)

      new_deficit = state.skill_deficits[ctx.weak_section.id].deficit
      assert new_deficit < 1.0
      assert state.skill_deficits[ctx.weak_section.id].correct == 1
    end

    test "answered question excluded from the re-ranked tail", ctx do
      state =
        PracticeEngine.start_practice(ctx.user_role.id, ctx.course.id, %{
          limit: 4,
          interleave_ratio: 0.0
        })

      first = hd(state.questions)
      state = PracticeEngine.record_answer(state, first.id, "A", true)

      tail = Enum.drop(state.questions, state.current_index)
      refute Enum.any?(tail, &(&1.id == first.id))
    end
  end
end
