defmodule FunSheep.Repo.Migrations.AddSuspendedAtToUserRoles do
  use Ecto.Migration

  def change do
    alter table(:user_roles) do
      add :suspended_at, :utc_datetime
    end

    create index(:user_roles, [:suspended_at], where: "suspended_at IS NOT NULL")
  end
end
