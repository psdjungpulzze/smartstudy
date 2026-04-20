defmodule FunSheep.Repo.Migrations.CreateUserTutorials do
  use Ecto.Migration

  def change do
    create table(:user_tutorials, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :tutorial_key, :string, null: false
      add :completed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_tutorials, [:user_role_id, :tutorial_key])
  end
end
