defmodule FunSheep.Repo.Migrations.AddClassificationToQuestions do
  @moduledoc """
  Adds skill-tag classification state to questions (North Star invariant I-1).

  Questions become adaptive-eligible only after they carry a fine-grained skill
  identifier. We use the existing `sections` table as the skill unit, and track
  how confident we are in the tagging so diagnostic flows can filter out
  uncategorized or low-confidence rows (invariant I-15).

  Backfill: questions that already have `section_id` set were tagged during
  content discovery — we trust those as `admin_reviewed`. Everything else stays
  `uncategorized` until the classification worker runs.
  """

  use Ecto.Migration

  def change do
    execute(
      "CREATE TYPE classification_status AS ENUM ('uncategorized', 'ai_classified', 'admin_reviewed', 'low_confidence')",
      "DROP TYPE IF EXISTS classification_status"
    )

    alter table(:questions) do
      add :classification_status, :classification_status,
        default: "uncategorized",
        null: false

      add :classification_confidence, :float
      add :classified_at, :utc_datetime
    end

    create index(:questions, [:classification_status])
    create index(:questions, [:section_id, :classification_status])

    # Trust existing section_id assignments — they were produced by content
    # discovery and passed validation. The `down` side is intentionally empty:
    # dropping the columns above reverses the backfill.
    execute(
      """
      UPDATE questions
      SET classification_status = 'admin_reviewed',
          classified_at = inserted_at
      WHERE section_id IS NOT NULL
      """,
      ""
    )
  end
end
