defmodule FunSheep.Repo.Migrations.AddEssayFieldsToQuestionAttempts do
  use Ecto.Migration

  def change do
    alter table(:question_attempts) do
      add :essay_draft_id,
          references(:essay_drafts, type: :binary_id, on_delete: :nilify_all)

      add :essay_word_count, :integer
    end

    create index(:question_attempts, [:essay_draft_id])
  end
end
