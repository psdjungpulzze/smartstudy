defmodule FunSheep.Repo.Migrations.AddStatusToOcrPages do
  use Ecto.Migration

  def up do
    alter table(:ocr_pages) do
      add :status, :string, default: "completed", null: false
      add :error, :text
    end

    # Existing rows were only ever inserted on success, so backfill as completed.
    execute "UPDATE ocr_pages SET status = 'completed' WHERE status IS NULL"

    create index(:ocr_pages, [:material_id, :status])
  end

  def down do
    drop index(:ocr_pages, [:material_id, :status])

    alter table(:ocr_pages) do
      remove :status
      remove :error
    end
  end
end
