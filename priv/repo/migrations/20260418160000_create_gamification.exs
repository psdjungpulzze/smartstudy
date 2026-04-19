defmodule FunSheep.Repo.Migrations.CreateGamification do
  use Ecto.Migration

  def change do
    # ── Streaks ──────────────────────────────────────────────────────────────
    create table(:streaks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :current_streak, :integer, default: 0, null: false
      add :longest_streak, :integer, default: 0, null: false
      add :last_activity_date, :date
      add :streak_frozen_until, :date
      add :wool_level, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:streaks, [:user_role_id])

    # ── XP Events ────────────────────────────────────────────────────────────
    create table(:xp_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :amount, :integer, null: false
      add :source, :string, null: false
      add :source_id, :binary_id
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:xp_events, [:user_role_id])
    create index(:xp_events, [:user_role_id, :inserted_at])

    # ── Achievements ─────────────────────────────────────────────────────────
    create table(:achievements, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :achievement_type, :string, null: false
      add :metadata, :map, default: %{}
      add :earned_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:achievements, [:user_role_id])
    create unique_index(:achievements, [:user_role_id, :achievement_type])
  end
end
