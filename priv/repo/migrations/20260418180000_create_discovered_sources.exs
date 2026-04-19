defmodule FunSheep.Repo.Migrations.CreateDiscoveredSources do
  use Ecto.Migration

  def change do
    create table(:discovered_sources, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false

      # What kind of source
      add :source_type, :string, null: false
      # "textbook", "question_bank", "practice_test", "study_guide", "curriculum", "video"

      # Discovery metadata
      add :title, :string, null: false
      add :url, :string
      add :description, :text
      add :publisher, :string
      add :content_preview, :text

      # Processing state
      add :status, :string, default: "discovered", null: false
      # "discovered" -> "scraping" -> "scraped" -> "processed" | "failed" | "skipped"

      # Stats after processing
      add :questions_extracted, :integer, default: 0
      add :content_size_bytes, :integer, default: 0

      # Raw scraped content (stored for re-processing)
      add :scraped_text, :text

      # Search metadata
      add :search_query, :string
      add :confidence_score, :float, default: 0.0

      timestamps(type: :utc_datetime)
    end

    create index(:discovered_sources, [:course_id])
    create index(:discovered_sources, [:source_type])
    create unique_index(:discovered_sources, [:course_id, :url], where: "url IS NOT NULL")
  end
end
