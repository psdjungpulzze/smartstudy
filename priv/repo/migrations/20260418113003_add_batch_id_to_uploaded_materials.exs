defmodule FunSheep.Repo.Migrations.AddBatchIdToUploadedMaterials do
  use Ecto.Migration

  def change do
    alter table(:uploaded_materials) do
      add :batch_id, :binary_id
    end

    # Make course_id nullable for staged (pre-course) uploads
    execute "ALTER TABLE uploaded_materials ALTER COLUMN course_id DROP NOT NULL",
            "ALTER TABLE uploaded_materials ALTER COLUMN course_id SET NOT NULL"

    create index(:uploaded_materials, [:batch_id])
  end
end
