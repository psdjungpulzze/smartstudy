defmodule FunSheep.Assessments.SessionStoreTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Assessments.SessionStore

  @user_role_id Ecto.UUID.generate()
  @schedule_id Ecto.UUID.generate()

  describe "save/3 + load/2 round-trip" do
    test "persists and rehydrates a plain engine state" do
      state = %{
        engine_state: %{
          schedule_id: @schedule_id,
          course_id: "course-1",
          current_topic_index: 0,
          topics: [%{id: "ch-1", name: "Chapter 1"}],
          target_difficulty: 0.5,
          current_difficulty: :medium,
          topic_attempts: %{},
          skill_states: %{},
          active_skill_id: nil,
          status: :in_progress
        },
        question_number: 3,
        phase: :testing,
        selected_answer: "A",
        assessment_complete: false
      }

      assert :ok = SessionStore.save(@user_role_id, @schedule_id, state)
      assert {:ok, loaded} = SessionStore.load(@user_role_id, @schedule_id)

      assert loaded.question_number == 3
      assert loaded.phase == :testing
      assert loaded.selected_answer == "A"
      assert loaded.assessment_complete == false
      assert loaded.engine_state.schedule_id == @schedule_id
      # Atom values survive only as strings after JSON round-trip; only keys
      # are rehydrated as atoms (`keys: :atoms!`).
      assert loaded.engine_state.current_difficulty == "medium"
    end

    test "load/2 returns :miss when no record exists" do
      assert :miss = SessionStore.load(Ecto.UUID.generate(), Ecto.UUID.generate())
    end

    test "save/3 upserts on (user_role_id, schedule_id)" do
      SessionStore.save(@user_role_id, @schedule_id, %{phase: :testing, question_number: 1})
      SessionStore.save(@user_role_id, @schedule_id, %{phase: :testing, question_number: 42})

      assert {:ok, loaded} = SessionStore.load(@user_role_id, @schedule_id)
      assert loaded.question_number == 42
    end
  end

  describe "delete/2" do
    test "removes a persisted session" do
      SessionStore.save(@user_role_id, @schedule_id, %{phase: :testing})
      assert {:ok, _} = SessionStore.load(@user_role_id, @schedule_id)

      assert :ok = SessionStore.delete(@user_role_id, @schedule_id)
      assert :miss = SessionStore.load(@user_role_id, @schedule_id)
    end

    test "is idempotent when no record exists" do
      assert :ok = SessionStore.delete(Ecto.UUID.generate(), Ecto.UUID.generate())
    end
  end
end
