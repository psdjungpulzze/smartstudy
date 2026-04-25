defmodule FunSheep.Workers.NotificationDeliveryWorkerTest do
  @moduledoc """
  Tests for `FunSheep.Workers.NotificationDeliveryWorker`.

  Verifies that the worker correctly marks in-app notifications as sent,
  handles missing notifications gracefully, skips already-delivered
  notifications, and respects quiet hours for email/push channels.
  """

  use FunSheep.DataCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  import Ecto.Query

  alias FunSheep.{Notifications, Repo}
  alias FunSheep.ContentFixtures
  alias FunSheep.Notifications.Notification
  alias FunSheep.Workers.NotificationDeliveryWorker

  defp enqueue_notification!(student, channel, opts \\ []) do
    type = Keyword.get(opts, :type, :streak_at_risk)
    body = Keyword.get(opts, :body, "Test notification body")

    {:ok, notifs} =
      Notifications.enqueue(student.id,
        type: type,
        body: body,
        channels: [channel]
      )

    notif = Enum.find(notifs, &(&1.channel == channel))
    notif || hd(notifs)
  end

  defp create_student(attrs \\ %{}) do
    ContentFixtures.create_user_role(Map.merge(%{role: :student}, attrs))
  end

  describe "perform/1 — in_app channel" do
    test "marks an in_app notification as :sent" do
      student = create_student()
      notif = enqueue_notification!(student, :in_app)

      assert :ok = perform_job(NotificationDeliveryWorker, %{"notification_id" => notif.id})

      updated = Repo.get!(Notification, notif.id)
      assert updated.status == :sent
      assert not is_nil(updated.sent_at)
    end
  end

  describe "perform/1 — missing / already delivered" do
    test "returns :ok and does not raise for a missing notification_id" do
      missing_id = Ecto.UUID.generate()
      assert :ok = perform_job(NotificationDeliveryWorker, %{"notification_id" => missing_id})
    end

    test "skips a notification that is already :sent" do
      student = create_student()
      notif = enqueue_notification!(student, :in_app)

      # First delivery
      :ok = perform_job(NotificationDeliveryWorker, %{"notification_id" => notif.id})
      first_sent_at = Repo.get!(Notification, notif.id).sent_at

      # Second delivery — should no-op
      :ok = perform_job(NotificationDeliveryWorker, %{"notification_id" => notif.id})
      second_sent_at = Repo.get!(Notification, notif.id).sent_at

      assert first_sent_at == second_sent_at
    end

    test "skips a notification that is already :read" do
      student = create_student()
      notif = enqueue_notification!(student, :in_app)

      # Mark as read directly
      Repo.update_all(
        from(n in Notification, where: n.id == ^notif.id),
        set: [status: :read, read_at: DateTime.utc_now() |> DateTime.truncate(:second)]
      )

      # Delivery should no-op
      assert :ok = perform_job(NotificationDeliveryWorker, %{"notification_id" => notif.id})
    end
  end

  describe "perform/1 — push channel" do
    test "marks push as :sent when active tokens exist" do
      student =
        create_student(%{
          push_enabled: true,
          notification_quiet_start: 0,
          notification_quiet_end: 0
        })

      {:ok, _} = Notifications.upsert_push_token(student.id, "dev_token_123", :ios)

      notif = enqueue_notification!(student, :push)

      assert :ok = perform_job(NotificationDeliveryWorker, %{"notification_id" => notif.id})

      updated = Repo.get!(Notification, notif.id)
      assert updated.status == :sent
    end

    test "marks push as :failed when no active tokens exist" do
      student =
        create_student(%{
          push_enabled: true,
          notification_quiet_start: 0,
          notification_quiet_end: 0
        })

      # No tokens registered
      notif = enqueue_notification!(student, :push)

      assert :ok = perform_job(NotificationDeliveryWorker, %{"notification_id" => notif.id})

      updated = Repo.get!(Notification, notif.id)
      assert updated.status == :failed
    end
  end

  describe "perform/1 — email channel (stub)" do
    test "marks email as :sent (stub path)" do
      student =
        create_student(%{notification_quiet_start: 0, notification_quiet_end: 0})

      notif = enqueue_notification!(student, :email)

      assert :ok = perform_job(NotificationDeliveryWorker, %{"notification_id" => notif.id})

      updated = Repo.get!(Notification, notif.id)
      assert updated.status == :sent
    end
  end

  describe "perform/1 — SMS channel" do
    test "marks sms notifications as :failed immediately" do
      student = create_student()
      notif = enqueue_notification!(student, :sms)

      assert :ok = perform_job(NotificationDeliveryWorker, %{"notification_id" => notif.id})

      updated = Repo.get!(Notification, notif.id)
      assert updated.status == :failed
    end
  end


  describe "perform/1 — quiet hours" do
    defp quiet_student_with_token do
      h = DateTime.utc_now().hour
      # Build a quiet window that is guaranteed to cover the current UTC hour:
      # same-day window [0, 23) covers hours 0-22; if h == 23, use overnight window [23, 0).
      {qs, qe} = if h < 23, do: {0, 23}, else: {23, 0}

      student =
        create_student(%{
          push_enabled: true,
          notification_frequency: :standard,
          notification_quiet_start: qs,
          notification_quiet_end: qe
        })

      # Register a push token so the non-quiet path would send
      {:ok, _} = Notifications.upsert_push_token(student.id, "quiet_token_#{student.id}", :ios)
      student
    end

    test "skips push delivery during quiet hours (status stays :pending)" do
      student = quiet_student_with_token()
      notif = enqueue_notification!(student, :push)

      assert :ok = perform_job(NotificationDeliveryWorker, %{"notification_id" => notif.id})

      updated = Repo.get!(Notification, notif.id)
      assert updated.status == :pending
    end

    test "skips email delivery during quiet hours (status stays :pending)" do
      h = DateTime.utc_now().hour
      {qs, qe} = if h < 23, do: {0, 23}, else: {23, 0}

      student = create_student(%{notification_quiet_start: qs, notification_quiet_end: qe})
      notif = enqueue_notification!(student, :email)

      assert :ok = perform_job(NotificationDeliveryWorker, %{"notification_id" => notif.id})

      updated = Repo.get!(Notification, notif.id)
      assert updated.status == :pending
    end
  end
end
