defmodule FunSheep.Repo.Migrations.AddTimezoneToUserRoles do
  use Ecto.Migration

  def change do
    alter table(:user_roles) do
      add :timezone, :string
    end
  end
end
