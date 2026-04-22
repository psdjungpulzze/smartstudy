defmodule FunSheep.Workers.ParentDigestWorker do
  @moduledoc """
  Oban worker that produces a single guardian+student weekly digest and
  emails it via Swoosh (spec §8.1).

  Enqueued by `FunSheep.Workers.ParentDigestScheduler` — one job per
  {guardian_id, student_id} pair so failures isolate.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias FunSheep.{Mailer, Notifications}
  alias FunSheepWeb.ParentEmail

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"guardian_id" => gid, "student_id" => sid}}) do
    case Notifications.build(gid, sid) do
      {:ok, digest} ->
        digest
        |> ParentEmail.weekly_digest()
        |> Mailer.deliver()
        |> case do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning("[ParentDigest] delivery failed for #{gid}/#{sid}: #{inspect(reason)}")
            {:error, reason}
        end

      {:skip, reason} ->
        Logger.info("[ParentDigest] skipped #{gid}/#{sid}: #{inspect(reason)}")
        :ok
    end
  end
end
