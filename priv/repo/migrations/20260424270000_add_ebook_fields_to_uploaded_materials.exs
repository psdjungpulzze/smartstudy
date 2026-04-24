defmodule FunSheep.Repo.Migrations.AddEbookFieldsToUploadedMaterials do
  use Ecto.Migration

  def up do
    alter table(:uploaded_materials) do
      # Canonical format detected from magic bytes + extension.
      # Values: "pdf", "epub", "mobi", "azw3", "image", "unknown"
      add :material_format, :string, default: "unknown"

      # Nullable JSON: stores EPUB metadata extracted by EpubParser.
      # Shape: %{"title" => ..., "authors" => [...], "language" => ...,
      #          "publisher" => ..., "isbn" => ..., "toc" => [...]}
      add :ebook_metadata, :map
    end

    # Backfill existing PDF rows so format detection does not re-classify
    # materials that were already processed.
    execute """
    UPDATE uploaded_materials
    SET material_format = 'pdf'
    WHERE file_type ILIKE '%pdf%'
    """
  end

  def down do
    alter table(:uploaded_materials) do
      remove :material_format
      remove :ebook_metadata
    end
  end
end
