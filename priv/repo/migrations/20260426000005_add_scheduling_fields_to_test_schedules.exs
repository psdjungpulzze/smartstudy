defmodule FunSheep.Repo.Migrations.AddSchedulingFieldsToTestSchedules do
  use Ecto.Migration

  def change do
    alter table(:test_schedules) do
      # standard = student-created, official = auto-created from known_test_dates, simulation = full mock exam
      add :schedule_type, :string, null: false, default: "standard"
      add :is_auto_created, :boolean, null: false, default: false
      add :known_test_date_id, references(:known_test_dates, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:test_schedules, [:known_test_date_id])
  end
end
