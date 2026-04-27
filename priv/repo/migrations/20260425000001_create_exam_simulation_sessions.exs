defmodule FunSheep.Repo.Migrations.CreateExamSimulationSessions do
  use Ecto.Migration

  def change do
    create table(:exam_simulation_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true, null: false, default: fragment("gen_random_uuid()")

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false
      add :schedule_id, references(:test_schedules, type: :binary_id, on_delete: :nilify_all)

      add :format_template_id,
          references(:test_format_templates, type: :binary_id, on_delete: :nilify_all)

      add :status, :string, null: false, default: "in_progress"
      add :time_limit_seconds, :integer, null: false
      add :started_at, :utc_datetime, null: false
      add :submitted_at, :utc_datetime
      add :question_ids_order, :jsonb, null: false, default: "[]"
      add :section_boundaries, :jsonb, null: false, default: "[]"
      add :answers, :jsonb, null: false, default: "{}"
      add :score_correct, :integer
      add :score_total, :integer
      add :score_pct, :float
      add :section_scores, :jsonb

      timestamps(type: :utc_datetime)
    end

    create index(:exam_simulation_sessions, [:user_role_id])
    create index(:exam_simulation_sessions, [:course_id])
    create index(:exam_simulation_sessions, [:user_role_id, :status])

    create constraint(:exam_simulation_sessions, :valid_status,
             check: "status IN ('in_progress','submitted','timed_out','abandoned')"
           )
  end
end
