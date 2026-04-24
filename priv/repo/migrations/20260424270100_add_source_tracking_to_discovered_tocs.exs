defmodule FunSheep.Repo.Migrations.AddSourceTrackingToDiscoveredTocs do
  use Ecto.Migration

  def change do
    alter table(:discovered_tocs) do
      # Which uploaded material this TOC was extracted from (nullable —
      # web-scraped and AI-inferred TOCs have no source material).
      add :source_material_id,
          references(:uploaded_materials, on_delete: :nilify_all, type: :binary_id)

      # How the TOC was obtained. Extends the existing string-based `source`
      # field with richer origin tracking:
      #   "scraped"    — web scraping (existing rows)
      #   "ebook_toc"  — parsed directly from an EPUB/MOBI navigation document
      #   "ai_inferred" — inferred by AI from OCR text
      add :source_type, :string, default: "scraped"
    end

    create index(:discovered_tocs, [:source_material_id])
  end
end
