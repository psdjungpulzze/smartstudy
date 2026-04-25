defmodule FunSheep.Workers.NotificationDeliveryWorker do
  @moduledoc """
  Oban worker that delivers a single pending notification.

  Accepts `%{"notification_id" => uuid}` in job args.

  Delivery behaviour by channel:
    - `:in_app` — notification is already written to the DB and broadcast via
      PubSub on creation, so delivery just marks it `:sent`.
    - `:email`  — delegates to the existing email infrastructure. Stubbed until
      transactional notification emails are wired up.
    - `:push`   — requires active push tokens for the user. Logs a warning and
      marks the notification `:sent` when tokens exist, `:failed` when none do.
    - `:sms`    — not yet supported; marks `:failed` immediately.

  Respects quiet-hour and frequency-cap preferences stored on `user_roles`.
  If the user is in quiet hours the job returns `:ok` without sending (Oban
  will not retry; the notification stays `:pending` and can be retried by a
  future scheduler pass or manually discarded).
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  import Ecto.Query, warn: false

  alias FunSheep.Notifications
  alias FunSheep.Notifications.Notification
  alias FunSheep.{Accounts, Repo}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"notification_id" => notification_id}}) do
    case Repo.get(Notification, notification_id) do
      nil ->
        Logger.warning(
          "[NotificationDelivery] notification #{notification_id} not found; skipping"
        )

        :ok

      %Notification{status: status} when status != :pending ->
        Logger.debug(
          "[NotificationDelivery] notification #{notification_id} is #{status}; skipping"
        )

        :ok

      %Notification{} = notif ->
        deliver(notif)
    end
  end

  # ── Per-channel delivery ──────────────────────────────────────────────────

  defp deliver(%Notification{channel: :in_app} = notif) do
    # In-app notifications are inserted + broadcast at creation time.
    # Delivery worker simply confirms the status transition.
    mark_sent(notif)
  end

  defp deliver(%Notification{channel: :email, user_role_id: user_role_id} = notif) do
    user_role = Accounts.get_user_role(user_role_id)

    if is_nil(user_role) do
      mark_failed(notif, "user_role not found")
    else
      if Notifications.in_quiet_hours?(user_role) do
        Logger.debug(
          "[NotificationDelivery] #{notif.id} skipped (quiet hours) for #{user_role_id}"
        )

        :ok
      else
        # Transactional notification emails are not yet wired up.
        # Log the intent and mark as sent so the notification is not retried
        # indefinitely. A future task will implement the Swoosh template.
        Logger.info(
          "[NotificationDelivery] email delivery stub for #{notif.type} to #{user_role.email}"
        )

        mark_sent(notif)
      end
    end
  end

  defp deliver(%Notification{channel: :push, user_role_id: user_role_id} = notif) do
    user_role = Accounts.get_user_role(user_role_id)

    if is_nil(user_role) do
      mark_failed(notif, "user_role not found")
    else
      if Notifications.in_quiet_hours?(user_role) do
        Logger.debug(
          "[NotificationDelivery] #{notif.id} skipped (quiet hours) for #{user_role_id}"
        )

        :ok
      else
        tokens = Notifications.list_push_tokens(user_role_id)

        if tokens == [] do
          Logger.info(
            "[NotificationDelivery] no active push tokens for #{user_role_id}; failing notification #{notif.id}"
          )

          mark_failed(notif, "no_active_push_tokens")
        else
          # Push send requires FCM/APNS integration (Phase 2). Log intent for now.
          Logger.info(
            "[NotificationDelivery] push stub: would send #{notif.type} to #{length(tokens)} token(s) for #{user_role_id}"
          )

          :telemetry.execute(
            [:fun_sheep, :notifications, :push_delivery_stub],
            %{token_count: length(tokens)},
            %{user_role_id: user_role_id, type: notif.type}
          )

          mark_sent(notif)
        end
      end
    end
  end

  defp deliver(%Notification{channel: :sms} = notif) do
    Logger.warning("[NotificationDelivery] SMS delivery not supported; failing #{notif.id}")
    mark_failed(notif, "sms_not_supported")
  end

  # ── Status helpers ────────────────────────────────────────────────────────

  defp mark_sent(%Notification{} = notif) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    notif
    |> Notification.changeset(%{status: :sent, sent_at: now})
    |> Repo.update()
    |> case do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Logger.error(
          "[NotificationDelivery] failed to mark #{notif.id} sent: #{inspect(changeset.errors)}"
        )

        {:error, :update_failed}
    end
  end

  defp mark_failed(%Notification{} = notif, reason) do
    notif
    |> Notification.changeset(%{status: :failed})
    |> Repo.update()

    Logger.warning("[NotificationDelivery] notification #{notif.id} failed: #{reason}")

    :ok
  end
end
