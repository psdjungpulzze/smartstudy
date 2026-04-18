defmodule FunSheep.Repo.Migrations.CreateStudyGuidesAndHobbies do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:study_guides, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :test_schedule_id, references(:test_schedules, type: :binary_id, on_delete: :nilify_all)
      add :content, :map, null: false
      add :generated_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:study_guides, [:user_role_id])
    create_if_not_exists index(:study_guides, [:test_schedule_id])

    create_if_not_exists table(:hobbies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :category, :string, null: false
      add :region_relevance, :map

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists unique_index(:hobbies, [:name])

    create_if_not_exists table(:student_hobbies, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :hobby_id, references(:hobbies, type: :binary_id, on_delete: :delete_all), null: false
      add :specific_interests, :map

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists unique_index(:student_hobbies, [:user_role_id, :hobby_id])
    create_if_not_exists index(:student_hobbies, [:hobby_id])
  end
end
