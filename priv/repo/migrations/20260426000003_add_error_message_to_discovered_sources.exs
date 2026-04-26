defmodule FunSheep.Repo.Migrations.AddErrorMessageToDiscoveredSources do
  use Ecto.Migration

  def change do
    alter table(:discovered_sources) do
      add :error_message, :text
    end
  end
end
