defmodule FunSheep.Repo.Migrations.CreatePracticeAssignments do
  use Ecto.Migration

  def change do
    create table(:practice_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true, null: false

      add :student_id,
          references(:user_roles, type: :binary_id, on_delete: :delete_all),
          null: false

      add :guardian_id,
          references(:user_roles, type: :binary_id, on_delete: :delete_all),
          null: false

      add :course_id, references(:courses, type: :binary_id, on_delete: :nilify_all)
      add :chapter_id, references(:chapters, type: :binary_id, on_delete: :nilify_all)
      add :section_id, references(:sections, type: :binary_id, on_delete: :nilify_all)

      add :question_count, :integer, null: false
      add :due_date, :date
      add :status, :string, null: false, default: "pending"
      add :completed_at, :utc_datetime
      add :questions_attempted, :integer, null: false, default: 0
      add :questions_correct, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:practice_assignments, [:student_id, :status])
    create index(:practice_assignments, [:guardian_id, :status])
    create index(:practice_assignments, [:student_id, :due_date])
  end
end
