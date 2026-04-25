defmodule FunSheep.Repo.Migrations.CreateShoutOuts do
  use Ecto.Migration

  def change do
    create table(:shout_outs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :category, :string, null: false
      # "weekly" | "monthly"
      add :period, :string, null: false, default: "weekly"
      add :period_start, :date, null: false
      add :period_end, :date, null: false
      add :metric_value, :integer, null: false

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(updated_at: false)
    end

    create index(:shout_outs, [:category, :period, :period_start])
    create index(:shout_outs, [:user_role_id])
  end
end
