defmodule FunSheep.SocialPhase4Test do
  use FunSheep.DataCase, async: true

  alias FunSheep.{Social, Gamification, Repo}
  alias FunSheep.ContentFixtures

  defp make_student do
    ContentFixtures.create_user_role(%{role: :student})
  end

  # Creates an accepted invite by: creating the invite, linking the invitee's
  # user_role_id (simulating registration), then accepting via token — which
  # triggers check_flock_milestones.
  defp accepted_invite(inviter, invitee) do
    email = "invite_#{System.unique_integer([:positive])}@test.example"
    {:ok, invite} = Social.create_invite(inviter.id, invitee_email: email)

    Repo.update!(Ecto.Changeset.change(invite, invitee_user_role_id: invitee.id))

    {:ok, accepted} = Social.accept_invite(invite.invite_token)
    accepted
  end

  # ── Flock Tree ────────────────────────────────────────────────────────────

  describe "flock_tree/1" do
    test "returns empty tree for a user with no invites" do
      user = make_student()
      tree = Social.flock_tree(user.id)
      assert tree.invited_by == nil
      assert tree.invited_users == []
      assert tree.total_invited == 0
    end

    test "shows who invited this user" do
      inviter = make_student()
      invitee = make_student()
      accepted_invite(inviter, invitee)

      tree = Social.flock_tree(invitee.id)
      assert tree.invited_by != nil
      assert tree.invited_by.id == inviter.id
    end

    test "shows who this user has invited" do
      inviter = make_student()
      i1 = make_student()
      i2 = make_student()
      accepted_invite(inviter, i1)
      accepted_invite(inviter, i2)

      tree = Social.flock_tree(inviter.id)
      assert length(tree.invited_users) == 2
      ids = Enum.map(tree.invited_users, & &1.id)
      assert i1.id in ids
      assert i2.id in ids
    end

    test "total_invited counts the entire subtree recursively" do
      root = make_student()
      child1 = make_student()
      child2 = make_student()
      grandchild = make_student()

      accepted_invite(root, child1)
      accepted_invite(root, child2)
      accepted_invite(child1, grandchild)

      tree = Social.flock_tree(root.id)
      # 2 direct + 1 grandchild
      assert tree.total_invited == 3
    end

    test "only counts accepted invites in subtree" do
      inviter = make_student()
      i1 = make_student()

      accepted_invite(inviter, i1)

      # Create a pending invite — should NOT count
      email = "pending_#{System.unique_integer([:positive])}@test.example"
      {:ok, _} = Social.create_invite(inviter.id, invitee_email: email)

      tree = Social.flock_tree(inviter.id)
      assert tree.total_invited == 1
    end
  end

  # ── Flock Milestone Achievements ─────────────────────────────────────────

  describe "flock milestone badges via accept_invite" do
    test "awards shepherd at 5 accepted invites" do
      inviter = make_student()

      for _ <- 1..5 do
        accepted_invite(inviter, make_student())
      end

      types = inviter.id |> Gamification.list_achievements() |> Enum.map(& &1.achievement_type)
      assert "shepherd" in types
    end

    test "awards lead_shepherd at 10 accepted invites" do
      inviter = make_student()

      for _ <- 1..10 do
        accepted_invite(inviter, make_student())
      end

      types = inviter.id |> Gamification.list_achievements() |> Enum.map(& &1.achievement_type)
      assert "lead_shepherd" in types
    end

    test "awards flock_builder at 20 accepted invites" do
      inviter = make_student()

      for _ <- 1..20 do
        accepted_invite(inviter, make_student())
      end

      types = inviter.id |> Gamification.list_achievements() |> Enum.map(& &1.achievement_type)
      assert "flock_builder" in types
    end

    test "does not award shepherd below 5 invites" do
      inviter = make_student()

      for _ <- 1..4 do
        accepted_invite(inviter, make_student())
      end

      types = inviter.id |> Gamification.list_achievements() |> Enum.map(& &1.achievement_type)
      refute "shepherd" in types
    end

    test "is idempotent — does not duplicate shepherd badge" do
      inviter = make_student()

      for _ <- 1..6 do
        accepted_invite(inviter, make_student())
      end

      achievements = Gamification.list_achievements(inviter.id)
      count = Enum.count(achievements, &(&1.achievement_type == "shepherd"))
      assert count == 1
    end
  end

  # ── Achievement Broadcast Fan-Out ─────────────────────────────────────────

  describe "achievement broadcast to followers" do
    test "follower receives :friend_achievement when followed user earns an achievement" do
      follower = make_student()
      earner = make_student()

      Social.follow(follower.id, earner.id)
      Phoenix.PubSub.subscribe(FunSheep.PubSub, "social:feed:#{follower.id}")

      Gamification.award_achievement(earner.id, "first_practice", %{})

      assert_receive {:friend_achievement, friend_id, achievement_type}, 1000
      assert friend_id == earner.id
      assert achievement_type == "first_practice"
    end

    test "non-follower does NOT receive the broadcast" do
      non_follower = make_student()
      earner = make_student()

      Phoenix.PubSub.subscribe(FunSheep.PubSub, "social:feed:#{non_follower.id}")

      Gamification.award_achievement(earner.id, "first_practice", %{})

      refute_receive {:friend_achievement, _, _}, 200
    end

    test "already_earned does not re-broadcast" do
      follower = make_student()
      earner = make_student()

      Social.follow(follower.id, earner.id)
      Gamification.award_achievement(earner.id, "first_practice", %{})

      # Subscribe AFTER the first award so its message is not in the mailbox
      Phoenix.PubSub.subscribe(FunSheep.PubSub, "social:feed:#{follower.id}")

      {:already_earned, _} = Gamification.award_achievement(earner.id, "first_practice", %{})

      refute_receive {:friend_achievement, _, _}, 200
    end

    test "multiple followers all receive the broadcast" do
      f1 = make_student()
      f2 = make_student()
      earner = make_student()

      Social.follow(f1.id, earner.id)
      Social.follow(f2.id, earner.id)

      Phoenix.PubSub.subscribe(FunSheep.PubSub, "social:feed:#{f1.id}")
      Phoenix.PubSub.subscribe(FunSheep.PubSub, "social:feed:#{f2.id}")

      earner_id = earner.id
      Gamification.award_achievement(earner.id, "golden_fleece", %{})

      assert_receive {:friend_achievement, ^earner_id, "golden_fleece"}, 1000
      assert_receive {:friend_achievement, ^earner_id, "golden_fleece"}, 1000
    end
  end
end
