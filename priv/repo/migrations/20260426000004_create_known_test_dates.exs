defmodule FunSheep.Repo.Migrations.CreateKnownTestDates do
  use Ecto.Migration

  def change do
    create table(:known_test_dates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :test_type, :string, null: false
      add :test_name, :string, null: false
      add :test_date, :date, null: false
      add :registration_deadline, :date
      add :late_registration_deadline, :date
      add :score_release_date, :date
      add :source_url, :string
      add :region, :string, null: false, default: "us"
      add :last_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:known_test_dates, [:test_type, :test_date, :region])
    create index(:known_test_dates, [:test_type])
    create index(:known_test_dates, [:test_date])
  end
end
