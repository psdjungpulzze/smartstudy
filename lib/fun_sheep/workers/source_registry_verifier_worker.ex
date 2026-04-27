defmodule FunSheep.Workers.SourceRegistryVerifierWorker do
  @moduledoc """
  Nightly health check for `source_registry_entries`.

  For each entry not verified in the last 7 days:
    - HEAD-probes the URL.
    - On success: resets `consecutive_failures` to 0, updates `last_verified_at`.
    - On failure: increments `consecutive_failures`.
    - After 3 consecutive failures: sets `is_enabled: false` and logs an alert
      (Swoosh email delivery is deferred to a future iteration — log is enough for v1).

  Runs nightly at 02:00 UTC per cron config.
  """

  use Oban.Worker, queue: :default, max_attempts: 2

  import Ecto.Query

  alias FunSheep.{Repo}
  alias FunSheep.Discovery.SourceRegistryEntry
  alias FunSheep.Questions.Question

  require Logger

  @stale_days 7
  @disable_after_failures 3
  @extraction_drop_threshold 0.5

  @impl Oban.Worker
  def perform(_job) do
    run(probe_fn: &probe_url/1)
  end

  @doc false
  def run(opts \\ []) do
    probe_fn = Keyword.get(opts, :probe_fn, &probe_url/1)
    cutoff = DateTime.add(DateTime.utc_now(), -@stale_days * 86_400, :second)

    stale =
      from(e in SourceRegistryEntry,
        where: e.is_enabled == true and (is_nil(e.last_verified_at) or e.last_verified_at < ^cutoff)
      )
      |> Repo.all()

    Logger.info("[RegistryVerifier] Checking #{length(stale)} stale entries")

    Enum.each(stale, &verify_entry(&1, probe_fn))

    check_extraction_rate_drop()

    :ok
  end

  @doc false
  def probe_url(url) do
    case Req.head(url, receive_timeout: 8_000, max_redirects: 3, retry: false) do
      {:ok, %{status: status}} when status in 200..399 ->
        :ok

      {:ok, %{status: status}} when status in [405, 501] ->
        case Req.get(url,
               receive_timeout: 8_000,
               max_redirects: 3,
               retry: false,
               headers: [{"range", "bytes=0-0"}]
             ) do
          {:ok, %{status: s}} when s in 200..399 -> :ok
          {:ok, %{status: s}} -> {:error, {:http_status, s}}
          {:error, reason} -> {:error, reason}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Private ---

  defp verify_entry(%SourceRegistryEntry{} = entry, probe_fn) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case probe_fn.(entry.url_or_pattern) do
      :ok ->
        entry
        |> SourceRegistryEntry.changeset(%{
          consecutive_failures: 0,
          last_verified_at: now
        })
        |> Repo.update()

        Logger.debug("[RegistryVerifier] OK: #{entry.url_or_pattern}")

      {:error, reason} ->
        new_failures = entry.consecutive_failures + 1
        should_disable = new_failures >= @disable_after_failures

        attrs =
          %{consecutive_failures: new_failures, last_verified_at: now}
          |> then(fn a -> if should_disable, do: Map.put(a, :is_enabled, false), else: a end)

        entry
        |> SourceRegistryEntry.changeset(attrs)
        |> Repo.update()

        if should_disable do
          Logger.error(
            "[RegistryVerifier] DISABLED #{entry.url_or_pattern} after #{new_failures} failures " <>
              "(last: #{inspect(reason)}). test_type=#{entry.test_type}"
          )
        else
          Logger.warning(
            "[RegistryVerifier] FAIL #{entry.url_or_pattern}: #{inspect(reason)} " <>
              "(#{new_failures}/#{@disable_after_failures})"
          )
        end
    end
  end

  defp check_extraction_rate_drop do
    now = DateTime.utc_now()
    today_start = %{now | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    yesterday_start = DateTime.add(today_start, -86_400, :second)

    today_count =
      from(q in Question,
        where:
          q.source_type == :web_scraped and
            q.inserted_at >= ^today_start and
            q.inserted_at < ^now
      )
      |> Repo.aggregate(:count)

    yesterday_count =
      from(q in Question,
        where:
          q.source_type == :web_scraped and
            q.inserted_at >= ^yesterday_start and
            q.inserted_at < ^today_start
      )
      |> Repo.aggregate(:count)

    if yesterday_count > 0 and today_count < yesterday_count * @extraction_drop_threshold do
      Logger.error(
        "[RegistryVerifier] EXTRACTION RATE DROP: today=#{today_count} yesterday=#{yesterday_count} " <>
          "(#{Float.round(today_count / yesterday_count * 100, 1)}% of yesterday). " <>
          "Check Playwright renderer, Anthropic API, and blocked domains."
      )
    else
      Logger.debug(
        "[RegistryVerifier] Extraction rate OK: today=#{today_count} yesterday=#{yesterday_count}"
      )
    end
  end
end
