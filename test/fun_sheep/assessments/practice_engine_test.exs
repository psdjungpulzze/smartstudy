defmodule FunSheep.Assessments.PracticeEngineTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Assessments.PracticeEngine
  alias FunSheep.{Questions, Courses}
  alias FunSheep.ContentFixtures

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter} =
      Courses.create_chapter(%{name: "Chapter 1", position: 1, course_id: course.id})

    {:ok, section} =
      Courses.create_section(%{name: "Sec 1", position: 1, chapter_id: chapter.id})

    {:ok, q1} =
      Questions.create_question(%{
        validation_status: :passed,
        content: "What is 2+2?",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{"A" => "4", "B" => "5", "C" => "6", "D" => "7"},
        course_id: course.id,
        chapter_id: chapter.id,
        section_id: section.id,
        classification_status: :admin_reviewed
      })

    {:ok, q2} =
      Questions.create_question(%{
        validation_status: :passed,
        content: "What is 3+3?",
        answer: "B",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{"A" => "5", "B" => "6", "C" => "7", "D" => "8"},
        course_id: course.id,
        chapter_id: chapter.id,
        section_id: section.id,
        classification_status: :admin_reviewed
      })

    # Create wrong attempts so these show as weak questions
    Questions.create_question_attempt(%{
      user_role_id: user_role.id,
      question_id: q1.id,
      answer_given: "B",
      is_correct: false
    })

    Questions.create_question_attempt(%{
      user_role_id: user_role.id,
      question_id: q2.id,
      answer_given: "A",
      is_correct: false
    })

    %{user_role: user_role, course: course, chapter: chapter, q1: q1, q2: q2}
  end

  describe "start_practice/3" do
    test "loads weak questions for the user and course", %{
      user_role: ur,
      course: course
    } do
      state = PracticeEngine.start_practice(ur.id, course.id)

      assert state.user_role_id == ur.id
      assert state.course_id == course.id
      assert state.status == :in_progress
      assert state.current_index == 0
      assert length(state.questions) == 2
    end

    test "filters by chapter when provided", %{
      user_role: ur,
      course: course,
      chapter: chapter
    } do
      state = PracticeEngine.start_practice(ur.id, course.id, %{chapter_id: chapter.id})
      assert length(state.questions) == 2
    end

    test "returns empty questions when no weak questions exist", %{course: course} do
      other_user = ContentFixtures.create_user_role()
      state = PracticeEngine.start_practice(other_user.id, course.id)
      assert state.questions == []
    end
  end

  describe "current_question/1" do
    test "returns the current question", %{user_role: ur, course: course} do
      state = PracticeEngine.start_practice(ur.id, course.id)
      {:question, question, _state} = PracticeEngine.current_question(state)

      assert question.content
    end

    test "returns :complete when all questions answered", %{user_role: ur, course: course} do
      state = PracticeEngine.start_practice(ur.id, course.id)
      # Advance past all questions
      state = %{state | current_index: length(state.questions)}
      {:complete, new_state} = PracticeEngine.current_question(state)

      assert new_state.status == :complete
    end
  end

  describe "record_answer/4" do
    test "advances index and records attempt", %{user_role: ur, course: course, q1: q1} do
      state = PracticeEngine.start_practice(ur.id, course.id)

      new_state = PracticeEngine.record_answer(state, q1.id, "A", true)

      assert new_state.current_index == 1
      assert length(new_state.attempts) == 1
      assert hd(new_state.attempts).is_correct == true
    end
  end

  describe "summary/1" do
    test "calculates correct statistics", %{user_role: ur, course: course, q1: q1, q2: q2} do
      state = PracticeEngine.start_practice(ur.id, course.id)

      state =
        state
        |> PracticeEngine.record_answer(q1.id, "A", true)
        |> PracticeEngine.record_answer(q2.id, "A", false)

      summary = PracticeEngine.summary(state)

      assert summary.total == 2
      assert summary.correct == 1
      assert summary.incorrect == 1
      assert summary.score == 50.0
    end

    test "returns zero score with no attempts", %{user_role: ur, course: course} do
      state = PracticeEngine.start_practice(ur.id, course.id)
      summary = PracticeEngine.summary(state)

      assert summary.total == 0
      assert summary.score == 0.0
    end
  end

  describe "full practice flow" do
    test "completes after answering all questions", %{user_role: ur, course: course} do
      state = PracticeEngine.start_practice(ur.id, course.id)
      question_count = length(state.questions)

      # Answer all questions
      state =
        Enum.reduce(state.questions, state, fn q, acc ->
          PracticeEngine.record_answer(acc, q.id, "A", true)
        end)

      {:complete, final_state} = PracticeEngine.current_question(state)
      summary = PracticeEngine.summary(final_state)

      assert summary.total == question_count
      assert summary.correct == question_count
      assert summary.score == 100.0
    end
  end
end
