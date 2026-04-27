defmodule FunSheep.Workers.CrawlBatchProgressWorker do
  @moduledoc """
  Oban cron worker that refreshes progress stats on all running CrawlBatches.

  Runs every 5 minutes. For each batch in "running" or "enqueued" status:
    - Counts `discovered_sources` with terminal status (processed/failed/skipped)
    - Sums `questions` of source_type :web_scraped for the course
    - Marks the batch "complete" when processed_urls >= total_urls

  This approach keeps `WebSourceScraperWorker` free of progress-accounting
  writes and avoids contention on the batch row.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query
  alias FunSheep.{Repo}
  alias FunSheep.Content.DiscoveredSource
  alias FunSheep.Questions.Question
  alias FunSheep.Scraper.CrawlBatch

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    active_batches =
      from(b in CrawlBatch, where: b.status in ["running", "enqueued"])
      |> Repo.all()

    Enum.each(active_batches, &update_batch/1)

    :ok
  end

  defp update_batch(%CrawlBatch{course_id: course_id} = batch) do
    total =
      from(ds in DiscoveredSource, where: ds.course_id == ^course_id)
      |> Repo.aggregate(:count)

    processed =
      from(ds in DiscoveredSource,
        where:
          ds.course_id == ^course_id and
            ds.status in ["processed", "failed", "skipped"]
      )
      |> Repo.aggregate(:count)

    questions =
      from(q in Question,
        where: q.course_id == ^course_id and q.source_type == :web_scraped
      )
      |> Repo.aggregate(:count)

    status =
      cond do
        total > 0 and processed >= total -> "complete"
        batch.status == "enqueued" -> "enqueued"
        true -> "running"
      end

    case batch
         |> CrawlBatch.changeset(%{
           total_urls: total,
           processed_urls: processed,
           questions_extracted: questions,
           status: status
         })
         |> Repo.update() do
      {:ok, updated} ->
        Logger.debug(
          "[CrawlBatch] #{updated.id}: #{updated.processed_urls}/#{updated.total_urls} sources, #{updated.questions_extracted} questions, status=#{updated.status}"
        )

      {:error, changeset} ->
        Logger.warning("[CrawlBatch] Failed to update #{batch.id}: #{inspect(changeset.errors)}")
    end
  end
end
