defmodule FunSheep.Repo.Migrations.CreateSourceRegistryEntries do
  use Ecto.Migration

  def change do
    create table(:source_registry_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :test_type, :string, null: false
      add :catalog_subject, :string
      add :url_or_pattern, :string, null: false
      add :domain, :string, null: false
      add :source_type, :string, null: false
      add :tier, :integer, null: false
      add :is_enabled, :boolean, default: true, null: false
      add :extractor_module, :string
      add :avg_questions_per_page, :integer
      add :consecutive_failures, :integer, default: 0, null: false
      add :last_verified_at, :utc_datetime
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:source_registry_entries, [:test_type, :catalog_subject, :is_enabled])
    create index(:source_registry_entries, [:domain])
    create unique_index(:source_registry_entries, [:test_type, :catalog_subject, :url_or_pattern])
  end
end
