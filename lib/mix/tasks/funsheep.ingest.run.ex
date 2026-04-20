defmodule Mix.Tasks.Funsheep.Ingest.Run do
  @shortdoc "Run an ingestion pipeline for a school/district/university registry"

  @moduledoc """
  Run an ingestion pipeline for authoritative school/district/university
  registries (NCES CCD, IPEDS, NEIS, GIAS, ACARA, ROR, IB, ...).

  ## Usage

      # Synchronous — runs in this process, good for first-time setup
      mix funsheep.ingest.run nces_ccd lea
      mix funsheep.ingest.run nces_ccd school
      mix funsheep.ingest.run ipeds hd
      mix funsheep.ingest.run kr_neis schools
      mix funsheep.ingest.run gias_uk establishments
      mix funsheep.ingest.run ror universities --url https://zenodo.org/...

      # Async — enqueue an Oban job, return immediately
      mix funsheep.ingest.run nces_ccd school --async

      # List available source/dataset pairs
      mix funsheep.ingest.run --list

  ## Options

    * `--async` — enqueue as an Oban job instead of running inline
    * `--force` — bypass the cache and re-download the upstream file
    * `--url URL` — override the upstream URL (for new-year file releases)
    * `--api-key KEY` — override the API key env var for the source
    * `--date YYYY-MM-DD` — used by date-parameterized sources (GIAS)
    * `--path PATH` — used by file-based sources (IB snapshot)
    * `--list` — print all registered sources and exit
  """

  use Mix.Task

  alias FunSheep.Ingest
  alias FunSheep.Workers.IngestWorker

  @switches [
    async: :boolean,
    force: :boolean,
    list: :boolean,
    url: :string,
    api_key: :string,
    date: :string,
    path: :string
  ]

  @impl Mix.Task
  def run(raw_args) do
    Mix.Task.run("app.start")

    {opts, args, _invalid} = OptionParser.parse(raw_args, switches: @switches)

    cond do
      opts[:list] ->
        list_sources()

      length(args) < 2 ->
        Mix.shell().error(
          "Usage: mix funsheep.ingest.run <source> <dataset> [--async] [--force] [--url URL]"
        )

        Mix.shell().info("Run `mix funsheep.ingest.run --list` to see available sources.")
        System.halt(1)

      true ->
        [source, dataset | _] = args
        dispatch(source, dataset, opts)
    end
  end

  defp list_sources do
    Mix.shell().info("Registered ingestion sources:\n")

    for {source, module} <- Ingest.sources() do
      Mix.shell().info("  #{String.pad_trailing(source, 16)} #{inspect(module)}")
      datasets = apply(module, :datasets, [])
      Mix.shell().info("    datasets: #{Enum.join(datasets, ", ")}")
    end
  end

  defp dispatch(source, dataset, opts) do
    run_opts = build_run_opts(opts)

    if opts[:async] do
      enqueue_async(source, dataset, opts)
    else
      run_sync(source, dataset, run_opts)
    end
  end

  defp run_sync(source, dataset, run_opts) do
    Mix.shell().info("Running #{source}/#{dataset} inline...")
    started = System.monotonic_time(:second)

    case Ingest.run(source, dataset, run_opts) do
      {:ok, stats} ->
        elapsed = System.monotonic_time(:second) - started

        Mix.shell().info("""

        Completed #{source}/#{dataset} in #{elapsed}s
          rows:     #{Map.get(stats, :rows, "-")}
          upserted: #{Map.get(stats, :inserted, "-")}
          errors:   #{Map.get(stats, :errors, 0)}
        """)

      {:error, reason} ->
        Mix.shell().error("FAILED #{source}/#{dataset}: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp enqueue_async(source, dataset, opts) do
    args =
      %{"source" => source, "dataset" => dataset}
      |> maybe_put("url", opts[:url])
      |> maybe_put("api_key", opts[:api_key])
      |> maybe_put("force", opts[:force])
      |> maybe_put("date", opts[:date])
      |> maybe_put("path", opts[:path])

    case args |> IngestWorker.new() |> Oban.insert() do
      {:ok, job} ->
        Mix.shell().info("Enqueued Oban job ##{job.id} for #{source}/#{dataset}")

      {:error, reason} ->
        Mix.shell().error("Failed to enqueue: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp build_run_opts(opts) do
    []
    |> maybe_kw(:url, opts[:url])
    |> maybe_kw(:api_key, opts[:api_key])
    |> maybe_kw(:force, opts[:force])
    |> maybe_kw(:path, opts[:path])
    |> maybe_kw(:date, parse_date(opts[:date]))
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  defp maybe_kw(kw, _k, nil), do: kw
  defp maybe_kw(kw, k, v), do: Keyword.put(kw, k, v)

  defp parse_date(nil), do: nil

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end
