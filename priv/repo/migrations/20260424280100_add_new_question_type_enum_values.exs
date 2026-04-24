defmodule FunSheep.Repo.Migrations.AddNewQuestionTypeEnumValues do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute "ALTER TYPE question_type ADD VALUE IF NOT EXISTS 'multi_select'"
    execute "ALTER TYPE question_type ADD VALUE IF NOT EXISTS 'cloze'"
    execute "ALTER TYPE question_type ADD VALUE IF NOT EXISTS 'matching'"
    execute "ALTER TYPE question_type ADD VALUE IF NOT EXISTS 'ordering'"
    execute "ALTER TYPE question_type ADD VALUE IF NOT EXISTS 'numeric'"
  end

  def down do
    # PostgreSQL does not support removing enum values — intentional no-op
    :ok
  end
end
