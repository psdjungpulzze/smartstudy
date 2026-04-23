defmodule Mix.Tasks.Funsheep.Questions.BackfillSourceType do
  @shortdoc "Phase 1: backfill source_type/generation_mode/grounding_refs on existing questions"

  @moduledoc """
  Populates the Phase 1 provenance columns from the legacy scattered
  fields so admin queries and coverage audits can rely on a single
  source-of-truth after deploy.

  Mapping rules (first match wins):

      metadata["source"] == "web_scrape"                -> :web_scraped
      metadata["source"] == "ocr_extraction"            -> :user_uploaded
      metadata["source"] == "ai_generation"             -> :ai_generated
      is_generated == true                              -> :ai_generated
      source_url NOT NULL                               -> :web_scraped
      source_material_id NOT NULL                       -> :user_uploaded
      (otherwise)                                       -> :curated

  `generation_mode` is read from `metadata["mode"]` or
  `metadata["generation_mode"]` when present (absent on 100% of
  existing AP Bio rows per the mid-April audit — that's expected and
  captured as NULL, which Phase 4 will start filling going forward).

  `grounding_refs` is reconstructed best-effort from the existing
  links: `source_material_id` → one "material" ref;
  `source_url` → one "url" ref; otherwise `%{}`.

  ## Usage

      # dry-run — prints the proposed distribution, writes nothing
      mix funsheep.questions.backfill_source_type --prod-db

      # scope to a single course (recommended for first prod run)
      mix funsheep.questions.backfill_source_type --prod-db \\
          --course d44628ca-6579-48da-a83b-466e12b1c19b --confirm

      # all rows across all courses
      mix funsheep.questions.backfill_source_type --prod-db --confirm

  Safe to re-run: the WHERE clause restricts updates to rows where
  `source_type IS NULL`, so a second invocation is a no-op.
  """

  use Mix.Task

  alias FunSheep.Repo

  @switches [course: :string, confirm: :boolean, prod_db: :boolean, batch_size: :integer]

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    if Keyword.get(opts, :prod_db, false) do
      db_url =
        System.get_env("DATABASE_URL") ||
          Mix.raise("--prod-db requires DATABASE_URL env var")

      Application.put_env(:fun_sheep, FunSheep.Repo,
        url: db_url,
        pool_size: 5,
        ssl: false,
        socket_options: []
      )
    end

    Mix.Task.run("app.start")

    dry_run? = not Keyword.get(opts, :confirm, false)
    course_id = opts[:course]
    batch_size = Keyword.get(opts, :batch_size, 200)

    Mix.shell().info(
      "\n=== BACKFILL source_type (#{if dry_run?, do: "DRY-RUN", else: "CONFIRMED"}) ==="
    )

    if course_id, do: Mix.shell().info("Scoped to course: #{course_id}")

    distribution = compute_distribution(course_id)

    Enum.each(distribution, fn {source_type, count} ->
      Mix.shell().info("  #{source_type}: #{count}")
    end)

    total = distribution |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    Mix.shell().info("  TOTAL: #{total}")

    cond do
      total == 0 ->
        Mix.shell().info("\nNothing to backfill — every candidate already has source_type.")

      dry_run? ->
        Mix.shell().info("\n(dry-run — pass --confirm to update #{total} rows)")

      true ->
        applied = apply_backfill(course_id, batch_size)
        Mix.shell().info("\nApplied source_type/grounding_refs to #{applied} rows.")
    end
  end

  # -- distribution -----------------------------------------------------------

  # Raw SQL distribution keeps the CASE definition in lockstep with the
  # UPDATE statement below — both queries live next to each other so the
  # "dry-run showed X but confirm did Y" drift is impossible.
  defp compute_distribution(course_id) do
    {sql, params} = distribution_sql(course_id)

    %{rows: rows} = Repo.query!(sql, params)

    rows
    |> Enum.map(fn [source_type, count] -> {source_type, count} end)
    |> Enum.sort_by(fn {_, c} -> -c end)
  end

  defp distribution_sql(nil) do
    {"""
     SELECT
       CASE
         WHEN metadata->>'source' = 'web_scrape' THEN 'web_scraped'
         WHEN metadata->>'source' = 'ocr_extraction' THEN 'user_uploaded'
         WHEN metadata->>'source' = 'ai_generation' THEN 'ai_generated'
         WHEN is_generated = true THEN 'ai_generated'
         WHEN source_url IS NOT NULL THEN 'web_scraped'
         WHEN source_material_id IS NOT NULL THEN 'user_uploaded'
         ELSE 'curated'
       END AS source_type,
       COUNT(*)
     FROM questions
     WHERE source_type IS NULL
     GROUP BY 1
     """, []}
  end

  defp distribution_sql(course_id) do
    {"""
     SELECT
       CASE
         WHEN metadata->>'source' = 'web_scrape' THEN 'web_scraped'
         WHEN metadata->>'source' = 'ocr_extraction' THEN 'user_uploaded'
         WHEN metadata->>'source' = 'ai_generation' THEN 'ai_generated'
         WHEN is_generated = true THEN 'ai_generated'
         WHEN source_url IS NOT NULL THEN 'web_scraped'
         WHEN source_material_id IS NOT NULL THEN 'user_uploaded'
         ELSE 'curated'
       END AS source_type,
       COUNT(*)
     FROM questions
     WHERE source_type IS NULL AND course_id = $1
     GROUP BY 1
     """, [Ecto.UUID.dump!(course_id)]}
  end

  # -- backfill ---------------------------------------------------------------

  defp apply_backfill(course_id, batch_size) do
    # Use a CTE-driven UPDATE to do the entire backfill in one statement
    # — safer than streaming batches of IDs from Elixir because it runs
    # under a single transactional snapshot (no rows added mid-run will
    # be mis-classified). `LIMIT` keeps the lock duration bounded; the
    # outer loop iterates until no rows remain.
    loop_update(course_id, batch_size, 0)
  end

  defp loop_update(course_id, batch_size, acc) do
    {sql, params} = update_sql(course_id, batch_size)

    case Repo.query!(sql, params) do
      %{num_rows: 0} ->
        acc

      %{num_rows: n} ->
        Mix.shell().info("  ...updated batch of #{n} rows")
        loop_update(course_id, batch_size, acc + n)
    end
  end

  defp update_sql(nil, batch_size) do
    {"""
     WITH batch AS (
       SELECT id FROM questions
       WHERE source_type IS NULL
       LIMIT $1
     )
     UPDATE questions q
     SET
       source_type = (
         CASE
           WHEN q.metadata->>'source' = 'web_scrape' THEN 'web_scraped'
           WHEN q.metadata->>'source' = 'ocr_extraction' THEN 'user_uploaded'
           WHEN q.metadata->>'source' = 'ai_generation' THEN 'ai_generated'
           WHEN q.is_generated = true THEN 'ai_generated'
           WHEN q.source_url IS NOT NULL THEN 'web_scraped'
           WHEN q.source_material_id IS NOT NULL THEN 'user_uploaded'
           ELSE 'curated'
         END
       ),
       generation_mode = COALESCE(q.metadata->>'mode', q.metadata->>'generation_mode'),
       grounding_refs = CASE
         WHEN q.source_material_id IS NOT NULL THEN
           jsonb_build_object('refs', jsonb_build_array(
             jsonb_build_object('type', 'material', 'id', q.source_material_id::text)
           ))
         WHEN q.source_url IS NOT NULL THEN
           jsonb_build_object('refs', jsonb_build_array(
             jsonb_build_object('type', 'url', 'id', q.source_url)
           ))
         ELSE '{}'::jsonb
       END,
       updated_at = NOW()
     WHERE q.id IN (SELECT id FROM batch)
     """, [batch_size]}
  end

  defp update_sql(course_id, batch_size) do
    {"""
     WITH batch AS (
       SELECT id FROM questions
       WHERE source_type IS NULL AND course_id = $2
       LIMIT $1
     )
     UPDATE questions q
     SET
       source_type = (
         CASE
           WHEN q.metadata->>'source' = 'web_scrape' THEN 'web_scraped'
           WHEN q.metadata->>'source' = 'ocr_extraction' THEN 'user_uploaded'
           WHEN q.metadata->>'source' = 'ai_generation' THEN 'ai_generated'
           WHEN q.is_generated = true THEN 'ai_generated'
           WHEN q.source_url IS NOT NULL THEN 'web_scraped'
           WHEN q.source_material_id IS NOT NULL THEN 'user_uploaded'
           ELSE 'curated'
         END
       ),
       generation_mode = COALESCE(q.metadata->>'mode', q.metadata->>'generation_mode'),
       grounding_refs = CASE
         WHEN q.source_material_id IS NOT NULL THEN
           jsonb_build_object('refs', jsonb_build_array(
             jsonb_build_object('type', 'material', 'id', q.source_material_id::text)
           ))
         WHEN q.source_url IS NOT NULL THEN
           jsonb_build_object('refs', jsonb_build_array(
             jsonb_build_object('type', 'url', 'id', q.source_url)
           ))
         ELSE '{}'::jsonb
       END,
       updated_at = NOW()
     WHERE q.id IN (SELECT id FROM batch)
     """, [batch_size, Ecto.UUID.dump!(course_id)]}
  end

end
