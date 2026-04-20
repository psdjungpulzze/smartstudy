defmodule FunSheep.Repo.Migrations.SupportMultipleRolesPerUser do
  use Ecto.Migration

  def change do
    drop_if_exists unique_index(:user_roles, [:interactor_user_id])
    create unique_index(:user_roles, [:interactor_user_id, :role])
  end
end
