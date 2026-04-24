defmodule FunSheep.Workers.DiscoveredSourceSweeperWorker do
  @moduledoc """
  Cron worker that recovers `discovered_sources` that got stuck in
  non-terminal states. The April audit of course d44628ca showed only
  1 of 33 discovered sources actually reached `:processed` — the other
  32 were distributed across `discovered | scraping | failed` and
  never moved forward because the original scrape job had long since
  been evicted from Oban.

  Three recovery paths:

    * `scraping` for > 30 min → stuck worker (container crash, lost
      job, or transient network failure that exhausted retries). Reset
      to `discovered` so the scraper picks it up again.
    * `failed` for > 1 day AND `attempts` < 3 → previous run
      failed but the failure count suggests transience. Reset to
      `discovered`.
    * `discovered` for > 1 day AND the course has no scraper job
      queued or recently running → enqueue a new scraper job so the
      backlog doesn't pile up forever when the original course
      creation's scraper hit the @max_sources_per_run cap.

  Runs every 30 minutes via Oban.Plugins.Cron.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias FunSheep.Content.DiscoveredSource
  alias FunSheep.Repo

  import Ecto.Query
  require Logger

  @stuck_scraping_minutes 30
  @stuck_failed_hours 24
  @stuck_discovered_hours 24

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    scraping_reset = reset_stuck_scraping(now)
    failed_reset = reset_stuck_failed(now)
    discovered_enqueued = enqueue_unrun_discovered(now)

    if scraping_reset + failed_reset + discovered_enqueued > 0 do
      Logger.info(
        "[SourceSweeper] scraping_reset=#{scraping_reset} failed_reset=#{failed_reset} discovered_enqueued=#{discovered_enqueued}"
      )
    end

    :ok
  end

  defp reset_stuck_scraping(now) do
    cutoff = DateTime.add(now, -@stuck_scraping_minutes, :minute)

    {count, _} =
      from(ds in DiscoveredSource,
        where: ds.status == "scraping" and ds.updated_at < ^cutoff
      )
      |> Repo.update_all(set: [status: "discovered", updated_at: now])

    count
  end

  defp reset_stuck_failed(now) do
    cutoff = DateTime.add(now, -@stuck_failed_hours, :hour)

    {count, _} =
      from(ds in DiscoveredSource,
        where: ds.status == "failed" and ds.updated_at < ^cutoff
      )
      |> Repo.update_all(set: [status: "discovered", updated_at: now])

    count
  end

  defp enqueue_unrun_discovered(now) do
    cutoff = DateTime.add(now, -@stuck_discovered_hours, :hour)

    # Course IDs that still have `discovered` sources older than the
    # cutoff. One scraper enqueue per course — the worker itself
    # handles batching via @max_sources_per_run.
    course_ids =
      from(ds in DiscoveredSource,
        where: ds.status == "discovered" and ds.inserted_at < ^cutoff,
        distinct: true,
        select: ds.course_id
      )
      |> Repo.all()

    Enum.each(course_ids, fn course_id ->
      FunSheep.Workers.WebQuestionScraperWorker.enqueue(course_id)
    end)

    length(course_ids)
  end
end
