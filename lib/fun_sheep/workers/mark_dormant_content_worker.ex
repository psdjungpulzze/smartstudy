defmodule FunSheep.Workers.MarkDormantContentWorker do
  @moduledoc """
  Oban worker that marks courses with no activity in 90 days as dormant.

  Sets `visibility_state` to `"reduced"` and records `dormant_at` for any
  course that:
  - is older than 90 days
  - has had no quality score update in the last 90 days
  - has `attempt_count == 0`
  - is not already delisted

  Runs nightly at 03:00 UTC (configured in config.exs crontab alongside
  the CoverageAuditWorker).
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    FunSheep.Community.mark_dormant_courses()
    :ok
  end
end
