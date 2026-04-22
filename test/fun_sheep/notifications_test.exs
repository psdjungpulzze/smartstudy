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
end
