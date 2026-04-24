defmodule FunSheep.Repo.Migrations.AddFloatScoreToQuestionAttempts do
  use Ecto.Migration

  def change do
    alter table(:question_attempts) do
      add_if_not_exists :score_float, :float
      add_if_not_exists :score_max_float, :float
    end
  end
end
