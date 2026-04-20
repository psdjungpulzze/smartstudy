defmodule FunSheep.Workers.IngestWorker do
  @moduledoc """
  Oban worker that runs a single `FunSheep.Ingest` source/dataset pair.

  Jobs are unique on `(source, dataset)` within a 1-hour window so two
  operators kicking off the same pipeline don't clobber each other.
  `max_attempts: 3` with exponential backoff covers transient network
  failures against upstream registries.
  """

  use Oban.Worker,
    queue: :ingest,
    max_attempts: 3,
    unique: [
      fields: [:worker, :args],
      keys: [:source, :dataset],
      period: 3600
    ]

  require Logger

  alias FunSheep.Ingest

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source" => source, "dataset" => dataset} = args}) do
    opts = build_opts(args)

    case Ingest.run(source, dataset, opts) do
      {:ok, stats} ->
        Logger.info("ingest worker completed",
          source: source,
          dataset: dataset,
          stats: stats
        )

        :ok

      {:error, reason} ->
        Logger.error("ingest worker failed",
          source: source,
          dataset: dataset,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(60)

  defp build_opts(args) do
    []
    |> maybe_put(:url, args["url"])
    |> maybe_put(:api_key, args["api_key"])
    |> maybe_put(:force, args["force"])
    |> maybe_put(:path, args["path"])
    |> maybe_put(:date, parse_date(args["date"]))
  end

  defp maybe_put(opts, _k, nil), do: opts
  defp maybe_put(opts, k, v), do: Keyword.put(opts, k, v)

  defp parse_date(nil), do: nil

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end
