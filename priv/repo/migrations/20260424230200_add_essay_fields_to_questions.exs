defmodule FunSheep.Repo.Migrations.AddEssayFieldsToQuestions do
  use Ecto.Migration

  def change do
    alter table(:questions) do
      add :essay_rubric_template_id,
          references(:essay_rubric_templates, type: :binary_id, on_delete: :nilify_all)

      add :essay_time_limit_minutes, :integer
      add :essay_word_target, :integer
      add :essay_word_limit, :integer
      add :essay_source_documents, :map
    end

    create index(:questions, [:essay_rubric_template_id])
  end
end
