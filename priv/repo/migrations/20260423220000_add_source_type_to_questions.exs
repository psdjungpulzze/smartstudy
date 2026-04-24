defmodule FunSheep.Repo.Migrations.AddSourceTypeToQuestions do
  use Ecto.Migration

  @moduledoc """
  Phase 1 of the question-sourcing rebuild: unify provenance.

  Today a question's origin is scattered across four fields:
  `is_generated` (bool), `source_url`, `source_material_id`, and
  `metadata["source"]`. Each gets set by a different worker with no
  schema-level guarantee, which means admin review, analytics, and
  coverage queries all have to reimplement the "where did this come
  from" logic.

  This migration adds:

  * `source_type` (enum) — the single load-bearing provenance field.
    `:web_scraped | :user_uploaded | :ai_generated | :curated`
  * `generation_mode` (string) — for `:ai_generated` rows, tracks which
    path produced them (e.g. `"from_curriculum"`, `"from_material"`,
    `"from_web_context"`). The worker code already accepts this argument
    but never persisted it — see the mid-April prod audit showing 100%
    of AI-generated rows with `mode: (missing)`.
  * `grounding_refs` (jsonb) — list of `{type, id_or_url}` entries
    identifying the materials/URLs that fed the generator prompt.
    Supports later coverage audits (Phase 6) and admin source-health UI
    (Phase 8).

  Backfill lives in a separate script so this migration is fast and
  reversible — do not do the backfill inline here, see
  `lib/mix/tasks/funsheep.questions.backfill_source_type.ex`.

  Legacy fields (`is_generated`, `source_url`, `source_material_id`,
  `metadata["source"]`) are kept for one release so the worker code
  can roll forward incrementally. They'll be dropped in a follow-up
  once every writer has been migrated.
  """

  def change do
    alter table(:questions) do
      add :source_type, :string
      add :generation_mode, :string
      add :grounding_refs, :map, default: %{}
    end

    # Index supports the new Questions context helpers:
    #   questions_by_source_type/2 (admin filter by source)
    #   coverage_by_chapter/1 (source-breakdown in coverage heatmaps)
    # Partial index — only indexing rows that have been migrated — keeps
    # the index small during the backfill window.
    create index(:questions, [:course_id, :source_type],
             where: "source_type IS NOT NULL",
             name: :questions_course_id_source_type_index
           )
  end
end
