defmodule FunSheep.Repo.Migrations.AddConfidenceToQuestionAttempts do
  use Ecto.Migration

  def change do
    alter table(:question_attempts) do
      add :confidence, :string
    end
  end
end
