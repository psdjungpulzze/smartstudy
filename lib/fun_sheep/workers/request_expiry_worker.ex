defmodule FunSheep.Workers.RequestExpiryWorker do
  @moduledoc """
  Expires `practice_requests` rows past their `expires_at` timestamp.

  Runs hourly via `Oban.Plugins.Cron` (see `config/config.exs`). Each
  run transitions every `:pending | :viewed` request whose `expires_at`
  is in the past to `:expired`, emitting `request.expired` telemetry
  per-request. Per spec §4.5, §11.2.

  Idempotent: running multiple times in the same hour is safe.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias FunSheep.PracticeRequests

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    expired_count =
      PracticeRequests.list_expired_pending()
      |> Enum.reduce(0, fn request, acc ->
        case PracticeRequests.expire(request.id) do
          {:ok, _} -> acc + 1
          _ -> acc
        end
      end)

    if expired_count > 0 do
      Logger.info("[RequestExpiry] expired #{expired_count} practice_requests")
    end

    :ok
  end
end
