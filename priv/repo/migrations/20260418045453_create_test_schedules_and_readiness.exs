defmodule FunSheep.Repo.Migrations.CreateTestSchedulesAndReadiness do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:test_format_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :course_id, references(:courses, type: :binary_id, on_delete: :nilify_all)
      add :structure, :map, null: false
      add :created_by_id, references(:user_roles, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:test_format_templates, [:course_id])
    create_if_not_exists index(:test_format_templates, [:created_by_id])

    create_if_not_exists table(:test_schedules, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :test_date, :date, null: false
      add :scope, :map, null: false

      add :format_template_id,
          references(:test_format_templates, type: :binary_id, on_delete: :nilify_all)

      add :notifications_enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:test_schedules, [:user_role_id])
    create_if_not_exists index(:test_schedules, [:course_id])
    create_if_not_exists index(:test_schedules, [:test_date])
    create_if_not_exists index(:test_schedules, [:format_template_id])

    create_if_not_exists table(:readiness_scores, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :test_schedule_id,
          references(:test_schedules, type: :binary_id, on_delete: :delete_all),
          null: false

      add :chapter_scores, :map, null: false
      add :topic_scores, :map, null: false
      add :aggregate_score, :float, null: false
      add :calculated_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:readiness_scores, [:user_role_id])
    create_if_not_exists index(:readiness_scores, [:test_schedule_id])
    create_if_not_exists index(:readiness_scores, [:user_role_id, :test_schedule_id])
  end
end
