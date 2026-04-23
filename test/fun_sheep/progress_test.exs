defmodule FunSheep.ProgressTest do
  use ExUnit.Case, async: true

  alias FunSheep.Progress
  alias FunSheep.Progress.Event

  describe "topic/2" do
    test "builds a stable topic string per subject type + id" do
      assert Progress.topic(:course, "abc") == "progress:course:abc"
      assert Progress.topic(:import, 42) == "progress:import:42"
    end
  end

  describe "Event.new/1" do
    test "builds a queued event with required fields" do
      e =
        Event.new(
          job_id: "j1",
          topic_type: :course,
          topic_id: "c1",
          scope: :question_regeneration,
          phase_total: 3,
          subject_id: "ch1",
          subject_label: "Chapter 1"
        )

      assert e.job_id == "j1"
      assert e.topic_type == :course
      assert e.topic_id == "c1"
      assert e.scope == :question_regeneration
      assert e.phase == :queued
      assert e.phase_index == 0
      assert e.phase_total == 3
      assert e.status == :queued
      assert e.progress == %{current: 0, total: nil, unit: ""}
      assert e.subject_id == "ch1"
      assert e.subject_label == "Chapter 1"
    end

    test "raises when required opts are missing" do
      assert_raise KeyError, fn ->
        Event.new(scope: :x, phase_total: 1)
      end
    end
  end

  describe "terminal?/1" do
    test "true for terminal statuses" do
      base = base_event()
      assert Event.terminal?(%{base | status: :succeeded})
      assert Event.terminal?(%{base | status: :failed})
      assert Event.terminal?(%{base | status: :partial})
    end

    test "false for non-terminal statuses" do
      base = base_event()
      refute Event.terminal?(%{base | status: :queued})
      refute Event.terminal?(%{base | status: :running})
    end
  end

  describe "broadcasts" do
    setup do
      :ok = Progress.subscribe(:course, "course-broadcast-test")
      :ok
    end

    test "phase/4 broadcasts and returns the updated event" do
      base = base_event()

      returned = Progress.phase(base, :preparing, "Preparing", 1)

      assert %Event{} = returned
      assert returned.phase == :preparing
      assert returned.phase_label == "Preparing"
      assert returned.phase_index == 1
      assert returned.status == :running

      assert_receive {:progress, %Event{} = e}
      assert e == returned
    end

    test "tick carries the current phase metadata from the last phase/4 call" do
      # Regression for the v1 bug caught in visual testing: tick/4 was
      # broadcasting stale phase fields from the original :queued base,
      # causing the UI to flip back to "Step 0 of 3 / Queued" on every tick
      # during the :saving phase.
      base = base_event()
      after_phase = Progress.phase(base, :saving, "Saving questions", 3)
      flush_inbox()

      ticked = Progress.tick(after_phase, 7, 10, "questions")

      assert_receive {:progress, %Event{} = e}
      assert e.phase == :saving
      assert e.phase_label == "Saving questions"
      assert e.phase_index == 3
      assert e.progress == %{current: 7, total: 10, unit: "questions"}
      assert e.status == :running
      assert e == ticked
    end

    test "succeeded/3 broadcasts and returns a terminal event" do
      base = base_event()
      returned = Progress.succeeded(base, "questions", 18)

      assert returned.status == :succeeded
      assert returned.phase == :done
      assert returned.progress == %{current: 18, total: 18, unit: "questions"}

      assert_receive {:progress, %Event{} = e}
      assert e == returned
    end

    test "failed/3 broadcasts and returns a terminal failure with code & message" do
      base = base_event()
      returned = Progress.failed(base, :ai_unavailable, "AI service unavailable")

      assert returned.status == :failed
      assert returned.phase == :failed
      assert returned.error == %{code: :ai_unavailable, message: "AI service unavailable"}

      assert_receive {:progress, %Event{} = e}
      assert e == returned
    end
  end

  defp flush_inbox do
    receive do
      _ -> flush_inbox()
    after
      0 -> :ok
    end
  end

  defp base_event do
    Event.new(
      job_id: "j1",
      topic_type: :course,
      topic_id: "course-broadcast-test",
      scope: :question_regeneration,
      phase_total: 3,
      subject_id: "ch1",
      subject_label: "Chapter 1"
    )
  end
end
