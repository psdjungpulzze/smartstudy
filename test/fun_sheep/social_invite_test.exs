defmodule FunSheep.SocialInviteTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Social
  alias FunSheep.Social.{Follow, Invite}
  alias FunSheep.ContentFixtures

  defp make_student do
    ContentFixtures.create_user_role(%{role: :student})
  end

  # ── create_invite ─────────────────────────────────────────────────────────

  describe "create_invite/2 for existing user" do
    test "creates a pending invite to an existing user role" do
      inviter = make_student()
      invitee = make_student()

      assert {:ok, invite} = Social.create_invite(inviter.id, invitee_user_role_id: invitee.id)
      assert invite.inviter_id == inviter.id
      assert invite.invitee_user_role_id == invitee.id
      assert invite.status == "pending"
    end

    test "does not generate a token when inviting existing user" do
      inviter = make_student()
      invitee = make_student()

      {:ok, invite} = Social.create_invite(inviter.id, invitee_user_role_id: invitee.id)
      assert is_nil(invite.invite_token)
      assert is_nil(invite.invite_token_expires_at)
    end

    test "accepts optional message" do
      inviter = make_student()
      invitee = make_student()

      {:ok, invite} =
        Social.create_invite(inviter.id,
          invitee_user_role_id: invitee.id,
          message: "Join me!"
        )

      assert invite.message == "Join me!"
    end

    test "truncates message to 200 chars" do
      inviter = make_student()
      invitee = make_student()

      long_msg = String.duplicate("x", 250)

      {:ok, invite} =
        Social.create_invite(inviter.id,
          invitee_user_role_id: invitee.id,
          message: long_msg
        )

      assert String.length(invite.message) == 200
    end

    test "accepts context and context_id" do
      inviter = make_student()
      invitee = make_student()
      ctx_id = Ecto.UUID.generate()

      {:ok, invite} =
        Social.create_invite(inviter.id,
          invitee_user_role_id: invitee.id,
          context: "course",
          context_id: ctx_id
        )

      assert invite.context == "course"
      assert invite.context_id == ctx_id
    end

    test "fails without invitee info" do
      inviter = make_student()
      assert {:error, changeset} = Social.create_invite(inviter.id)
      assert changeset.errors[:invitee_email] != nil
    end
  end

  describe "create_invite/2 for non-user (email)" do
    test "creates a pending invite with token and expiry" do
      inviter = make_student()

      assert {:ok, invite} = Social.create_invite(inviter.id, invitee_email: "new@test.com")
      assert invite.inviter_id == inviter.id
      assert invite.invitee_email == "new@test.com"
      assert invite.status == "pending"
      assert is_binary(invite.invite_token)
      assert String.length(invite.invite_token) == 14
      assert invite.invite_token_expires_at != nil
    end

    test "token expires ~14 days in the future" do
      inviter = make_student()
      {:ok, invite} = Social.create_invite(inviter.id, invitee_email: "future@test.com")

      days_until_expiry =
        DateTime.diff(invite.invite_token_expires_at, DateTime.utc_now(), :second) / 86_400

      assert days_until_expiry > 13.9
      assert days_until_expiry < 14.1
    end

    test "generates unique tokens" do
      inviter = make_student()
      {:ok, i1} = Social.create_invite(inviter.id, invitee_email: "a@test.com")
      {:ok, i2} = Social.create_invite(inviter.id, invitee_email: "b@test.com")
      assert i1.invite_token != i2.invite_token
    end
  end

  # ── accept_invite ─────────────────────────────────────────────────────────

  describe "accept_invite/1" do
    test "accepts a valid pending invite and creates a follow" do
      inviter = make_student()
      invitee = make_student()

      {:ok, invite} = Social.create_invite(inviter.id, invitee_email: "x@test.com")

      invite_with_invitee =
        Repo.update!(Ecto.Changeset.change(invite, invitee_user_role_id: invitee.id))

      assert {:ok, accepted} = Social.accept_invite(invite_with_invitee.invite_token)
      assert accepted.status == "accepted"
      assert accepted.accepted_at != nil

      assert Repo.get_by(Follow, follower_id: invitee.id, following_id: inviter.id)
    end

    test "returns :not_found for unknown token" do
      assert {:error, :not_found} = Social.accept_invite("unknowntoken12")
    end

    test "returns :expired for expired invite" do
      inviter = make_student()
      {:ok, invite} = Social.create_invite(inviter.id, invitee_email: "exp@test.com")

      past = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
      Repo.update!(Ecto.Changeset.change(invite, invite_token_expires_at: past))

      assert {:error, :expired} = Social.accept_invite(invite.invite_token)

      reloaded = Repo.get!(Invite, invite.id)
      assert reloaded.status == "expired"
    end

    test "returns :invalid_token for non-binary input" do
      assert {:error, :invalid_token} = Social.accept_invite(nil)
    end

    test "returns :not_found for already-accepted invite" do
      inviter = make_student()
      invitee = make_student()

      {:ok, invite} = Social.create_invite(inviter.id, invitee_email: "once@test.com")

      invite_with_invitee =
        Repo.update!(Ecto.Changeset.change(invite, invitee_user_role_id: invitee.id))

      Social.accept_invite(invite_with_invitee.invite_token)
      assert {:error, :not_found} = Social.accept_invite(invite_with_invitee.invite_token)
    end
  end

  # ── decline_invite ────────────────────────────────────────────────────────

  describe "decline_invite/1" do
    test "marks invite as declined" do
      inviter = make_student()
      {:ok, invite} = Social.create_invite(inviter.id, invitee_email: "dec@test.com")

      assert {:ok, declined} = Social.decline_invite(invite.invite_token)
      assert declined.status == "declined"
    end

    test "returns :not_found for unknown token" do
      assert {:error, :not_found} = Social.decline_invite("notavalidtoken1")
    end
  end

  # ── list_sent_invites / list_received_invites ─────────────────────────────

  describe "list_sent_invites/1" do
    test "returns invites sent by the user" do
      inviter = make_student()
      invitee = make_student()

      Social.create_invite(inviter.id, invitee_email: "a@test.com")
      Social.create_invite(inviter.id, invitee_user_role_id: invitee.id)

      sent = Social.list_sent_invites(inviter.id)
      assert length(sent) == 2
      assert Enum.all?(sent, &(&1.inviter_id == inviter.id))
    end

    test "returns empty list when none sent" do
      student = make_student()
      assert Social.list_sent_invites(student.id) == []
    end
  end

  describe "list_received_invites/1" do
    test "returns pending invites received by the user" do
      inviter = make_student()
      invitee = make_student()

      {:ok, _} = Social.create_invite(inviter.id, invitee_user_role_id: invitee.id)

      received = Social.list_received_invites(invitee.id)
      assert length(received) == 1
      assert hd(received).invitee_user_role_id == invitee.id
    end

    test "excludes non-pending invites" do
      inviter = make_student()
      invitee = make_student()

      {:ok, invite} = Social.create_invite(inviter.id, invitee_user_role_id: invitee.id)
      Repo.update!(Invite.status_changeset(invite, "declined"))

      assert Social.list_received_invites(invitee.id) == []
    end
  end

  # ── invite_count_by_status ────────────────────────────────────────────────

  describe "invite_count_by_status/1" do
    test "returns counts grouped by status" do
      inviter = make_student()

      Social.create_invite(inviter.id, invitee_email: "p1@test.com")
      {:ok, invite2} = Social.create_invite(inviter.id, invitee_email: "p2@test.com")
      Repo.update!(Invite.status_changeset(invite2, "declined"))

      counts = Social.invite_count_by_status(inviter.id)
      assert counts["pending"] == 1
      assert counts["declined"] == 1
    end

    test "returns empty map when no invites sent" do
      student = make_student()
      assert Social.invite_count_by_status(student.id) == %{}
    end
  end
end
