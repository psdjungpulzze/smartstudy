defmodule FunSheep.Repo.Migrations.AddSourceTierToQuestions do
  use Ecto.Migration

  def change do
    alter table(:questions) do
      # Trust tier of the web source. 1 = official test maker, 2 = established
      # prep company, 3 = student-sharing site, 4 = unknown. nil for
      # AI-generated questions that have no web source.
      add :source_tier, :integer
    end

    create index(:questions, [:source_tier])
  end
end
