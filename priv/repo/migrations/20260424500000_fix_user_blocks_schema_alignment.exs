defmodule FunSheep.Repo.Migrations.FixUserBlocksSchemaAlignment do
  use Ecto.Migration

  def up do
    # The user_blocks table was created with timestamps(type: :utc_datetime) which
    # includes updated_at. But FunSheep.Social.Block uses timestamps(updated_at: false).
    # Drop updated_at to avoid NOT NULL violations on insert.
    alter table(:user_blocks) do
      remove :updated_at
    end

    # Add the no_self_block check constraint referenced in Block.changeset/2.
    create constraint(:user_blocks, :no_self_block,
             check: "blocker_id != blocked_id"
           )
  end

  def down do
    drop constraint(:user_blocks, :no_self_block)

    alter table(:user_blocks) do
      add :updated_at, :utc_datetime, null: true
    end
  end
end
