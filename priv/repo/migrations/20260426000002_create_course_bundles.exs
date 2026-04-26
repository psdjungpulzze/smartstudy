defmodule FunSheep.Repo.Migrations.CreateCourseBundles do
  use Ecto.Migration

  def change do
    create table(:course_bundles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :price_cents, :integer, null: false
      add :currency, :string, default: "usd", null: false
      add :course_ids, {:array, :binary_id}, null: false, default: []
      add :is_active, :boolean, default: true, null: false
      add :catalog_test_type, :string
      timestamps(type: :utc_datetime)
    end

    create index(:course_bundles, [:catalog_test_type])
    create index(:course_bundles, [:is_active])
  end
end
