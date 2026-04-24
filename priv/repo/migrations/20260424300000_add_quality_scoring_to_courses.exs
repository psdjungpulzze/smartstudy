defmodule FunSheep.Repo.Migrations.AddQualityScoringToCourses do
  use Ecto.Migration

  def change do
    alter table(:courses) do
      add :quality_score, :float, default: 0.0
      add :like_count, :integer, default: 0
      add :dislike_count, :integer, default: 0
      add :completion_count, :integer, default: 0
      add :attempt_count, :integer, default: 0
      add :unique_user_count, :integer, default: 0
      add :quality_last_computed_at, :utc_datetime
      add :visibility_state, :string, default: "normal"
      add :dormant_at, :utc_datetime
    end
  end
end
