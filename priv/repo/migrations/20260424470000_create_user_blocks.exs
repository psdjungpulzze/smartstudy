defmodule FunSheep.Repo.Migrations.CreateUserBlocks do
  use Ecto.Migration

  def change do
    create table(:user_blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :blocker_id, references(:user_roles, type: :binary_id, on_delete: :delete_all), null: false
      add :blocked_id, references(:user_roles, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:user_blocks, [:blocker_id, :blocked_id])
    create index(:user_blocks, [:blocker_id])
    create index(:user_blocks, [:blocked_id])

    create constraint(:user_blocks, :no_self_block,
      check: "blocker_id != blocked_id"
    )
  end
end
