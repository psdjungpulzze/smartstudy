defmodule FunSheep.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :type, :string, null: false
      add :channel, :string, null: false
      add :priority, :integer, null: false, default: 2
      add :title, :string
      add :body, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :status, :string, null: false, default: "pending"
      add :scheduled_for, :utc_datetime, null: false
      add :sent_at, :utc_datetime
      add :read_at, :utc_datetime

      add :inserted_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create index(:notifications, [:user_role_id, :status])
    create index(:notifications, [:user_role_id, :channel, :read_at])
    create index(:notifications, [:status, :scheduled_for])
    create index(:notifications, [:type, :user_role_id, :inserted_at])
  end
end
