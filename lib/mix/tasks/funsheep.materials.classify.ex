defmodule Mix.Tasks.Funsheep.Materials.Classify do
  @shortdoc "Phase 2: enqueue the material classifier for completed OCR'd materials"

  @moduledoc """
  Backfills `uploaded_materials.classified_kind` for existing materials
  that completed OCR before the Phase 2 classifier shipped. Without the
  backfill, the Phase 2 routing guardrail (`route/1` in
  `FunSheep.Workers.MaterialClassificationWorker`) falls back to the
  legacy user-supplied `material_kind` — which is exactly what let an
  answer-key image get extracted as a textbook.

  Safe to re-run; the worker itself is a no-op when `classified_kind`
  is already set.

  ## Usage

      # dry-run — prints how many materials would be enqueued
      mix funsheep.materials.classify --prod-db

      # scope to a single course
      mix funsheep.materials.classify --prod-db \\
          --course d44628ca-6579-48da-a83b-466e12b1c19b --confirm

      # all eligible materials across all courses
      mix funsheep.materials.classify --prod-db --confirm
  """

  use Mix.Task

  alias FunSheep.Repo

  @switches [course: :string, confirm: :boolean, prod_db: :boolean]

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

    {sql, params} = candidate_sql(course_id)
    %{rows: rows} = Repo.query!(sql, params)
    ids = Enum.map(rows, fn [id] -> Ecto.UUID.load!(id) end)

    Mix.shell().info(
      "\n=== MATERIAL CLASSIFIER BACKFILL (#{if dry_run?, do: "DRY-RUN", else: "CONFIRMED"}) ==="
    )

    if course_id, do: Mix.shell().info("Scoped to course: #{course_id}")
    Mix.shell().info("Candidates: #{length(ids)}")

    cond do
      ids == [] ->
        Mix.shell().info("Nothing to enqueue.")

      dry_run? ->
        Mix.shell().info("(dry-run — pass --confirm to enqueue classifier jobs)")

      true ->
        Enum.each(ids, fn id ->
          FunSheep.Workers.MaterialClassificationWorker.enqueue(id)
        end)

        Mix.shell().info("Enqueued #{length(ids)} classifier jobs.")
    end
  end

  defp candidate_sql(nil) do
    {"""
     SELECT id FROM uploaded_materials
     WHERE ocr_status = 'completed' AND classified_kind IS NULL
     """, []}
  end

  defp candidate_sql(course_id) do
    {"""
     SELECT id FROM uploaded_materials
     WHERE ocr_status = 'completed' AND classified_kind IS NULL
       AND course_id = $1
     """, [Ecto.UUID.dump!(course_id)]}
  end
end
