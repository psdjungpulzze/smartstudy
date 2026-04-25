defmodule FunSheep.NotificationsTest do
  @moduledoc """
  Covers `FunSheep.Notifications` + the signed unsubscribe token
  (spec §8.1 / §8.4).
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.{Accounts, Notifications, Repo}
  alias FunSheep.ContentFixtures
  alias FunSheep.Engagement.StudySession
  alias FunSheep.Notifications.UnsubscribeToken

  setup do
    parent = ContentFixtures.create_user_role(%{role: :parent})
    student = ContentFixtures.create_user_role(%{role: :student, grade: "10"})
    {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
    {:ok, _} = Accounts.accept_guardian_invite(sg.id)
    %{parent: parent, student: student}
  end

  defp insert_session!(student, attrs) do
    defaults = %{
      session_type: "practice",
      time_window: "morning",
      questions_attempted: 5,
      questions_correct: 4,
      duration_seconds: 600,
      user_role_id: student.id,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    {:ok, _} =
      %StudySession{}
      |> StudySession.changeset(Map.merge(defaults, attrs))
      |> Repo.insert()
  end

  describe "active_digest_recipients/0" do
    test "lists active guardian+student pairs with digest_frequency=:weekly",
         %{parent: p, student: s} do
      pairs = Notifications.active_digest_recipients()
      assert Enum.any?(pairs, fn {g, st} -> g.id == p.id and st.id == s.id end)
    end

    test "excludes guardians with digest_frequency=:off", %{parent: p} do
      {:ok, _} = Accounts.update_user_role(p, %{digest_frequency: :off})
      pairs = Notifications.active_digest_recipients()
      refute Enum.any?(pairs, fn {g, _} -> g.id == p.id end)
    end
  end

  describe "build/2" do
    test "returns :no_activity for a fresh student", %{parent: p, student: s} do
      assert {:skip, :no_activity} = Notifications.build(p.id, s.id)
    end

    test "builds a digest once there's real activity", %{parent: p, student: s} do
      insert_session!(s, %{duration_seconds: 1200})

      assert {:ok, digest} = Notifications.build(p.id, s.id)
      assert digest.guardian.id == p.id
      assert digest.student.id == s.id
      assert digest.minutes_this_week == 20
      assert is_binary(digest.unsubscribe_token)
      assert is_list(digest.upcoming_tests)
    end

    test "refuses unauthorized guardian" do
      stranger = ContentFixtures.create_user_role(%{role: :parent})
      student = ContentFixtures.create_user_role(%{role: :student})

      assert {:skip, :unauthorized} = Notifications.build(stranger.id, student.id)
    end
  end

  describe "UnsubscribeToken" do
    test "round-trips a guardian id", %{parent: p} do
      token = UnsubscribeToken.mint(p.id)
      assert {:ok, verified} = UnsubscribeToken.verify(token)
      assert verified == p.id
    end

    test "rejects a tampered token" do
      assert {:error, _} = UnsubscribeToken.verify("not-a-valid-token")
    end
  end

  # ── Alert enqueue / read / count ─────────────────────────────────────────

  describe "enqueue/2" do
    test "inserts an in_app notification", %{student: s} do
      assert {:ok, [notif]} =
               Notifications.enqueue(s.id,
                 type: :streak_at_risk,
                 body: "Your streak is at risk!",
                 channels: [:in_app]
               )

      assert notif.channel == :in_app
      assert notif.type == :streak_at_risk
      assert notif.status == :pending
    end

    test "inserts both in_app and push when push_enabled", %{student: s} do
      {:ok, notifs} =
        Notifications.enqueue(s.id,
          type: :streak_at_risk,
          body: "body",
          channels: [:in_app, :push]
        )

      channels = Enum.map(notifs, & &1.channel)
      assert :in_app in channels
      assert :push in channels
    end

    test "skips push when push_enabled is false" do
      {:ok, student} =
        Accounts.create_user_role(%{
          interactor_user_id: "itr_#{System.unique_integer([:positive])}",
          role: :student,
          email: "nopush_#{System.unique_integer([:positive])}@test.com",
          push_enabled: false
        })

      {:ok, notifs} =
        Notifications.enqueue(student.id,
          type: :streak_at_risk,
          body: "body",
          channels: [:in_app, :push]
        )

      assert Enum.all?(notifs, &(&1.channel == :in_app))
    end

    test "returns error for unknown user" do
      assert {:error, :user_role_not_found} =
               Notifications.enqueue(Ecto.UUID.generate(),
                 type: :streak_at_risk,
                 body: "body"
               )
    end

    test "stores payload correctly", %{student: s} do
      {:ok, [notif | _]} =
        Notifications.enqueue(s.id,
          type: :streak_at_risk,
          body: "body",
          payload: %{"streak" => 7},
          channels: [:in_app]
        )

      assert notif.payload["streak"] == 7
    end
  end

  describe "list_in_app_unread/1" do
    test "returns unread in-app notifications", %{student: s} do
      Notifications.enqueue(s.id, type: :streak_at_risk, body: "unread", channels: [:in_app])
      notifs = Notifications.list_in_app_unread(s.id)
      assert length(notifs) >= 1
      assert Enum.all?(notifs, &is_nil(&1.read_at))
    end

    test "does not return read notifications", %{student: s} do
      {:ok, [notif]} =
        Notifications.enqueue(s.id,
          type: :streak_at_risk,
          body: "will be read",
          channels: [:in_app]
        )

      Notifications.mark_read(s.id, notif.id)
      assert [] == Notifications.list_in_app_unread(s.id)
    end

    test "does not return notifications for other users", %{student: s, parent: p} do
      Notifications.enqueue(s.id, type: :streak_at_risk, body: "s only", channels: [:in_app])
      assert [] == Notifications.list_in_app_unread(p.id)
    end
  end

  describe "unread_count/1" do
    test "returns 0 for a fresh user", %{student: s} do
      assert Notifications.unread_count(s.id) == 0
    end

    test "returns correct count after enqueue", %{student: s} do
      Notifications.enqueue(s.id, type: :streak_at_risk, body: "1", channels: [:in_app])
      assert Notifications.unread_count(s.id) == 1

      Notifications.enqueue(s.id, type: :test_upcoming_3d, body: "2", channels: [:in_app])
      assert Notifications.unread_count(s.id) == 2
    end
  end

  describe "mark_read/2" do
    test "marks a notification as read", %{student: s} do
      {:ok, [notif]} =
        Notifications.enqueue(s.id, type: :streak_at_risk, body: "b", channels: [:in_app])

      assert {:ok, updated} = Notifications.mark_read(s.id, notif.id)
      assert updated.status == :read
      assert not is_nil(updated.read_at)
    end

    test "returns error for wrong user", %{student: s, parent: p} do
      {:ok, [notif]} =
        Notifications.enqueue(s.id, type: :streak_at_risk, body: "b", channels: [:in_app])

      assert {:error, :not_found} = Notifications.mark_read(p.id, notif.id)
    end
  end

  describe "mark_all_read/1" do
    test "marks all unread in-app notifications as read", %{student: s} do
      Notifications.enqueue(s.id, type: :streak_at_risk, body: "1", channels: [:in_app])
      Notifications.enqueue(s.id, type: :test_upcoming_3d, body: "2", channels: [:in_app])

      assert Notifications.unread_count(s.id) == 2
      Notifications.mark_all_read(s.id)
      assert Notifications.unread_count(s.id) == 0
    end
  end

  # ── Push tokens ───────────────────────────────────────────────────────────

  describe "upsert_push_token/3" do
    test "creates a new token", %{student: s} do
      assert {:ok, %FunSheep.Notifications.PushToken{active: true}} =
               Notifications.upsert_push_token(s.id, "tok123", :ios)
    end

    test "reactivates an existing deactivated token", %{student: s} do
      {:ok, _} = Notifications.upsert_push_token(s.id, "tok123", :ios)
      Notifications.deactivate_push_token("tok123")

      assert {:ok, %FunSheep.Notifications.PushToken{active: true}} =
               Notifications.upsert_push_token(s.id, "tok123", :ios)
    end

    test "list_push_tokens/1 only returns active tokens", %{student: s} do
      {:ok, _} = Notifications.upsert_push_token(s.id, "tok1", :ios)
      {:ok, _} = Notifications.upsert_push_token(s.id, "tok2", :android)
      Notifications.deactivate_push_token("tok2")

      tokens = Notifications.list_push_tokens(s.id)
      assert length(tokens) == 1
      assert hd(tokens).token == "tok1"
    end
  end

  # ── Streak at-risk query ──────────────────────────────────────────────────

  describe "streak_at_risk_students/0" do
    test "returns students with streak > 0 and last_activity_date == yesterday", %{student: s} do
      yesterday = Date.add(Date.utc_today(), -1)
      {:ok, _} = FunSheep.Gamification.get_or_create_streak(s.id)

      import Ecto.Query

      Repo.update_all(
        from(str in FunSheep.Gamification.Streak, where: str.user_role_id == ^s.id),
        set: [current_streak: 5, last_activity_date: yesterday]
      )

      Repo.update_all(
        from(ur in FunSheep.Accounts.UserRole, where: ur.id == ^s.id),
        set: [alerts_streak: true, push_enabled: true]
      )

      at_risk = Notifications.streak_at_risk_students()
      ids = Enum.map(at_risk, & &1.user_role_id)
      assert s.id in ids
    end

    test "excludes students who already studied today", %{student: s} do
      today = Date.utc_today()
      {:ok, _} = FunSheep.Gamification.get_or_create_streak(s.id)

      import Ecto.Query

      Repo.update_all(
        from(str in FunSheep.Gamification.Streak, where: str.user_role_id == ^s.id),
        set: [current_streak: 3, last_activity_date: today]
      )

      at_risk = Notifications.streak_at_risk_students()
      ids = Enum.map(at_risk, & &1.user_role_id)
      refute s.id in ids
    end
  end
end
