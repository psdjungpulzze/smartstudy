defmodule FunSheep.Scraper.CrawlBatch do
  @moduledoc """
  Tracks one fan-out of WebSourceScraperWorker jobs for a course.

  Created by `WebQuestionScraperWorker` (the coordinator) each time it
  fans out per-source Oban jobs. Updated every 5 minutes by
  `CrawlBatchProgressWorker` from DB counts — no in-job writes needed.

  Status progression:
    running  → jobs are still being processed
    enqueued → coordinator finished enqueuing; jobs may still be running
    complete → processed_urls >= total_urls (progress worker sets this)
    failed   → abnormal termination
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "crawl_batches" do
    field :strategy, :string
    field :test_type, :string
    field :total_urls, :integer, default: 0
    field :processed_urls, :integer, default: 0
    field :questions_extracted, :integer, default: 0
    field :status, :string, default: "running"
    field :config, :map, default: %{}

    belongs_to :course, FunSheep.Courses.Course

    timestamps(type: :utc_datetime)
  end

  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [
      :course_id,
      :strategy,
      :test_type,
      :total_urls,
      :processed_urls,
      :questions_extracted,
      :status,
      :config
    ])
    |> validate_required([:course_id])
    |> validate_inclusion(:status, ~w(running enqueued complete failed))
    |> foreign_key_constraint(:course_id)
  end
end
