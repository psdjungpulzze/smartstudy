defmodule FunSheep.Repo.Migrations.CreateDiscoveredTocs do
  use Ecto.Migration

  def change do
    create table(:discovered_tocs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :course_id,
          references(:courses, type: :binary_id, on_delete: :delete_all),
          null: false

      add :source, :string, null: false
      add :chapter_count, :integer, null: false
      add :ocr_char_count, :integer, default: 0, null: false
      add :chapters, :map, null: false
      add :score, :float, null: false
      add :applied_at, :utc_datetime
      add :superseded_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:discovered_tocs, [:course_id, :applied_at])
    create index(:discovered_tocs, [:course_id, :score])

    # At most one "currently-applied" TOC per course. Applied rows have a
    # non-null applied_at AND null superseded_at. Enforced via a partial
    # unique index so older applied-then-superseded rows don't conflict.
    create unique_index(:discovered_tocs, [:course_id],
             where: "applied_at IS NOT NULL AND superseded_at IS NULL",
             name: :discovered_tocs_one_applied_per_course
           )
  end
end
