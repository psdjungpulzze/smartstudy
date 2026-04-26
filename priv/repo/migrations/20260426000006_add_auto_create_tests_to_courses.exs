defmodule FunSheep.Repo.Migrations.AddAutoCreateTestsToCourses do
  use Ecto.Migration

  def change do
    alter table(:courses) do
      add :auto_create_tests, :boolean, null: false, default: false
    end
  end
end
