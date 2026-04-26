defmodule FunSheep.Repo.Migrations.MigrateCourseGradeToGradesArray do
  use Ecto.Migration

  def up do
    # Add array column with default empty array
    alter table(:courses) do
      add :grades, {:array, :string}, null: false, default: []
    end

    # Backfill: wrap each existing single grade in an array
    execute("UPDATE courses SET grades = ARRAY[grade] WHERE grade IS NOT NULL AND grade != ''")

    # Drop old column and its index
    drop_if_exists index(:courses, [:subject, :grade])

    alter table(:courses) do
      remove :grade
    end

    # Create GIN index on the array column for overlap queries
    create index(:courses, [:grades], using: :gin)
  end

  def down do
    drop_if_exists index(:courses, [:grades])

    alter table(:courses) do
      add :grade, :string
    end

    # Restore from first element of grades array
    execute("UPDATE courses SET grade = grades[1] WHERE array_length(grades, 1) > 0")

    drop_if_exists index(:courses, [:grades])
    create index(:courses, [:subject, :grade])

    alter table(:courses) do
      remove :grades
    end
  end
end
