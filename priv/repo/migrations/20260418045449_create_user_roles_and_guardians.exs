defmodule FunSheep.Repo.Migrations.CreateUserRolesAndGuardians do
  use Ecto.Migration

  def change do
    create_query = "CREATE TYPE user_role_type AS ENUM ('student', 'parent', 'teacher')"
    drop_query = "DROP TYPE IF EXISTS user_role_type"
    execute(create_query, drop_query)

    create_query = "CREATE TYPE guardian_relationship_type AS ENUM ('parent', 'teacher')"
    drop_query = "DROP TYPE IF EXISTS guardian_relationship_type"
    execute(create_query, drop_query)

    create_query = "CREATE TYPE guardian_status AS ENUM ('pending', 'active', 'revoked')"
    drop_query = "DROP TYPE IF EXISTS guardian_status"
    execute(create_query, drop_query)

    create_if_not_exists table(:user_roles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :interactor_user_id, :string, null: false
      add :role, :user_role_type, null: false
      add :email, :string
      add :display_name, :string
      add :school_id, references(:schools, type: :binary_id, on_delete: :nilify_all)
      add :grade, :string
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists unique_index(:user_roles, [:interactor_user_id])
    create_if_not_exists index(:user_roles, [:school_id])
    create_if_not_exists index(:user_roles, [:role])

    create_if_not_exists table(:student_guardians, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :guardian_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :student_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :relationship_type, :guardian_relationship_type, null: false
      add :status, :guardian_status, null: false, default: "pending"
      add :class_name, :string
      add :invited_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists unique_index(:student_guardians, [:guardian_id, :student_id])
    create_if_not_exists index(:student_guardians, [:student_id])
    create_if_not_exists index(:student_guardians, [:guardian_id])
  end
end
