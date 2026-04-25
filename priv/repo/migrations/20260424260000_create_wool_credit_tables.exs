defmodule FunSheep.Repo.Migrations.CreateWoolCreditTables do
  use Ecto.Migration

  def change do
    create table(:wool_credits, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :delta, :integer, null: false
      add :source, :string, null: false
      add :source_ref_id, :binary_id
      add :metadata, :map, null: false, default: %{}
      timestamps(updated_at: false)
    end

    create index(:wool_credits, [:user_role_id])
    create index(:wool_credits, [:source_ref_id], where: "source_ref_id IS NOT NULL")

    create table(:credit_transfers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :from_user_role_id, references(:user_roles, type: :binary_id), null: false
      add :to_user_role_id, references(:user_roles, type: :binary_id), null: false
      add :amount_quarter_units, :integer, null: false
      add :note, :string, limit: 255
      timestamps(updated_at: false)
    end

    create index(:credit_transfers, [:from_user_role_id])
    create index(:credit_transfers, [:to_user_role_id])
    create constraint(:credit_transfers, :positive_amount, check: "amount_quarter_units > 0")
  end
end
