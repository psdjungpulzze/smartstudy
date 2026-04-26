defmodule FunSheep.Assessments.ExamSimulationsTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Assessments.{ExamSimulations, ExamSimulationSession}

  describe "changeset/2" do
    test "valid with all required fields" do
      cs =
        ExamSimulationSession.changeset(%ExamSimulationSession{}, %{
          user_role_id: Ecto.UUID.generate(),
          course_id: Ecto.UUID.generate(),
          time_limit_seconds: 2700,
          started_at: DateTime.utc_now(:second),
          question_ids_order: []
        })

      assert cs.valid?
    end

    test "invalid without time_limit_seconds" do
      cs =
        ExamSimulationSession.changeset(%ExamSimulationSession{}, %{
          user_role_id: Ecto.UUID.generate(),
          course_id: Ecto.UUID.generate(),
          started_at: DateTime.utc_now(:second),
          question_ids_order: []
        })

      refute cs.valid?
      assert {:time_limit_seconds, _} = List.first(cs.errors)
    end

    test "invalid without user_role_id" do
      cs =
        ExamSimulationSession.changeset(%ExamSimulationSession{}, %{
          course_id: Ecto.UUID.generate(),
          time_limit_seconds: 2700,
          started_at: DateTime.utc_now(:second),
          question_ids_order: []
        })

      refute cs.valid?
    end

    test "invalid with unknown status" do
      cs =
        ExamSimulationSession.changeset(%ExamSimulationSession{}, %{
          user_role_id: Ecto.UUID.generate(),
          course_id: Ecto.UUID.generate(),
          time_limit_seconds: 2700,
          started_at: DateTime.utc_now(:second),
          question_ids_order: [],
          status: "nonsense"
        })

      refute cs.valid?
    end

    test "insert fails with FK violation (no real user_role)" do
      assert {:error, _} =
               ExamSimulations.create_session(%{
                 user_role_id: Ecto.UUID.generate(),
                 course_id: Ecto.UUID.generate(),
                 time_limit_seconds: 2700,
                 started_at: DateTime.utc_now(:second),
                 question_ids_order: ["q1", "q2"]
               })
    end
  end

  describe "answer_changeset/2" do
    test "updates answers map" do
      session = %ExamSimulationSession{answers: %{}}
      new_answers = %{"q1" => %{"answer" => "A"}}
      cs = ExamSimulationSession.answer_changeset(session, new_answers)
      assert Ecto.Changeset.get_change(cs, :answers) == new_answers
    end
  end

  describe "submit_changeset/2" do
    test "sets status to submitted with score fields" do
      session = %ExamSimulationSession{status: "in_progress"}

      attrs = %{
        score_correct: 8,
        score_total: 10,
        score_pct: 0.8,
        submitted_at: DateTime.utc_now(:second)
      }

      cs = ExamSimulationSession.submit_changeset(session, attrs)
      assert Ecto.Changeset.get_change(cs, :status) == "submitted"
      assert Ecto.Changeset.get_change(cs, :score_correct) == 8
      assert Ecto.Changeset.get_change(cs, :score_total) == 10
    end
  end

  describe "timeout_changeset/2" do
    test "sets status to timed_out" do
      session = %ExamSimulationSession{status: "in_progress"}

      cs =
        ExamSimulationSession.timeout_changeset(session, %{
          score_correct: 5,
          score_total: 10,
          score_pct: 0.5,
          submitted_at: DateTime.utc_now(:second)
        })

      assert Ecto.Changeset.get_change(cs, :status) == "timed_out"
      assert Ecto.Changeset.get_change(cs, :score_correct) == 5
    end
  end

  describe "abandoned_changeset/1" do
    test "sets status to abandoned" do
      session = %ExamSimulationSession{status: "in_progress"}
      cs = ExamSimulationSession.abandoned_changeset(session)
      assert Ecto.Changeset.get_change(cs, :status) == "abandoned"
    end
  end
end
