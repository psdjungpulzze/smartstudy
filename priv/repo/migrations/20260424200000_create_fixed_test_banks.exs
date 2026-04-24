defmodule FunSheep.Repo.Migrations.CreateFixedTestBanks do
  use Ecto.Migration

  def change do
    create table(:fixed_test_banks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text

      add :created_by_id, references(:user_roles, type: :binary_id, on_delete: :restrict),
        null: false

      add :course_id, references(:courses, type: :binary_id, on_delete: :nilify_all)
      add :visibility, :string, null: false, default: "private"
      add :shuffle_questions, :boolean, null: false, default: false
      add :time_limit_minutes, :integer
      add :max_attempts, :integer
      add :version, :integer, null: false, default: 1
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:fixed_test_banks, [:created_by_id])
    create index(:fixed_test_banks, [:course_id])
    create index(:fixed_test_banks, [:archived_at])
  end
end
