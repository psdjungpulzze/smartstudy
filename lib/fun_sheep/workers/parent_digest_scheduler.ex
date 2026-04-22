defmodule FunSheep.Workers.ParentDigestScheduler do
  @moduledoc """
  Fans out one `FunSheep.Workers.ParentDigestWorker` job per active
  guardian+student pair whose parent opted into the weekly digest.

  Intended to be triggered by `Oban.Plugins.Cron` at Sunday 6pm in the
  student's local timezone. Because Cron fires in UTC we enqueue-by-UTC
  and each inner worker computes the local send-time context itself.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias FunSheep.Notifications
  alias FunSheep.Workers.ParentDigestWorker

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    for {guardian, student} <- Notifications.active_digest_recipients() do
      %{"guardian_id" => guardian.id, "student_id" => student.id}
      |> ParentDigestWorker.new()
      |> Oban.insert()
    end

    :ok
  end
end
