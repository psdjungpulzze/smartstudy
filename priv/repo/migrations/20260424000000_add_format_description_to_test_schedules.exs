defmodule FunSheep.Repo.Migrations.AddFormatDescriptionToTestSchedules do
  use Ecto.Migration

  def change do
    alter table(:test_schedules) do
      add :format_description, :text
    end
  end
end
