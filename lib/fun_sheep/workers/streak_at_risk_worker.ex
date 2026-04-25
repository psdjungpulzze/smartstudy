defmodule FunSheep.Workers.StreakAtRiskWorker do
  @moduledoc """
  Cron worker that runs every 2 hours and nudges students whose streak
  will reset at midnight if they don't study today.

  "At risk" = streak > 0 and last_activity_date == yesterday (not today).
  The worker skips users in their quiet hours and respects their per-type
  `alerts_streak` preference.

  Telemetry: emits `[:fun_sheep, :notifications, :streak_alert_sent]`.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias FunSheep.Notifications

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    students = Notifications.streak_at_risk_students()

    Logger.info("[StreakAtRisk] found #{length(students)} at-risk streak(s)")

    Enum.each(students, &maybe_enqueue/1)

    :ok
  end

  defp maybe_enqueue(%{user_role_id: user_role_id, streak: streak}) do
    user_role = FunSheep.Accounts.get_user_role(user_role_id)

    if is_nil(user_role) or Notifications.in_quiet_hours?(user_role) do
      Logger.debug("[StreakAtRisk] skipping #{user_role_id}: nil or quiet hours")
    else
      days = if streak == 1, do: "day", else: "days"

      {:ok, _} =
        Notifications.enqueue(user_role_id,
          type: :streak_at_risk,
          priority: 1,
          title: "Your streak is at risk! 🔥",
          body: "Your #{streak}-#{days} streak ends tonight. Answer 1 question to keep it alive.",
          payload: %{"streak" => streak},
          channels: [:in_app, :push]
        )

      :telemetry.execute(
        [:fun_sheep, :notifications, :streak_alert_sent],
        %{count: 1},
        %{user_role_id: user_role_id, streak: streak}
      )

      Logger.info("[StreakAtRisk] enqueued alert for #{user_role_id} (streak=#{streak})")
    end
  end
end
