defmodule FunSheep.Repo.Migrations.CreateQuestionGroups do
  use Ecto.Migration

  def change do
    create table(:question_groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :stimulus_type, :string, null: false
      add :stimulus_title, :string
      add :stimulus_content, :text, null: false
      add :stimulus_html, :text
      add :word_count, :integer
      add :reading_level, :string
      add :difficulty, :string
      add :source_type, :string, default: "ai_generated"
      add :generation_mode, :string
      add :grounding_refs, :map, default: %{}
      add :validation_status, :string, default: "pending"
      add :validation_score, :float
      add :validation_report, :map, default: %{}
      add :validated_at, :utc_datetime
      add :metadata, :map, default: %{}
      add :course_id, references(:courses, type: :binary_id, on_delete: :nilify_all)
      add :chapter_id, references(:chapters, type: :binary_id, on_delete: :nilify_all)
      add :section_id, references(:sections, type: :binary_id, on_delete: :nilify_all)

      add :source_material_id,
          references(:uploaded_materials, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:question_groups, [:course_id])
    create index(:question_groups, [:chapter_id])
  end
end
