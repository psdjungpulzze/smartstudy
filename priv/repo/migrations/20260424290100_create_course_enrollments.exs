defmodule FunSheep.Repo.Migrations.CreateCourseEnrollments do
  use Ecto.Migration

  def change do
    create table(:course_enrollments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false

      # 'subscription', 'alacarte', 'free', 'gifted'
      add :access_type, :string, null: false
      add :access_granted_at, :utc_datetime, null: false
      # nil = permanent
      add :access_expires_at, :utc_datetime
      add :purchase_reference, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:course_enrollments, [:user_role_id, :course_id])
    create index(:course_enrollments, [:user_role_id])
    create index(:course_enrollments, [:course_id])
  end
end
