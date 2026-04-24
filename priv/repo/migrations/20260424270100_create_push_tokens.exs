defmodule FunSheep.Repo.Migrations.CreatePushTokens do
  use Ecto.Migration

  def change do
    create table(:push_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :string, null: false
      add :platform, :string, null: false
      add :active, :boolean, null: false, default: true

      add :inserted_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create unique_index(:push_tokens, [:user_role_id, :token])
    create index(:push_tokens, [:user_role_id, :active])
  end
end
