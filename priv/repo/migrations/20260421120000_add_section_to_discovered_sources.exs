defmodule FunSheep.Repo.Migrations.AddSectionToDiscoveredSources do
  @moduledoc """
  Links discovered sources (especially videos) to a specific section so the
  practice UI can surface relevant videos on wrong-answer / "I don't know"
  events — North Star invariant I-14.
  """

  use Ecto.Migration

  def change do
    alter table(:discovered_sources) do
      add :section_id, references(:sections, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:discovered_sources, [:section_id])
    create index(:discovered_sources, [:section_id, :source_type])
  end
end
