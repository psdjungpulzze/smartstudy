defmodule FunSheep.Repo.Migrations.AddStreakFields do
  use Ecto.Migration

  def change do
    alter table(:streaks) do
      # Number of times the user has activated a streak freeze.
      # Used by the freeze-purchase flow to cap total freezes per account.
      add_if_not_exists :freeze_count, :integer, default: 0, null: false

      # Date the most recent freeze was activated (UTC date).
      # Enables a "one active freeze per day" guard.
      add_if_not_exists :freeze_used_at, :date
    end
  end
end
