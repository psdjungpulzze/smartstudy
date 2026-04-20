defmodule FunSheep.Repo.Migrations.ExtendGeoForIngestion do
  @moduledoc """
  Extends the geographic hierarchy to support ingestion from authoritative
  registries (NCES CCD, IPEDS, GIAS, ACARA, KR NEIS, WHED, IB, OSM, ...).

  Design:
    * Natural-key upserts via `(source, source_id)` unique index on every
      institution-level table (districts, schools, universities).
    * UUID primary keys remain stable so existing FKs (user_roles.school_id,
      courses.school_id, questions.school_id) are unaffected.
    * `district_id` is now nullable — many countries have no district tier,
      and private/international schools are often independent.
    * Denormalized `country_id` + `state_id` on schools and universities for
      fast profile/search filters without joining through districts.
    * Universities get their own table (separate ingestion path, different
      PIDs: IPEDS UNITID, WHED global id).

  See .claude/rules/i/ (or CLAUDE.md) "No fake data" rule — every row in
  these tables must originate from a real registry or direct user input.
  """

  use Ecto.Migration

  def change do
    # ── Countries: expand ISO coverage ─────────────────────────────────────────
    alter table(:countries) do
      add_if_not_exists :iso3, :string, size: 3
      add_if_not_exists :numeric_code, :string, size: 3
      add_if_not_exists :native_name, :string
    end

    # ── States: ISO 3166-2 subdivision code (e.g. "US-CA", "KR-11") ────────────
    alter table(:states) do
      add_if_not_exists :iso_code, :string, size: 10
      add_if_not_exists :fips_code, :string, size: 4
      add_if_not_exists :native_name, :string
      add_if_not_exists :subdivision_type, :string, size: 32
    end

    create_if_not_exists unique_index(:states, [:iso_code])

    # ── Districts: PIDs + denormalized country_id + metadata ───────────────────
    alter table(:districts) do
      add_if_not_exists :source, :string, size: 32
      add_if_not_exists :source_id, :string, size: 64
      add_if_not_exists :nces_leaid, :string, size: 12
      add_if_not_exists :native_name, :string
      add_if_not_exists :country_id, references(:countries, type: :binary_id, on_delete: :restrict)
      add_if_not_exists :type, :string, size: 32
      add_if_not_exists :operational_status, :string, size: 16
      add_if_not_exists :address, :string
      add_if_not_exists :city, :string
      add_if_not_exists :postal_code, :string, size: 16
      add_if_not_exists :phone, :string, size: 32
      add_if_not_exists :website, :string
      add_if_not_exists :lat, :float
      add_if_not_exists :lng, :float
      add_if_not_exists :metadata, :map, default: %{}
    end

    create_if_not_exists unique_index(:districts, [:source, :source_id],
                          name: :districts_source_pid_index
                        )

    create_if_not_exists index(:districts, [:country_id])
    create_if_not_exists index(:districts, [:nces_leaid])

    # ── Schools: make district optional, add PIDs, location, type, grades ──────
    execute(
      "ALTER TABLE schools ALTER COLUMN district_id DROP NOT NULL",
      "ALTER TABLE schools ALTER COLUMN district_id SET NOT NULL"
    )

    alter table(:schools) do
      add_if_not_exists :source, :string, size: 32
      add_if_not_exists :source_id, :string, size: 64
      add_if_not_exists :nces_id, :string, size: 14
      add_if_not_exists :urn, :string, size: 12
      add_if_not_exists :acara_id, :string, size: 16
      add_if_not_exists :kr_code, :string, size: 32
      add_if_not_exists :ib_code, :string, size: 16
      add_if_not_exists :native_name, :string
      add_if_not_exists :country_id, references(:countries, type: :binary_id, on_delete: :restrict)
      add_if_not_exists :state_id, references(:states, type: :binary_id, on_delete: :restrict)
      add_if_not_exists :type, :string, size: 32
      add_if_not_exists :level, :string, size: 16
      add_if_not_exists :lowest_grade, :string, size: 8
      add_if_not_exists :highest_grade, :string, size: 8
      add_if_not_exists :operational_status, :string, size: 16
      add_if_not_exists :address, :string
      add_if_not_exists :city, :string
      add_if_not_exists :postal_code, :string, size: 16
      add_if_not_exists :phone, :string, size: 32
      add_if_not_exists :website, :string
      add_if_not_exists :lat, :float
      add_if_not_exists :lng, :float
      add_if_not_exists :locale_code, :string, size: 4
      add_if_not_exists :student_count, :integer
      add_if_not_exists :opened_at, :date
      add_if_not_exists :closed_at, :date
      add_if_not_exists :metadata, :map, default: %{}
    end

    create_if_not_exists unique_index(:schools, [:source, :source_id],
                          name: :schools_source_pid_index
                        )

    create_if_not_exists index(:schools, [:country_id])
    create_if_not_exists index(:schools, [:state_id])
    create_if_not_exists index(:schools, [:nces_id])
    create_if_not_exists index(:schools, [:urn])
    create_if_not_exists index(:schools, [:kr_code])
    create_if_not_exists index(:schools, [:name])

    # ── Universities: separate table for higher education ────────────────────
    # K-12 ingestion (NCES CCD, GIAS, ACARA, NEIS) populates `schools`.
    # Higher-ed ingestion (IPEDS, WHED) populates this table. Different PIDs,
    # different classification schemes, and different consumer UIs.
    create_if_not_exists table(:universities, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :name, :string, null: false
      add :native_name, :string

      # Natural keys
      add :source, :string, size: 32, null: false
      add :source_id, :string, size: 64, null: false
      add :ipeds_unitid, :string, size: 10
      add :whed_id, :string, size: 32
      add :opeid, :string, size: 16
      add :ror_id, :string, size: 16

      # Geography (denormalized for fast filters)
      add :country_id, references(:countries, type: :binary_id, on_delete: :restrict), null: false
      add :state_id, references(:states, type: :binary_id, on_delete: :restrict)

      # Classification
      # public | private_nonprofit | private_forprofit
      add :control, :string, size: 24
      # 4-year | 2-year | less-than-2-year
      add :level, :string, size: 24
      add :type, :string, size: 32
      add :operational_status, :string, size: 16

      # Location / contact
      add :address, :string
      add :city, :string
      add :postal_code, :string, size: 16
      add :phone, :string, size: 32
      add :website, :string
      add :lat, :float
      add :lng, :float

      add :student_count, :integer
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists unique_index(:universities, [:source, :source_id],
                          name: :universities_source_pid_index
                        )

    create_if_not_exists index(:universities, [:country_id])
    create_if_not_exists index(:universities, [:state_id])
    create_if_not_exists index(:universities, [:ipeds_unitid])
    create_if_not_exists index(:universities, [:whed_id])
    create_if_not_exists index(:universities, [:name])

    # ── Ingestion runs: audit trail for each ingestion attempt ────────────────
    create_if_not_exists table(:ingestion_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source, :string, null: false, size: 32
      add :dataset, :string, null: false, size: 64
      add :status, :string, null: false, size: 16
      add :object_key, :string
      add :row_count, :integer
      add :inserted_count, :integer
      add :updated_count, :integer
      add :error_count, :integer
      add :error_sample, :text
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:ingestion_runs, [:source, :dataset, :started_at])
  end
end
