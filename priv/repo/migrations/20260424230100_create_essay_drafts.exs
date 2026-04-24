defmodule FunSheep.Repo.Migrations.CreateEssayDrafts do
  use Ecto.Migration

  def change do
    create table(:essay_drafts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :question_id, references(:questions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :schedule_id, references(:test_schedules, type: :binary_id, on_delete: :nilify_all)
      add :body, :text, null: false, default: ""
      add :word_count, :integer, null: false, default: 0
      add :last_saved_at, :utc_datetime, null: false
      add :started_at, :utc_datetime, null: false
      add :time_elapsed_seconds, :integer, null: false, default: 0
      add :submitted, :boolean, null: false, default: false
      add :submitted_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:essay_drafts, [:user_role_id, :question_id, :schedule_id])
    create index(:essay_drafts, [:user_role_id])
    create index(:essay_drafts, [:question_id])
  end
end
