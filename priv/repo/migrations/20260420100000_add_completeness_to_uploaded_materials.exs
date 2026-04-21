defmodule FunSheep.Repo.Migrations.AddCompletenessToUploadedMaterials do
  use Ecto.Migration

  def change do
    alter table(:uploaded_materials) do
      add :completeness_score, :float
      add :completeness_notes, :text
      add :toc_detected, :boolean, default: false, null: false
      add :completeness_checked_at, :utc_datetime
    end

    create index(:uploaded_materials, [:course_id, :material_kind, :completeness_score])
  end
end
