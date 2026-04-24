defmodule FunSheep.Repo.Migrations.AddScoringToQuestionAttempts do
  use Ecto.Migration

  def change do
    alter table(:question_attempts) do
      add :score, :integer
      add :score_max, :integer, default: 10
      add :score_feedback, :text
      add :grader_path, :string
    end
  end
end
