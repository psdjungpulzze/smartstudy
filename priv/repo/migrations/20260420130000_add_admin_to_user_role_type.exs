defmodule FunSheep.Repo.Migrations.AddAdminToUserRoleType do
  use Ecto.Migration

  # ALTER TYPE ... ADD VALUE must run outside a transaction in PostgreSQL.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("ALTER TYPE user_role_type ADD VALUE IF NOT EXISTS 'admin'")
  end

  def down do
    # PostgreSQL does not support removing a value from an enum type.
    :ok
  end
end
