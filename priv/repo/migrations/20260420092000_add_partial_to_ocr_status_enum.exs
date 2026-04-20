defmodule FunSheep.Repo.Migrations.AddPartialToOcrStatusEnum do
  use Ecto.Migration

  # Postgres ALTER TYPE ... ADD VALUE cannot run inside a transaction block.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute "ALTER TYPE ocr_status ADD VALUE IF NOT EXISTS 'partial' AFTER 'completed'"
  end

  def down do
    # Postgres has no DROP VALUE for enums; the rollback is intentionally a
    # no-op. To remove the value cleanly, the type must be recreated and the
    # column rewritten — far heavier than this forward-only addition warrants.
    :ok
  end
end
