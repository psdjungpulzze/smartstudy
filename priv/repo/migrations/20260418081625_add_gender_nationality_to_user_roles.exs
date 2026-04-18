defmodule FunSheep.Repo.Migrations.AddGenderNationalityToUserRoles do
  use Ecto.Migration

  def change do
    alter table(:user_roles) do
      add :gender, :string
      add :nationality, :string
    end
  end
end
