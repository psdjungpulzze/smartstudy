defmodule FunSheep.Workers.WebQuestionScraperWorker do
  @moduledoc """
  Coordinator Oban worker for the web-scraping pipeline.

  For each discovered source in "discovered" status, enqueues one
  `WebSourceScraperWorker` job (the per-source worker) and creates a
  `CrawlBatch` record so progress can be tracked.

  This worker does NOT do any scraping itself — it is a pure fan-out
  coordinator. All heavy lifting (HTTP fetch, AI extraction, dedup,
  validation) happens inside `WebSourceScraperWorker`.
  """

  use Oban.Worker,
    queue: :ai,
    max_attempts: 2,
    unique: [
      period: 300,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias FunSheep.{Content, Courses, Repo}
  alias FunSheep.Scraper.CrawlBatch
  alias FunSheep.Workers.WebSourceScraperWorker

  require Logger

  @max_sources_per_run 500

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"course_id" => course_id}}) do
    # Raises Ecto.NoResultsError for unknown courses (propagates as job failure)
    _course = Courses.get_course_with_chapters!(course_id)

    sources =
      Content.list_scrapable_sources(course_id) |> Enum.take(@max_sources_per_run)

    if sources == [] do
      Logger.info("[Coordinator] No scrapable sources for course #{course_id}")
      :ok
    else
      total = length(sources)

      %CrawlBatch{}
      |> CrawlBatch.changeset(%{
        course_id: course_id,
        strategy: "web_scrape",
        total_urls: total,
        status: "enqueued"
      })
      |> Repo.insert!()

      Enum.each(sources, fn source ->
        %{"source_id" => source.id}
        |> WebSourceScraperWorker.new(queue: :web_scrape)
        |> Oban.insert!()
      end)

      Logger.info(
        "[Coordinator] Enqueued #{total} WebSourceScraperWorker jobs for course #{course_id}"
      )

      :ok
    end
  end

  @doc """
  Enqueues a coordinator job for a course.

  Oban uniqueness prevents duplicate jobs from stacking up for the same course —
  if one is already queued/running/retryable, this returns the existing job.
  """
  def enqueue(course_id) do
    %{course_id: course_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
