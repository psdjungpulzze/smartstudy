defmodule FunSheep.Repo.Migrations.AddQualityScoreToQuestionStats do
  use Ecto.Migration

  def change do
    alter table(:question_stats) do
      add_if_not_exists :like_count, :integer, default: 0, null: false
      add_if_not_exists :dislike_count, :integer, default: 0, null: false
      add_if_not_exists :flag_count, :integer, default: 0, null: false
      add_if_not_exists :quality_score, :float, default: 0.0, null: false
    end
  end
end
