defmodule FunSheep.Repo.Migrations.AddPricingToCourses do
  use Ecto.Migration

  def change do
    alter table(:courses) do
      add :price_cents, :integer, null: true
      add :currency, :string, default: "usd"
      add :price_label, :string
    end
  end
end
