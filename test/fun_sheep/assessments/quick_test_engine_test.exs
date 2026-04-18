defmodule FunSheep.Assessments.QuickTestEngineTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Assessments.QuickTestEngine
  alias FunSheep.{Questions, Courses}
  alias FunSheep.ContentFixtures

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter} =
      Courses.create_chapter(%{
        name: "Chapter 1",
        position: 1,
        course_id: course.id
      })

    {:ok, q1} =
      Questions.create_question(%{
        content: "What is 2+2?",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{"A" => "4", "B" => "5", "C" => "6", "D" => "7"},
        course_id: course.id,
        chapter_id: chapter.id
      })

    {:ok, q2} =
      Questions.create_question(%{
        content: "What is 3+3?",
        answer: "B",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{"A" => "5", "B" => "6", "C" => "7", "D" => "8"},
        course_id: course.id,
        chapter_id: chapter.id
      })

    {:ok, q3} =
      Questions.create_question(%{
        content: "Is the sky blue?",
        answer: "True",
        question_type: :true_false,
        difficulty: :easy,
        course_id: course.id,
        chapter_id: chapter.id
      })

    %{user_role: user_role, course: course, chapter: chapter, q1: q1, q2: q2, q3: q3}
  end

  describe "start_session/2" do
    test "loads questions for the user", %{user_role: ur} do
      state = QuickTestEngine.start_session(ur.id)

      assert state.user_role_id == ur.id
      assert state.status == :in_progress
      assert state.current_index == 0
      assert length(state.questions) == 3
    end

    test "filters by course when provided", %{user_role: ur, course: course} do
      state = QuickTestEngine.start_session(ur.id, %{course_id: course.id})
      assert length(state.questions) == 3
    end
  end

  describe "current_card/1" do
    test "returns the current card", %{user_role: ur} do
      state = QuickTestEngine.start_session(ur.id)
      {:card, question, _state} = QuickTestEngine.current_card(state)

      assert question.content
    end

    test "returns :complete when all cards processed", %{user_role: ur} do
      state = QuickTestEngine.start_session(ur.id)
      state = %{state | current_index: length(state.questions)}

      {:complete, final} = QuickTestEngine.current_card(state)
      assert final.status == :complete
    end
  end

  describe "mark_known/2" do
    test "records as correct and advances", %{user_role: ur, q1: q1} do
      state = QuickTestEngine.start_session(ur.id)
      new_state = QuickTestEngine.mark_known(state, q1.id)

      assert new_state.current_index == 1
      assert length(new_state.results) == 1

      result = hd(new_state.results)
      assert result.action == :know
      assert result.is_correct == true
    end
  end

  describe "mark_unknown/2" do
    test "records as incorrect and advances", %{user_role: ur, q1: q1} do
      state = QuickTestEngine.start_session(ur.id)
      new_state = QuickTestEngine.mark_unknown(state, q1.id)

      assert new_state.current_index == 1
      assert length(new_state.results) == 1

      result = hd(new_state.results)
      assert result.action == :dont_know
      assert result.is_correct == false
    end
  end

  describe "mark_answered/3" do
    test "records answered with correct result", %{user_role: ur, q1: q1} do
      state = QuickTestEngine.start_session(ur.id)
      new_state = QuickTestEngine.mark_answered(state, q1.id, true)

      result = hd(new_state.results)
      assert result.action == :answered
      assert result.is_correct == true
    end

    test "records answered with incorrect result", %{user_role: ur, q1: q1} do
      state = QuickTestEngine.start_session(ur.id)
      new_state = QuickTestEngine.mark_answered(state, q1.id, false)

      result = hd(new_state.results)
      assert result.action == :answered
      assert result.is_correct == false
    end
  end

  describe "skip/2" do
    test "advances without recording a result", %{user_role: ur, q1: q1} do
      state = QuickTestEngine.start_session(ur.id)
      new_state = QuickTestEngine.skip(state, q1.id)

      assert new_state.current_index == 1
      assert new_state.results == []
    end
  end

  describe "summary/1" do
    test "calculates accurate stats", %{user_role: ur, q1: q1, q2: q2, q3: q3} do
      state = QuickTestEngine.start_session(ur.id)

      state =
        state
        |> QuickTestEngine.mark_known(q1.id)
        |> QuickTestEngine.mark_unknown(q2.id)
        |> QuickTestEngine.mark_answered(q3.id, true)

      summary = QuickTestEngine.summary(state)

      assert summary.total == 3
      assert summary.known == 1
      assert summary.unknown == 1
      assert summary.answered_correct == 1
      assert summary.answered_wrong == 0
      # 2 correct out of 3 results
      assert summary.score == 66.7
    end

    test "handles empty session", %{user_role: ur} do
      state = QuickTestEngine.start_session(ur.id)
      summary = QuickTestEngine.summary(state)

      assert summary.score == 0.0
    end
  end

  describe "full session flow" do
    test "completes after processing all cards", %{user_role: ur} do
      state = QuickTestEngine.start_session(ur.id)

      # Process all cards with mark_known
      state =
        Enum.reduce(state.questions, state, fn q, acc ->
          QuickTestEngine.mark_known(acc, q.id)
        end)

      {:complete, final} = QuickTestEngine.current_card(state)
      summary = QuickTestEngine.summary(final)

      assert summary.total == 3
      assert summary.known == 3
      assert summary.score == 100.0
    end
  end
end
