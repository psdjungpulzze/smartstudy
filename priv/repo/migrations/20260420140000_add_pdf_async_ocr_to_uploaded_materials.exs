defmodule FunSheep.Repo.Migrations.AddPdfAsyncOcrToUploadedMaterials do
  use Ecto.Migration

  def change do
    alter table(:uploaded_materials) do
      # Async PDF OCR tracks N Vision long-running operations per material
      # (one per page-range chunk). Stored as JSON under "chunks".
      add :ocr_operations, :map, default: %{}, null: false
      add :ocr_pages_expected, :integer
      add :ocr_pages_completed, :integer, default: 0, null: false
    end

    # Any existing (material_id, page_number) duplicates must be collapsed
    # before we can add the unique index. The previous pipeline could create
    # dupes if a retry slipped through between `delete_ocr_pages_for_material`
    # and the new insert. Keep the most recently updated row per page and
    # drop the rest — that row has the best chance of being the successful
    # OCR result rather than a retry's failure stub.
    execute(
      """
      DELETE FROM ocr_pages
      WHERE id IN (
        SELECT id FROM (
          SELECT id,
                 row_number() OVER (
                   PARTITION BY material_id, page_number
                   ORDER BY updated_at DESC, inserted_at DESC, id DESC
                 ) AS rn
          FROM ocr_pages
        ) ranked
        WHERE ranked.rn > 1
      )
      """,
      # No-op on rollback — duplicates aren't meaningful data to restore.
      ""
    )

    # ON CONFLICT (material_id, page_number) needs a true unique constraint,
    # not the existing non-unique composite index. The chunk poller relies
    # on this so a re-poll after a worker crash is safe.
    drop_if_exists index(:ocr_pages, [:material_id, :page_number])
    create unique_index(:ocr_pages, [:material_id, :page_number])
  end
end
