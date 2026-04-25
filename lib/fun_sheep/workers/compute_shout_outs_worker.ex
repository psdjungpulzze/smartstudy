defmodule FunSheep.Workers.ComputeShoutOutsWorker do
  @moduledoc """
  Oban worker that computes weekly shout out winners and stores them.

  Runs Sunday at 23:55 UTC so the winners are ready for Monday morning.
  The week being summarised is the one that just ended (Mon–Sun UTC).
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias FunSheep.Gamification

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()

    # Most recent Monday (start of the week just ending)
    week_start =
      case Date.day_of_week(today, :monday) do
        1 -> today
        n -> Date.add(today, -(n - 1))
      end

    period_end = Date.add(week_start, 7)

    Gamification.compute_and_store_shout_outs(week_start, period_end)
  end
end
