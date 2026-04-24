defmodule FunSheep.Repo.Migrations.AddCatalogAccessToSubscriptions do
  use Ecto.Migration

  def change do
    alter table(:subscriptions) do
      add :catalog_access, {:array, :string}, default: []
    end
  end
end
