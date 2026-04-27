defmodule FunSheep.Repo.Migrations.WidenDiscoveredSourcesUrlAndTitle do
  use Ecto.Migration

  def change do
    alter table(:discovered_sources) do
      modify :url, :text
      modify :title, :text
      modify :publisher, :text
      modify :search_query, :text
    end
  end
end
