defmodule FunSheep.Repo.Migrations.CreateFixedTestSessions do
  use Ecto.Migration

  def change do
    create table(:fixed_test_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :bank_id, references(:fixed_test_banks, type: :binary_id, on_delete: :restrict),
        null: false

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :assignment_id,
          references(:fixed_test_assignments, type: :binary_id, on_delete: :nilify_all)

      add :status, :string, null: false, default: "in_progress"
      add :started_at, :utc_datetime, null: false
      add :completed_at, :utc_datetime
      add :time_taken_seconds, :integer
      add :score_correct, :integer
      add :score_total, :integer
      add :answers, :jsonb
      add :questions_order, :jsonb

      timestamps(type: :utc_datetime)
    end

    create index(:fixed_test_sessions, [:bank_id])
    create index(:fixed_test_sessions, [:user_role_id])
    create index(:fixed_test_sessions, [:assignment_id])
    create index(:fixed_test_sessions, [:user_role_id, :bank_id])
  end
end
