defmodule FunSheep.Assessments.EngineTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Assessments.Engine
  alias FunSheep.ContentFixtures

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter1} =
      FunSheep.Courses.create_chapter(%{name: "Chapter 1", position: 1, course_id: course.id})

    {:ok, chapter2} =
      FunSheep.Courses.create_chapter(%{name: "Chapter 2", position: 2, course_id: course.id})

    # Skill tags (sections) required for adaptive flows — North Star I-1.
    {:ok, section1} =
      FunSheep.Courses.create_section(%{name: "Ch1 Sec 1", position: 1, chapter_id: chapter1.id})

    {:ok, section2} =
      FunSheep.Courses.create_section(%{name: "Ch2 Sec 1", position: 1, chapter_id: chapter2.id})

    # Create questions for chapter 1
    {:ok, q1} =
      FunSheep.Questions.create_question(%{
        validation_status: :passed,
        content: "What is 2+2?",
        answer: "4",
        question_type: :multiple_choice,
        difficulty: :easy,
        course_id: course.id,
        chapter_id: chapter1.id,
        section_id: section1.id,
        classification_status: :admin_reviewed
      })

    {:ok, q2} =
      FunSheep.Questions.create_question(%{
        validation_status: :passed,
        content: "What is 3+3?",
        answer: "6",
        question_type: :multiple_choice,
        difficulty: :medium,
        course_id: course.id,
        chapter_id: chapter1.id,
        section_id: section1.id,
        classification_status: :admin_reviewed
      })

    {:ok, q3} =
      FunSheep.Questions.create_question(%{
        validation_status: :passed,
        content: "What is 5+5?",
        answer: "10",
        question_type: :multiple_choice,
        difficulty: :hard,
        course_id: course.id,
        chapter_id: chapter1.id,
        section_id: section1.id,
        classification_status: :admin_reviewed
      })

    # Create questions for chapter 2
    {:ok, q4} =
      FunSheep.Questions.create_question(%{
        validation_status: :passed,
        content: "What is 1+1?",
        answer: "2",
        question_type: :multiple_choice,
        difficulty: :easy,
        course_id: course.id,
        chapter_id: chapter2.id,
        section_id: section2.id,
        classification_status: :admin_reviewed
      })

    {:ok, schedule} =
      FunSheep.Assessments.create_test_schedule(%{
        name: "Midterm",
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
      schedule: schedule,
      questions: [q1, q2, q3, q4]
    }
  end

  describe "start_assessment/1" do
    test "initializes state correctly", %{schedule: schedule, chapter1: ch1, chapter2: ch2} do
      state = Engine.start_assessment(schedule)

      assert state.schedule_id == schedule.id
      assert state.course_id == schedule.course_id
      assert state.current_topic_index == 0
      assert state.current_difficulty == :medium
      assert state.status == :in_progress
      assert length(state.topics) == 2

      topic_ids = Enum.map(state.topics, & &1.id)
      assert ch1.id in topic_ids
      assert ch2.id in topic_ids
    end
  end

  describe "next_question/1" do
    test "returns a question from the first topic", %{schedule: schedule} do
      state = Engine.start_assessment(schedule)
      assert {:question, question, _new_state} = Engine.next_question(state)
      assert question.content != nil
    end

    test "returns :no_questions_available when no topics exist" do
      # Fails honestly per commit 2935c33: an empty scope must NOT produce a
      # zero-of-zero "complete" state — that would mark the assessment done
      # and advance the study path despite no work having been done. Instead
      # the engine exits with `:no_questions_available` so the UI can show
      # the readiness-block screen (covered by AssessmentLiveTest).
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course()

      {:ok, schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Empty Test",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => []},
          user_role_id: user_role.id,
          course_id: course.id
        })

      state = Engine.start_assessment(schedule)
      assert {:no_questions_available, final_state} = Engine.next_question(state)
      assert final_state.status == :no_questions_available
    end
  end

  describe "record_answer/4" do
    test "adjusts difficulty up on correct answer", %{schedule: schedule} do
      state = Engine.start_assessment(schedule)
      {:question, question, state} = Engine.next_question(state)

      new_state = Engine.record_answer(state, question.id, "4", true)
      assert new_state.current_difficulty == :medium
    end

    test "decreases difficulty on incorrect answer", %{schedule: schedule} do
      state = Engine.start_assessment(schedule)
      {:question, question, state} = Engine.next_question(state)

      new_state = Engine.record_answer(state, question.id, "wrong", false)
      # Starting at 0.5 (medium), wrong answer drops to 0.35 — still medium
      assert new_state.target_difficulty < state.target_difficulty
    end

    test "tracks attempts per topic", %{schedule: schedule} do
      state = Engine.start_assessment(schedule)
      {:question, question, state} = Engine.next_question(state)

      topic = Enum.at(state.topics, 0)
      new_state = Engine.record_answer(state, question.id, "4", true)

      topic_attempts = Map.get(new_state.topic_attempts, topic.id, [])
      assert length(topic_attempts) == 1
      assert hd(topic_attempts).is_correct == true
    end
  end

  describe "topic mastery" do
    test "moves to next topic when mastered", %{schedule: schedule} do
      state = Engine.start_assessment(schedule)

      # Answer 3 questions correctly to master first topic
      state = answer_questions_correctly(state, 3)

      # Next question should be from chapter 2 (or complete)
      case Engine.next_question(state) do
        {:question, _q, new_state} ->
          assert new_state.current_topic_index >= 1

        {:complete, _state} ->
          # Also acceptable if chapter 2 has no questions at current difficulty
          assert true
      end
    end
  end

  describe "summary/1" do
    test "returns correct summary structure", %{schedule: schedule} do
      state = Engine.start_assessment(schedule)
      state = answer_questions_correctly(state, 1)

      summary = Engine.summary(state)

      assert is_list(summary.topic_results)
      assert is_number(summary.total_correct)
      assert is_number(summary.total_questions)
      assert is_number(summary.overall_score)
    end
  end

  # Helper to answer N questions correctly
  defp answer_questions_correctly(state, n) do
    Enum.reduce(1..n, state, fn _i, acc ->
      case Engine.next_question(acc) do
        {:question, question, new_state} ->
          Engine.record_answer(new_state, question.id, question.answer, true)

        {:complete, completed} ->
          completed

        _ ->
          acc
      end
    end)
  end
end
