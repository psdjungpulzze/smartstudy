defmodule FunSheep.Repo.Migrations.AddBonusFreeTestsToSubscriptions do
  use Ecto.Migration

  def change do
    alter table(:subscriptions) do
      add :bonus_free_tests, :integer, null: false, default: 0
    end
  end
end
