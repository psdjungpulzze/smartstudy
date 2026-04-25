defmodule FunSheep.Repo.Migrations.DropSocialFollowsUpdatedAt do
  use Ecto.Migration

  def up do
    # The social_follows schema uses timestamps(updated_at: false), meaning
    # Ecto never sets updated_at. Drop the column so inserts don't hit a
    # NOT NULL violation.
    alter table(:social_follows) do
      remove :updated_at
    end
  end

  def down do
    alter table(:social_follows) do
      add :updated_at, :utc_datetime, null: true
    end
  end
end
