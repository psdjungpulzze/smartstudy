defmodule FunSheep.Assessments.ExamSimulationEngineTest do
  use ExUnit.Case, async: true

  alias FunSheep.Assessments.ExamSimulationEngine

  describe "remaining_seconds/1" do
    test "returns positive value for a fresh session" do
      state = %{
        time_limit_seconds: 2700,
        started_at: DateTime.utc_now(:second)
      }

      assert ExamSimulationEngine.remaining_seconds(state) > 0
    end

    test "returns negative for an expired session" do
      state = %{
        time_limit_seconds: 1,
        started_at: DateTime.add(DateTime.utc_now(:second), -60, :second)
      }

      assert ExamSimulationEngine.remaining_seconds(state) < 0
    end

    test "counts down over time" do
      state = %{
        time_limit_seconds: 100,
        started_at: DateTime.add(DateTime.utc_now(:second), -10, :second)
      }

      remaining = ExamSimulationEngine.remaining_seconds(state)
      assert remaining >= 89 && remaining <= 91
    end
  end

  describe "answered_count/1" do
    test "counts only questions with non-nil, non-empty answers" do
      state = %{
        question_ids_order: ["q1", "q2", "q3"],
        answers: %{
          "q1" => %{"answer" => "A"},
          "q2" => %{"answer" => nil},
          "q3" => %{}
        }
      }

      assert ExamSimulationEngine.answered_count(state) == 1
    end

    test "counts empty-string answers as unanswered" do
      state = %{
        question_ids_order: ["q1", "q2"],
        answers: %{
          "q1" => %{"answer" => ""},
          "q2" => %{"answer" => "B"}
        }
      }

      assert ExamSimulationEngine.answered_count(state) == 1
    end

    test "returns 0 for empty answers map" do
      state = %{question_ids_order: ["q1", "q2"], answers: %{}}
      assert ExamSimulationEngine.answered_count(state) == 0
    end

    test "returns 0 for no questions" do
      state = %{question_ids_order: [], answers: %{}}
      assert ExamSimulationEngine.answered_count(state) == 0
    end
  end

  describe "unanswered_count/1" do
    test "returns total minus answered" do
      state = %{
        question_ids_order: ["q1", "q2", "q3"],
        answers: %{"q1" => %{"answer" => "A"}}
      }

      assert ExamSimulationEngine.unanswered_count(state) == 2
    end

    test "returns 0 when all answered" do
      state = %{
        question_ids_order: ["q1", "q2"],
        answers: %{
          "q1" => %{"answer" => "A"},
          "q2" => %{"answer" => "B"}
        }
      }

      assert ExamSimulationEngine.unanswered_count(state) == 0
    end
  end

  describe "question_ids_for_section/2" do
    test "returns correct slice for the first section" do
      state = %{
        question_ids_order: ["q1", "q2", "q3", "q4", "q5"],
        section_boundaries: [
          %{
            "name" => "A",
            "start_index" => 0,
            "question_count" => 2,
            "time_budget_seconds" => 600
          },
          %{
            "name" => "B",
            "start_index" => 2,
            "question_count" => 3,
            "time_budget_seconds" => 900
          }
        ]
      }

      assert ExamSimulationEngine.question_ids_for_section(state, 0) == ["q1", "q2"]
    end

    test "returns correct slice for the second section" do
      state = %{
        question_ids_order: ["q1", "q2", "q3", "q4", "q5"],
        section_boundaries: [
          %{
            "name" => "A",
            "start_index" => 0,
            "question_count" => 2,
            "time_budget_seconds" => 600
          },
          %{
            "name" => "B",
            "start_index" => 2,
            "question_count" => 3,
            "time_budget_seconds" => 900
          }
        ]
      }

      assert ExamSimulationEngine.question_ids_for_section(state, 1) == ["q3", "q4", "q5"]
    end

    test "returns empty list for out-of-range section" do
      state = %{
        question_ids_order: ["q1"],
        section_boundaries: [
          %{"name" => "A", "start_index" => 0, "question_count" => 1, "time_budget_seconds" => 60}
        ]
      }

      assert ExamSimulationEngine.question_ids_for_section(state, 5) == []
    end
  end

  describe "section_for_question/2" do
    setup do
      state = %{
        question_ids_order: ["q1", "q2", "q3"],
        section_boundaries: [
          %{
            "name" => "A",
            "start_index" => 0,
            "question_count" => 2,
            "time_budget_seconds" => 600
          },
          %{
            "name" => "B",
            "start_index" => 2,
            "question_count" => 1,
            "time_budget_seconds" => 300
          }
        ]
      }

      {:ok, state: state}
    end

    test "returns index 0 for a question in section A", %{state: state} do
      {si, sec} = ExamSimulationEngine.section_for_question(state, "q1")
      assert si == 0
      assert sec["name"] == "A"
    end

    test "returns index 1 for a question in section B", %{state: state} do
      {si, sec} = ExamSimulationEngine.section_for_question(state, "q3")
      assert si == 1
      assert sec["name"] == "B"
    end

    test "defaults to section 0 for unknown question", %{state: state} do
      {si, _} = ExamSimulationEngine.section_for_question(state, "unknown")
      assert si == 0
    end
  end

  describe "question_at/2" do
    test "returns the question at the given flat index" do
      q1 = %{id: "q1", content: "Q1"}
      q2 = %{id: "q2", content: "Q2"}

      state = %{
        question_ids_order: ["q1", "q2"],
        questions: [q1, q2]
      }

      assert ExamSimulationEngine.question_at(state, 0) == q1
      assert ExamSimulationEngine.question_at(state, 1) == q2
    end

    test "returns nil for out-of-range index" do
      state = %{question_ids_order: ["q1"], questions: [%{id: "q1"}]}
      assert ExamSimulationEngine.question_at(state, 5) == nil
    end
  end
end
