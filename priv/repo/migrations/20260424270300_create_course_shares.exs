defmodule FunSheep.Repo.Migrations.CreateCourseShares do
  use Ecto.Migration

  def change do
    create table(:course_shares, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :sharer_id, references(:user_roles, type: :binary_id, on_delete: :delete_all), null: false
      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false
      add :message, :text
      add :share_count, :integer, default: 1, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create table(:course_share_recipients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :share_id, references(:course_shares, type: :binary_id, on_delete: :delete_all), null: false
      add :recipient_id, references(:user_roles, type: :binary_id, on_delete: :delete_all), null: false
      add :seen_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:course_shares, [:sharer_id])
    create index(:course_shares, [:course_id])
    create index(:course_shares, [:sharer_id, :course_id])
    create index(:course_share_recipients, [:share_id])
    create index(:course_share_recipients, [:recipient_id])
    create unique_index(:course_share_recipients, [:share_id, :recipient_id])
  end
end
