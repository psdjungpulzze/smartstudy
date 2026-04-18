defmodule FunSheep.Repo.Migrations.CreateCoursesAndChapters do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:courses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :subject, :string, null: false
      add :grade, :string, null: false
      add :school_id, references(:schools, type: :binary_id, on_delete: :nilify_all)
      add :description, :text
      add :metadata, :map, default: %{}
      add :created_by_id, references(:user_roles, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:courses, [:school_id])
    create_if_not_exists index(:courses, [:subject, :grade])
    create_if_not_exists index(:courses, [:created_by_id])

    create_if_not_exists table(:chapters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:chapters, [:course_id])
    create_if_not_exists index(:chapters, [:course_id, :position])

    create_if_not_exists table(:sections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :chapter_id, references(:chapters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:sections, [:chapter_id])
    create_if_not_exists index(:sections, [:chapter_id, :position])
  end
end
