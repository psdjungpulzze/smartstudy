defmodule FunSheep.Repo.Migrations.CreateFixedTestAssignments do
  use Ecto.Migration

  def change do
    create table(:fixed_test_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :bank_id, references(:fixed_test_banks, type: :binary_id, on_delete: :delete_all),
        null: false

      add :assigned_by_id, references(:user_roles, type: :binary_id, on_delete: :restrict),
        null: false

      add :assigned_to_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :due_at, :utc_datetime
      add :note, :text

      timestamps(type: :utc_datetime)
    end

    create index(:fixed_test_assignments, [:bank_id])
    create index(:fixed_test_assignments, [:assigned_to_id])
    create index(:fixed_test_assignments, [:assigned_by_id])
    create unique_index(:fixed_test_assignments, [:bank_id, :assigned_to_id])
  end
end
