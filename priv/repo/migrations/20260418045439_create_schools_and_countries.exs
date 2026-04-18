defmodule FunSheep.Repo.Migrations.CreateSchoolsAndCountries do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:countries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :code, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists unique_index(:countries, [:code])

    create_if_not_exists table(:states, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :code, :string
      add :country_id, references(:countries, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:states, [:country_id])

    create_if_not_exists table(:districts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :state_id, references(:states, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:districts, [:state_id])

    create_if_not_exists table(:schools, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      add :district_id, references(:districts, type: :binary_id, on_delete: :restrict),
        null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:schools, [:district_id])
  end
end
