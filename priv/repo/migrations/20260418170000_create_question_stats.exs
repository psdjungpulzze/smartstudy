defmodule FunSheep.Repo.Migrations.CreateQuestionStats do
  use Ecto.Migration

  def change do
    create table(:question_stats, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :question_id, references(:questions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :total_attempts, :integer, default: 0, null: false
      add :correct_attempts, :integer, default: 0, null: false
      add :difficulty_score, :float, default: 0.5, null: false
      add :avg_time_seconds, :float, default: 0.0, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:question_stats, [:question_id])

    # Add source_material_id to questions for question set filtering
    alter table(:questions) do
      add :source_material_id,
          references(:uploaded_materials, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:questions, [:source_material_id])

    # Add relevance validation to uploaded materials
    alter table(:uploaded_materials) do
      add :relevance_status, :string, default: "pending"
      add :relevance_score, :float
      add :relevance_notes, :text
    end
  end
end
