defmodule FunSheep.Ingest do
  @moduledoc """
  Ingestion context — orchestrates downloading, parsing, and upserting of
  authoritative school/district/university registries.

  Each registry has a module under `FunSheep.Ingest.Sources.*` that exposes:

    * `@behaviour FunSheep.Ingest.Source`
    * `source/0` — stable id (e.g. `"nces_ccd"`)
    * `datasets/0` — list of datasets this source provides
    * `run/1` — accepts dataset name, does fetch + parse + upsert,
      returns `{:ok, stats}` or `{:error, reason}`

  Use `FunSheep.Ingest.run/2` to invoke from IEx, the Mix task, or an
  Oban worker.
  """

  require Logger

  alias FunSheep.Geo.IngestionRun
  alias FunSheep.Repo

  @type source :: String.t()
  @type dataset :: String.t()
  @type stats :: %{
          required(:inserted) => integer(),
          required(:updated) => integer(),
          optional(:errors) => integer(),
          optional(atom()) => term()
        }

  @sources %{
    "nces_ccd" => FunSheep.Ingest.Sources.NcesCcd,
    "ipeds" => FunSheep.Ingest.Sources.Ipeds,
    "kr_neis" => FunSheep.Ingest.Sources.KrNeis,
    "gias_uk" => FunSheep.Ingest.Sources.GiasUk,
    "acara_au" => FunSheep.Ingest.Sources.AcaraAu,
    "ca_provincial" => FunSheep.Ingest.Sources.CaProvincial,
    "ror" => FunSheep.Ingest.Sources.Whed,
    "ib" => FunSheep.Ingest.Sources.IbWorldSchools
  }

  @doc """
  List all registered sources.
  """
  @spec sources() :: [{source(), module()}]
  def sources, do: Enum.to_list(@sources)

  @doc """
  Look up the module implementing `source`.
  """
  @spec lookup(source()) :: {:ok, module()} | :error
  def lookup(source) when is_binary(source), do: Map.fetch(@sources, source)

  @doc """
  Run an ingestion pipeline end-to-end with a persistent audit record.

  Creates an `ingestion_runs` row in status `pending`, delegates to the
  source module, then patches the row with the final counts. Exceptions
  are caught so a partial failure still leaves a visible audit record.
  """
  @spec run(source(), dataset(), keyword()) :: {:ok, stats()} | {:error, term()}
  def run(source, dataset, opts \\ []) do
    with {:ok, mod} <- lookup(source) do
      run = start_run(source, dataset)

      try do
        case apply(mod, :run, [dataset, opts]) do
          {:ok, stats} ->
            finalize_run(run, "completed", stats)
            Logger.info("ingest completed",
              source: source,
              dataset: dataset,
              stats: stats
            )
            {:ok, stats}

          {:error, reason} = err ->
            finalize_run(run, "failed", %{error: inspect(reason)})
            Logger.error("ingest failed", source: source, dataset: dataset, reason: inspect(reason))
            err
        end
      rescue
        e ->
          stack = __STACKTRACE__
          message = Exception.format(:error, e, stack)
          finalize_run(run, "failed", %{error: message})
          Logger.error("ingest raised", source: source, dataset: dataset, error: message)
          {:error, {:exception, Exception.message(e)}}
      end
    else
      :error -> {:error, {:unknown_source, source}}
    end
  end

  defp start_run(source, dataset) do
    %IngestionRun{}
    |> IngestionRun.changeset(%{
      source: source,
      dataset: dataset,
      status: "pending",
      started_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert!()
  end

  defp finalize_run(run, status, stats) do
    run
    |> IngestionRun.changeset(%{
      status: status,
      finished_at: DateTime.utc_now() |> DateTime.truncate(:second),
      inserted_count: Map.get(stats, :inserted),
      updated_count: Map.get(stats, :updated),
      row_count: Map.get(stats, :rows),
      error_count: Map.get(stats, :errors),
      error_sample: Map.get(stats, :error),
      object_key: Map.get(stats, :object_key),
      metadata: Map.drop(stats, [:inserted, :updated, :rows, :errors, :error, :object_key])
    })
    |> Repo.update!()
  end
end
