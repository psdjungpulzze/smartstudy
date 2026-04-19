defmodule FunSheep.Repo.Migrations.RenameNationalityToEthnicity do
  use Ecto.Migration

  def change do
    rename table(:user_roles), :nationality, to: :ethnicity
  end
end
