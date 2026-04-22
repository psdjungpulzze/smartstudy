defmodule FunSheep.Repo.Migrations.AddValidationAttemptsToQuestions do
  use Ecto.Migration

  def change do
    alter table(:questions) do
      add :validation_attempts, :integer, default: 0, null: false
    end
  end
end
