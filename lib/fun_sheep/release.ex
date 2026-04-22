defmodule FunSheep.Release do
  @moduledoc """
  Tasks that can be run from a release (without Mix).

  Used by the Dockerfile boot command and by one-off Cloud Run Jobs.

  ## Examples

      bin/fun_sheep eval 'FunSheep.Release.migrate()'
      bin/fun_sheep eval 'FunSheep.Release.ingest_us_schools()'
  """

  require Logger

  @app :fun_sheep

  # Threshold below which we assume NCES CCD was never ingested into this
  # DB. NCES CCD has ~130K US K-12 schools; anything under 10K means the
  # release is running without school data and student profile setup will
  # fail to find schools.
  @low_school_count_threshold 10_000

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)
          warn_if_school_registry_empty(repo)
        end)
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  One-shot bulk ingestion of the NCES Common Core of Data for US K-12
  schools. Runs `lea` (districts) first so school rows can reference them,
  then `school`. Results are recorded in the `ingestion_runs` audit table.

  Safe to re-run: both datasets upsert on `(source, source_id)`, so a
  second run after a new annual file is published updates existing rows
  and inserts new ones.

  Invoked once per deployment environment (typically via a Cloud Run Job
  on `funsheep-api`'s image) — NOT on every boot.
  """
  def ingest_us_schools do
    {:ok, _} = Application.ensure_all_started(@app)

    Logger.info("release.ingest_us_schools starting")

    with {:ok, lea_stats} <- FunSheep.Ingest.run("nces_ccd", "lea"),
         {:ok, school_stats} <- FunSheep.Ingest.run("nces_ccd", "school") do
      Logger.info("release.ingest_us_schools completed",
        lea: lea_stats,
        school: school_stats
      )

      {:ok, %{lea: lea_stats, school: school_stats}}
    else
      {:error, reason} = err ->
        Logger.error("release.ingest_us_schools failed", reason: inspect(reason))
        err
    end
  end

  defp warn_if_school_registry_empty(repo) do
    count = repo.aggregate(FunSheep.Geo.School, :count, :id)

    if count < @low_school_count_threshold do
      Logger.warning(
        "school registry has #{count} rows — under #{@low_school_count_threshold}. " <>
          "Run `bin/fun_sheep eval 'FunSheep.Release.ingest_us_schools()'` " <>
          "to populate NCES CCD."
      )
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
