defmodule FunSheep.Repo.Migrations.AddTargetScoreToTestSchedules do
  use Ecto.Migration

  def change do
    alter table(:test_schedules) do
      # Jointly settable by parent + student (Phase 3 §7.1 wires the proposal
      # flow). Stored as an integer 0..100 mirroring the readiness score units.
      add :target_readiness_score, :integer
      # Who set the target most recently — used to present the "who proposed
      # this?" framing in Phase 3 and to gate permission to change it. Values:
      # :student | :guardian | nil (unset).
      add :target_set_by, :string
      add :target_set_at, :utc_datetime
    end
  end
end
