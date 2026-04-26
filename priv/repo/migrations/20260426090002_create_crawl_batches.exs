defmodule FunSheep.Repo.Migrations.CreateCrawlBatches do
  use Ecto.Migration

  def change do
    create table(:crawl_batches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false
      # "web_search" | "sitemap" | "api" | "registry"
      add :strategy, :string
      # Mirror of course.catalog_test_type for quick dashboarding without joining courses
      add :test_type, :string
      add :total_urls, :integer, default: 0, null: false
      add :processed_urls, :integer, default: 0, null: false
      add :questions_extracted, :integer, default: 0, null: false
      # "running" | "enqueued" | "complete" | "failed"
      add :status, :string, default: "running", null: false
      add :config, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:crawl_batches, [:course_id])
    create index(:crawl_batches, [:status])
    create index(:crawl_batches, [:inserted_at])
  end
end
