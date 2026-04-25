defmodule FunSheep.Repo.Migrations.AddQualityScoreToTestSchedules do
  use Ecto.Migration

  def change do
    alter table(:test_schedules) do
      add :quality_score, :float, default: 0.0
      add :completion_count, :integer, default: 0
      add :attempt_count, :integer, default: 0
    end
  end
end
