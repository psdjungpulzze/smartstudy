defmodule FunSheep.Repo.Migrations.AddLastLoginAtToUserRoles do
  use Ecto.Migration

  def change do
    alter table(:user_roles) do
      add :last_login_at, :utc_datetime
    end

    create index(:user_roles, [:last_login_at])
  end
end
