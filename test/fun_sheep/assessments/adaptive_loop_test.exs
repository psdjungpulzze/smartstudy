defmodule FunSheep.Assessments.AdaptiveLoopTest do
  @moduledoc """
  Exercises the per-skill state machine for North Star I-2, I-3, I-4, I-15.
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.Assessments.Engine
  alias FunSheep.{Courses, Questions, ContentFixtures}

  defp mk_question(course, chapter, section, difficulty, suffix) do
    {:ok, q} =
      Questions.create_question(%{
        validation_status: :passed,
        content: "Q-#{difficulty}#{suffix}",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: difficulty,
        options: %{"A" => "a", "B" => "b"},
        course_id: course.id,
        chapter_id: chapter.id,
        section_id: section.id,
        classification_status: :admin_reviewed
      })

    q
  end

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter} =
      Courses.create_chapter(%{name: "Ch 1", position: 1, course_id: course.id})

    {:ok, section_a} =
      Courses.create_section(%{name: "Skill A", position: 1, chapter_id: chapter.id})

    a_easy = mk_question(course, chapter, section_a, :easy, "-a1")
    a_med = mk_question(course, chapter, section_a, :medium, "-a2")
    a_hard = mk_question(course, chapter, section_a, :hard, "-a3")
    _a_hard2 = mk_question(course, chapter, section_a, :hard, "-a4")

    {:ok, schedule} =
      FunSheep.Assessments.create_test_schedule(%{
        name: "Adaptive Loop",
        test_date: Date.add(Date.utc_today(), 7),
        scope: %{"chapter_ids" => [chapter.id]},
        user_role_id: user_role.id,
        course_id: course.id
      })

    %{
      user_role: user_role,
      course: course,
      chapter: chapter,
      section_a: section_a,
      schedule: schedule,
      questions: %{a_easy: a_easy, a_med: a_med, a_hard: a_hard}
    }
  end

  describe "I-2: confirm on wrong" do
    test "first wrong sets pending :confirm; skill :insufficient_data", ctx do
      state = Engine.start_assessment(ctx.schedule)
      state = Engine.record_answer(state, ctx.questions.a_med.id, "B", false)

      skill = Map.fetch!(state.skill_states, ctx.section_a.id)
      assert skill.pending == :confirm
      assert skill.status == :insufficient_data
      assert state.active_skill_id == ctx.section_a.id
    end

    test "next question after a wrong comes from the same section", ctx do
      state = Engine.start_assessment(ctx.schedule)
      state = Engine.record_answer(state, ctx.questions.a_med.id, "B", false)

      assert {:question, next_q, _state} = Engine.next_question(state)
      assert next_q.section_id == ctx.section_a.id
      refute next_q.id == ctx.questions.a_med.id
    end
  end

  describe "I-4: weak only after confirmed wrong" do
    test "two wrongs on same skill -> :weak", ctx do
      state = Engine.start_assessment(ctx.schedule)
      state = Engine.record_answer(state, ctx.questions.a_med.id, "B", false)
      state = Engine.record_answer(state, ctx.questions.a_easy.id, "B", false)

      skill = Map.fetch!(state.skill_states, ctx.section_a.id)
      assert skill.status == :weak
      assert skill.pending == nil
    end

    test "wrong then correct -> :probing, NOT :weak", ctx do
      state = Engine.start_assessment(ctx.schedule)
      state = Engine.record_answer(state, ctx.questions.a_med.id, "B", false)
      state = Engine.record_answer(state, ctx.questions.a_easy.id, "A", true)

      skill = Map.fetch!(state.skill_states, ctx.section_a.id)
      assert skill.status == :probing
      assert skill.pending == nil
    end
  end

  describe "I-3: depth probe" do
    test "depth probe fires after two correct-at-medium+ answers", ctx do
      state = Engine.start_assessment(ctx.schedule)
      state = Engine.record_answer(state, ctx.questions.a_med.id, "A", true)
      state = Engine.record_answer(state, ctx.questions.a_hard.id, "A", true)

      skill = Map.fetch!(state.skill_states, ctx.section_a.id)
      assert skill.pending == :depth_probe
      assert skill.status == :probing

      assert {:question, probe_q, _} = Engine.next_question(state)
      assert probe_q.section_id == ctx.section_a.id
    end

    test "failed depth probe reverts to :probing (NOT :weak)", ctx do
      state = Engine.start_assessment(ctx.schedule)
      state = Engine.record_answer(state, ctx.questions.a_med.id, "A", true)
      state = Engine.record_answer(state, ctx.questions.a_hard.id, "A", true)
      state = Engine.record_answer(state, ctx.questions.a_easy.id, "B", false)

      skill = Map.fetch!(state.skill_states, ctx.section_a.id)
      assert skill.status == :probing
      refute skill.status == :weak
      assert skill.pending == nil
    end
  end

  describe "I-15: honest insufficient data" do
    test "a single attempt stays :insufficient_data", ctx do
      state = Engine.start_assessment(ctx.schedule)
      state = Engine.record_answer(state, ctx.questions.a_med.id, "A", true)

      skill = Map.fetch!(state.skill_states, ctx.section_a.id)
      assert skill.status == :insufficient_data
    end

    test "summary exposes per-skill status", ctx do
      state = Engine.start_assessment(ctx.schedule)
      state = Engine.record_answer(state, ctx.questions.a_med.id, "B", false)
      state = Engine.record_answer(state, ctx.questions.a_easy.id, "B", false)

      summary = Engine.summary(state)
      weak = Enum.find(summary.skill_results, &(&1.section_id == ctx.section_a.id))
      assert weak.status == :weak
      assert weak.attempts == 2
    end
  end

  describe "target-difficulty guard during pending" do
    test "pending state does not double-adjust target", ctx do
      state = Engine.start_assessment(ctx.schedule)
      t0 = state.target_difficulty

      state = Engine.record_answer(state, ctx.questions.a_med.id, "B", false)
      t1 = state.target_difficulty
      assert t1 < t0

      state = Engine.record_answer(state, ctx.questions.a_easy.id, "B", false)
      assert state.target_difficulty == t1
    end
  end
end
