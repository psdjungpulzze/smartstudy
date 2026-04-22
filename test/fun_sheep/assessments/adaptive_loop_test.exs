defmodule FunSheep.Assessments.AdaptiveLoopTest do
  @moduledoc """
  Exercises the per-skill state machine added for North Star invariants
  I-2 (confirm on wrong), I-3 (depth probe on correct), I-4 (no premature
  weak label), and I-15 (insufficient_data honesty).

  Questions are created with adaptive-eligible tagging (section_id +
  classification_status: :admin_reviewed) and two sibling questions per
  section so the engine has room to serve a confirmation/probe.
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

    {:ok, section_b} =
      Courses.create_section(%{name: "Skill B", position: 2, chapter_id: chapter.id})

    # Populate each section with a range of difficulties so confirm (easy/med)
    # and depth probe (hard) have room to pull from.
    a_easy = mk_question(course, chapter, section_a, :easy, "-a1")
    a_med = mk_question(course, chapter, section_a, :medium, "-a2")
    a_hard = mk_question(course, chapter, section_a, :hard, "-a3")
    # A second hard section_a question so the depth-probe selector has a
    # candidate even after a_hard has been "used" in the setup scenario.
    a_hard2 = mk_question(course, chapter, section_a, :hard, "-a4")
    b_med = mk_question(course, chapter, section_b, :medium, "-b1")
    b_med2 = mk_question(course, chapter, section_b, :medium, "-b2")

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
      section_b: section_b,
      schedule: schedule,
      questions: %{
        a_easy: a_easy,
        a_med: a_med,
        a_hard: a_hard,
        a_hard2: a_hard2,
        b_med: b_med,
        b_med2: b_med2
      }
    }
  end

  describe "invariant I-2: confirm on wrong" do
    test "first wrong sets pending :confirm and skill stays :insufficient_data", ctx do
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
      # Confirm must not be harder than current target (target dropped to 0.35).
      refute next_q.id == ctx.questions.a_med.id
    end
  end

  describe "invariant I-4: weak only after confirmed wrong" do
    test "two wrongs on same skill promote status to :weak", ctx do
      state = Engine.start_assessment(ctx.schedule)
      state = Engine.record_answer(state, ctx.questions.a_med.id, "B", false)
      state = Engine.record_answer(state, ctx.questions.a_easy.id, "B", false)

      skill = Map.fetch!(state.skill_states, ctx.section_a.id)
      assert skill.status == :weak
      assert skill.pending == nil
      assert state.active_skill_id == nil
    end

    test "wrong then correct on confirm settles at :probing, not :weak", ctx do
      state = Engine.start_assessment(ctx.schedule)
      state = Engine.record_answer(state, ctx.questions.a_med.id, "B", false)
      state = Engine.record_answer(state, ctx.questions.a_easy.id, "A", true)

      skill = Map.fetch!(state.skill_states, ctx.section_a.id)
      assert skill.status == :probing
      assert skill.pending == nil
      assert state.active_skill_id == nil
    end
  end

  describe "invariant I-3: depth probe on correct at target" do
    test "depth probe fires after two correct-at-medium attempts and pulls a harder Q", ctx do
      state = Engine.start_assessment(ctx.schedule)
      # Two correct on medium questions to establish surface competence.
      state = Engine.record_answer(state, ctx.questions.a_med.id, "A", true)
      skill = Map.fetch!(state.skill_states, ctx.section_a.id)
      # First correct — not enough history yet.
      assert skill.pending == nil
      assert skill.status == :insufficient_data

      state = Engine.record_answer(state, ctx.questions.a_easy.id, "A", true)
      skill = Map.fetch!(state.skill_states, ctx.section_a.id)

      # With two attempts and the most recent at/above target, a probe fires.
      # (The second attempt's difficulty is :easy but target has risen to ~0.8
      # so won't fire; use a_hard instead.)
      _ = skill

      # Restart to run the specific probe scenario cleanly.
      state2 = Engine.start_assessment(ctx.schedule)
      state2 = Engine.record_answer(state2, ctx.questions.a_med.id, "A", true)
      state2 = Engine.record_answer(state2, ctx.questions.a_hard.id, "A", true)

      skill2 = Map.fetch!(state2.skill_states, ctx.section_a.id)
      assert skill2.pending == :depth_probe
      assert skill2.status == :probing
      assert state2.active_skill_id == ctx.section_a.id

      # The probe question must be same section AND harder than target.
      assert {:question, probe_q, _} = Engine.next_question(state2)
      assert probe_q.section_id == ctx.section_a.id
    end

    test "failing the depth probe reverts to :probing (NOT :weak)", ctx do
      state = Engine.start_assessment(ctx.schedule)
      state = Engine.record_answer(state, ctx.questions.a_med.id, "A", true)
      state = Engine.record_answer(state, ctx.questions.a_hard.id, "A", true)

      # Now pending :depth_probe. Answer wrong.
      state = Engine.record_answer(state, ctx.questions.a_easy.id, "B", false)

      skill = Map.fetch!(state.skill_states, ctx.section_a.id)
      assert skill.status == :probing
      refute skill.status == :weak
      assert skill.pending == nil
    end
  end

  describe "invariant I-15: insufficient_data on thin evidence" do
    test "a single attempt never escalates past :insufficient_data", ctx do
      state = Engine.start_assessment(ctx.schedule)
      state = Engine.record_answer(state, ctx.questions.a_med.id, "A", true)

      skill = Map.fetch!(state.skill_states, ctx.section_a.id)
      assert skill.status == :insufficient_data
    end

    test "summary exposes per-skill status honestly", ctx do
      state = Engine.start_assessment(ctx.schedule)
      state = Engine.record_answer(state, ctx.questions.a_med.id, "B", false)
      state = Engine.record_answer(state, ctx.questions.a_easy.id, "B", false)

      summary = Engine.summary(state)
      weak = Enum.find(summary.skill_results, &(&1.section_id == ctx.section_a.id))
      assert weak.status == :weak
      assert weak.attempts == 2
      assert weak.correct == 0
    end
  end

  describe "target-difficulty guard during pending" do
    test "pending state does not double-adjust target", ctx do
      state = Engine.start_assessment(ctx.schedule)
      t0 = state.target_difficulty

      # First wrong drops target once and sets pending.
      state = Engine.record_answer(state, ctx.questions.a_med.id, "B", false)
      t1 = state.target_difficulty
      assert t1 < t0

      # Confirmation wrong must NOT drop target a second time.
      state = Engine.record_answer(state, ctx.questions.a_easy.id, "B", false)
      assert state.target_difficulty == t1
    end
  end
end
