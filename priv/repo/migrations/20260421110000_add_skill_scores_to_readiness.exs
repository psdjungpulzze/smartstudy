defmodule FunSheep.Repo.Migrations.AddSkillScoresToReadiness do
  @moduledoc """
  Adds per-skill score + mastery-status fields to readiness snapshots,
  backing North Star I-9 and I-10.
  """

  use Ecto.Migration

  def change do
    alter table(:readiness_scores) do
      add :skill_scores, :map, default: "{}"
    end
  end
end
