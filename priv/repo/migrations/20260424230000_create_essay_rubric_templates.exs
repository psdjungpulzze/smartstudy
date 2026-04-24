defmodule FunSheep.Repo.Migrations.CreateEssayRubricTemplates do
  use Ecto.Migration

  def change do
    create table(:essay_rubric_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :exam_type, :string, null: false
      add :criteria, :map, null: false
      add :max_score, :integer, null: false
      add :mastery_threshold_ratio, :float, null: false, default: 0.67
      add :time_limit_minutes, :integer
      add :word_target, :integer
      add :word_limit, :integer
      timestamps(type: :utc_datetime)
    end

    create unique_index(:essay_rubric_templates, [:exam_type])
  end
end
