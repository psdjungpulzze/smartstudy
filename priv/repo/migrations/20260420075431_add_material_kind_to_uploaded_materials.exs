defmodule FunSheep.Repo.Migrations.AddMaterialKindToUploadedMaterials do
  use Ecto.Migration

  def up do
    alter table(:uploaded_materials) do
      add :material_kind, :string, default: "textbook", null: false
    end

    execute "UPDATE uploaded_materials SET material_kind = 'textbook' WHERE material_kind IS NULL"

    create index(:uploaded_materials, [:material_kind])
  end

  def down do
    drop index(:uploaded_materials, [:material_kind])

    alter table(:uploaded_materials) do
      remove :material_kind
    end
  end
end
