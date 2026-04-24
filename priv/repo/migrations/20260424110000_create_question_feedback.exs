defmodule FunSheep.Repo.Migrations.CreateQuestionFeedback do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:question_flags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all), null: false
      add :question_id, references(:questions, type: :binary_id, on_delete: :delete_all), null: false
      add :reason, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:question_flags, [:user_role_id, :question_id])
    create index(:question_flags, [:question_id])
  end
end
