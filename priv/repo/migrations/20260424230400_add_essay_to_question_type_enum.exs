defmodule FunSheep.Repo.Migrations.AddEssayToQuestionTypeEnum do
  use Ecto.Migration

  def up do
    execute("ALTER TYPE question_type ADD VALUE IF NOT EXISTS 'essay'")
  end

  def down do
    # PostgreSQL does not support removing individual values from an enum.
    # A rollback would require recreating the type, which is destructive.
    # For safety, this migration is intentionally irreversible.
    :ok
  end
end
