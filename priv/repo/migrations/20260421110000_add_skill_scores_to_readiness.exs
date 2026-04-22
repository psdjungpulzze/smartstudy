defmodule FunSheep.Repo.Migrations.AddSkillScoresToReadiness do
  @moduledoc """
  Adds per-skill (section-level) score + mastery-status fields to readiness
  snapshots, backing North Star invariants I-9 (mastery definition) and I-10
  (weakest-skill-weighted aggregate).

  `chapter_scores` stays for backward compatibility with existing callers;
  the new `skill_scores` is what drives the aggregate going forward.
  """

  use Ecto.Migration

  def change do
    alter table(:readiness_scores) do
      add :skill_scores, :map, default: "{}"
    end
  end
end
