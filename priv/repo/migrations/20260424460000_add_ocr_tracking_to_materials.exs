defmodule FunSheep.Repo.Migrations.AddOcrTrackingToMaterials do
  use Ecto.Migration

  def change do
    alter table(:uploaded_materials) do
      add_if_not_exists :ocr_started_at, :utc_datetime
      add_if_not_exists :ocr_pages_done, :integer, default: 0
      add_if_not_exists :ocr_pages_total, :integer
    end
  end
end
