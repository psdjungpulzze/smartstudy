defmodule FunSheep.Repo.Migrations.AddOrphanedAtToChapters do
  use Ecto.Migration

  def change do
    alter table(:chapters) do
      add :orphaned_at, :utc_datetime
    end
  end
end
