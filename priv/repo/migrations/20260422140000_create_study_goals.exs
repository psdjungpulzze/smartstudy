defmodule FunSheep.Repo.Migrations.CreateStudyGoals do
  use Ecto.Migration

  def change do
    create table(:study_goals, primary_key: false) do
      add :id, :binary_id, primary_key: true, null: false

      add :student_id,
          references(:user_roles, type: :binary_id, on_delete: :delete_all),
          null: false

      add :guardian_id,
          references(:user_roles, type: :binary_id, on_delete: :delete_all),
          null: false

      add :course_id, references(:courses, type: :binary_id, on_delete: :nilify_all)

      add :test_schedule_id,
          references(:test_schedules, type: :binary_id, on_delete: :nilify_all)

      add :goal_type, :string, null: false
      add :target_value, :integer, null: false

      add :start_date, :date, null: false
      add :end_date, :date

      add :status, :string, null: false, default: "proposed"
      add :proposed_by, :string, null: false
      add :accepted_at, :utc_datetime
      add :decline_reason, :text

      timestamps(type: :utc_datetime)
    end

    create index(:study_goals, [:student_id, :status])
    create index(:study_goals, [:guardian_id, :status])
    create index(:study_goals, [:test_schedule_id])
    create index(:study_goals, [:status, :end_date])
  end
end
