defmodule FunSheep.Repo.Migrations.AddFolderNameToUploadedMaterials do
  use Ecto.Migration

  def change do
    alter table(:uploaded_materials) do
      add :folder_name, :string
    end

    create index(:uploaded_materials, [:folder_name])
  end
end
