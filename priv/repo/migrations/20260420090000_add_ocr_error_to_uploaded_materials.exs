defmodule FunSheep.Repo.Migrations.AddOcrErrorToUploadedMaterials do
  use Ecto.Migration

  def change do
    alter table(:uploaded_materials) do
      add :ocr_error, :text
    end
  end
end
