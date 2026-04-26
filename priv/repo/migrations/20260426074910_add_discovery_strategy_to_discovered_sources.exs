defmodule FunSheep.Repo.Migrations.AddDiscoveryStrategyToDiscoveredSources do
  use Ecto.Migration

  def change do
    alter table(:discovered_sources) do
      add :discovery_strategy, :string, default: "web_search"
      add :scrape_attempts, :integer, default: 0
      add :last_scraped_at, :utc_datetime
    end

    create index(:discovered_sources, [:discovery_strategy])
    create index(:discovered_sources, [:status, :scrape_attempts])
  end
end
