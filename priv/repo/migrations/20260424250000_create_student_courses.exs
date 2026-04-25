defmodule FunSheep.Repo.Migrations.CreateStudentCourses do
  use Ecto.Migration

  def change do
    create table(:student_courses, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id,
          references(:user_roles, type: :binary_id, on_delete: :delete_all),
          null: false

      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "active"
      add :enrolled_at, :utc_datetime
      add :source, :string, null: false, default: "self_enrolled"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:student_courses, [:user_role_id, :course_id])
    create index(:student_courses, [:user_role_id, :status])
    create index(:student_courses, [:course_id])
  end
end
