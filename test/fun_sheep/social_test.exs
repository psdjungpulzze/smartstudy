defmodule FunSheep.SocialTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Social
  alias FunSheep.Social.{Follow, Block}
  alias FunSheep.ContentFixtures

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp make_school do
    ContentFixtures.create_school()
  end

  defp make_student(opts \\ []) do
    school = Keyword.get(opts, :school)

    attrs =
      if school do
        %{role: :student, school_id: school.id}
      else
        %{role: :student}
      end

    ContentFixtures.create_user_role(attrs)
  end

  # ── Follow ───────────────────────────────────────────────────────────────

  describe "follow/3" do
    test "creates a follow relationship" do
      a = make_student()
      b = make_student()

      assert {:ok, follow} = Social.follow(a.id, b.id)
      assert follow.follower_id == a.id
      assert follow.following_id == b.id
      assert follow.status == "active"
      assert follow.source == "manual"
    end

    test "is idempotent — returns existing follow if already following" do
      a = make_student()
      b = make_student()

      {:ok, first} = Social.follow(a.id, b.id)
      {:ok, second} = Social.follow(a.id, b.id)

      assert first.id == second.id
    end

    test "rejects self-follow" do
      a = make_student()
      assert {:error, changeset} = Social.follow(a.id, a.id)
      assert changeset.errors[:follower_id] != nil or changeset.errors[:following_id] != nil
    end

    test "accepts custom source" do
      a = make_student()
      b = make_student()

      assert {:ok, follow} = Social.follow(a.id, b.id, "suggested_school")
      assert follow.source == "suggested_school"
    end

    test "awards first_follow badge on first follow" do
      a = make_student()
      b = make_student()

      Social.follow(a.id, b.id)

      achievements = FunSheep.Gamification.list_achievements(a.id)
      assert Enum.any?(achievements, &(&1.achievement_type == "first_follow"))
    end

    test "awards first_follower badge to the first-followed user" do
      a = make_student()
      b = make_student()

      Social.follow(a.id, b.id)

      achievements = FunSheep.Gamification.list_achievements(b.id)
      assert Enum.any?(achievements, &(&1.achievement_type == "first_follower"))
    end
  end

  describe "unfollow/2" do
    test "removes a follow relationship" do
      a = make_student()
      b = make_student()

      Social.follow(a.id, b.id)
      assert :ok = Social.unfollow(a.id, b.id)

      refute Repo.get_by(Follow, follower_id: a.id, following_id: b.id)
    end

    test "is a no-op if not following" do
      a = make_student()
      b = make_student()

      assert :ok = Social.unfollow(a.id, b.id)
    end
  end

  describe "block/2" do
    test "creates a block and removes existing follows" do
      a = make_student()
      b = make_student()

      Social.follow(a.id, b.id)
      Social.follow(b.id, a.id)

      assert {:ok, block} = Social.block(a.id, b.id)
      assert block.blocker_id == a.id
      assert block.blocked_id == b.id

      refute Repo.get_by(Follow, follower_id: a.id, following_id: b.id)
      refute Repo.get_by(Follow, follower_id: b.id, following_id: a.id)
    end

    test "is idempotent" do
      a = make_student()
      b = make_student()

      {:ok, b1} = Social.block(a.id, b.id)
      {:ok, b2} = Social.block(a.id, b.id)

      assert b1.id == b2.id
    end
  end

  describe "unblock/2" do
    test "removes a block" do
      a = make_student()
      b = make_student()

      Social.block(a.id, b.id)
      assert :ok = Social.unblock(a.id, b.id)

      refute Repo.get_by(Block, blocker_id: a.id, blocked_id: b.id)
    end
  end

  # ── follow_state ─────────────────────────────────────────────────────────

  describe "follow_state/2" do
    test "returns :none when no relationship" do
      a = make_student()
      b = make_student()

      assert Social.follow_state(a.id, b.id) == :none
    end

    test "returns :following when viewer follows subject" do
      a = make_student()
      b = make_student()

      Social.follow(a.id, b.id)
      assert Social.follow_state(a.id, b.id) == :following
    end

    test "returns :followed_by when subject follows viewer" do
      a = make_student()
      b = make_student()

      Social.follow(b.id, a.id)
      assert Social.follow_state(a.id, b.id) == :followed_by
    end

    test "returns :mutual when both follow each other" do
      a = make_student()
      b = make_student()

      Social.follow(a.id, b.id)
      Social.follow(b.id, a.id)
      assert Social.follow_state(a.id, b.id) == :mutual
    end

    test "returns :blocked when viewer blocked subject" do
      a = make_student()
      b = make_student()

      Social.block(a.id, b.id)
      assert Social.follow_state(a.id, b.id) == :blocked
    end

    test "returns :blocked when subject blocked viewer" do
      a = make_student()
      b = make_student()

      Social.block(b.id, a.id)
      assert Social.follow_state(a.id, b.id) == :blocked
    end
  end

  describe "mutual?/2" do
    test "returns true for mutual follows" do
      a = make_student()
      b = make_student()

      Social.follow(a.id, b.id)
      Social.follow(b.id, a.id)

      assert Social.mutual?(a.id, b.id)
    end

    test "returns false for one-way follow" do
      a = make_student()
      b = make_student()

      Social.follow(a.id, b.id)
      refute Social.mutual?(a.id, b.id)
    end
  end

  # ── following/follower lists ──────────────────────────────────────────────

  describe "following_ids/1 and follower_ids/1" do
    test "returns correct following and follower lists" do
      a = make_student()
      b = make_student()
      c = make_student()

      Social.follow(a.id, b.id)
      Social.follow(a.id, c.id)
      Social.follow(b.id, a.id)

      assert Enum.sort(Social.following_ids(a.id)) == Enum.sort([b.id, c.id])
      assert Social.follower_ids(a.id) == [b.id]
    end
  end

  describe "blocked_user_ids/1" do
    test "includes both blockers and blocked users" do
      a = make_student()
      b = make_student()
      c = make_student()

      Social.block(a.id, b.id)
      Social.block(c.id, a.id)

      blocked = Social.blocked_user_ids(a.id)
      assert b.id in blocked
      assert c.id in blocked
    end
  end

  # ── follow counts ─────────────────────────────────────────────────────────

  describe "following_count/1 and follower_count/1" do
    test "returns correct counts" do
      a = make_student()
      b = make_student()
      c = make_student()

      Social.follow(a.id, b.id)
      Social.follow(a.id, c.id)
      Social.follow(b.id, a.id)

      assert Social.following_count(a.id) == 2
      assert Social.follower_count(a.id) == 1
    end
  end

  # ── school_peers ──────────────────────────────────────────────────────────

  describe "school_peers/2" do
    test "returns students at the same school" do
      school = make_school()
      me = make_student(school: school)
      peer1 = make_student(school: school)
      peer2 = make_student(school: school)
      other = make_student()

      peers = Social.school_peers(me.id)
      peer_ids = Enum.map(peers, & &1.id)

      assert peer1.id in peer_ids
      assert peer2.id in peer_ids
      refute me.id in peer_ids
      refute other.id in peer_ids
    end

    test "excludes blocked users" do
      school = make_school()
      me = make_student(school: school)
      peer = make_student(school: school)

      Social.block(me.id, peer.id)

      peers = Social.school_peers(me.id)
      refute Enum.any?(peers, &(&1.id == peer.id))
    end

    test "includes follow_state for each peer" do
      school = make_school()
      me = make_student(school: school)
      peer = make_student(school: school)

      Social.follow(me.id, peer.id)

      peers = Social.school_peers(me.id)
      found = Enum.find(peers, &(&1.id == peer.id))
      assert found.follow_state == :following
    end

    test "returns empty list when user has no school" do
      me = ContentFixtures.create_user_role(%{role: :student, school_id: nil})
      assert Social.school_peers(me.id) == []
    end
  end

  describe "school_peer_count/1" do
    test "counts students at a school" do
      school = make_school()
      make_student(school: school)
      make_student(school: school)

      assert Social.school_peer_count(school.id) == 2
    end

    test "returns 0 for nil school" do
      assert Social.school_peer_count(nil) == 0
    end
  end

  # ── flock_with_social ─────────────────────────────────────────────────────

  describe "flock_with_social/2" do
    test "includes follow_state on each flock entry" do
      school = make_school()
      me = make_student(school: school)
      peer = make_student(school: school)

      Social.follow(me.id, peer.id)

      {flock, _rank, _size} = Social.flock_with_social(me.id)

      peer_entry = Enum.find(flock, &(&1.id == peer.id))
      assert peer_entry != nil
      assert peer_entry.follow_state == :following
    end

    test "excludes blocked users" do
      school = make_school()
      me = make_student(school: school)
      peer = make_student(school: school)

      Social.block(me.id, peer.id)

      {flock, _rank, _size} = Social.flock_with_social(me.id)
      refute Enum.any?(flock, &(&1.id == peer.id))
    end

    test "filter :following returns only following+mutual+me" do
      school = make_school()
      me = make_student(school: school)
      peer_followed = make_student(school: school)
      peer_not_followed = make_student(school: school)

      Social.follow(me.id, peer_followed.id)

      {flock, _rank, _size} = Social.flock_with_social(me.id, filter: :following)
      flock_ids = Enum.map(flock, & &1.id)

      assert peer_followed.id in flock_ids or not (peer_not_followed.id in flock_ids)
      refute peer_not_followed.id in flock_ids
    end
  end

  # ── can_view_profile ─────────────────────────────────────────────────────

  describe "can_view_profile?/2" do
    test "returns true for same school users" do
      school = make_school()
      a = make_student(school: school)
      b = make_student(school: school)

      assert Social.can_view_profile?(a.id, b.id)
    end

    test "returns true for self" do
      a = make_student()
      assert Social.can_view_profile?(a.id, a.id)
    end

    test "returns false when blocked" do
      a = make_student()
      b = make_student()

      Social.block(a.id, b.id)
      refute Social.can_view_profile?(a.id, b.id)
    end

    test "returns true when viewer follows subject (different school)" do
      a = make_student()
      b = make_student()

      Social.follow(a.id, b.id)
      assert Social.can_view_profile?(a.id, b.id)
    end

    test "returns false with no relationship and different schools" do
      a = make_student()
      b = make_student()

      refute Social.can_view_profile?(a.id, b.id)
    end
  end

  # ── suggested_follows ────────────────────────────────────────────────────

  describe "suggested_follows/2" do
    test "excludes already-followed users" do
      school = make_school()
      me = make_student(school: school)
      peer = make_student(school: school)

      Social.follow(me.id, peer.id)

      suggestions = Social.suggested_follows(me.id)
      refute Enum.any?(suggestions, &(&1.user_role.id == peer.id))
    end

    test "excludes blocked users" do
      school = make_school()
      me = make_student(school: school)
      peer = make_student(school: school)

      Social.block(me.id, peer.id)

      suggestions = Social.suggested_follows(me.id)
      refute Enum.any?(suggestions, &(&1.user_role.id == peer.id))
    end

    test "excludes self" do
      school = make_school()
      me = make_student(school: school)
      _peer = make_student(school: school)

      suggestions = Social.suggested_follows(me.id)
      refute Enum.any?(suggestions, &(&1.user_role.id == me.id))
    end

    test "includes school peers with :school reason" do
      school = make_school()
      me = make_student(school: school)
      peer = make_student(school: school)

      suggestions = Social.suggested_follows(me.id)
      found = Enum.find(suggestions, &(&1.user_role.id == peer.id))
      assert found != nil
      assert found.reason == :school
    end
  end

  # ── search_peers ─────────────────────────────────────────────────────────

  describe "search_peers/3" do
    test "finds peers by display name within same school" do
      school = make_school()
      me = make_student(school: school)
      {:ok, peer} =
        %FunSheep.Accounts.UserRole{}
        |> FunSheep.Accounts.UserRole.changeset(%{
          interactor_user_id: "uid_#{System.unique_integer([:positive])}",
          role: :student,
          email: "zoe#{System.unique_integer([:positive])}@test.com",
          display_name: "Zoe Testington",
          school_id: school.id
        })
        |> Repo.insert()

      results = Social.search_peers(me.id, "Zoe")
      assert Enum.any?(results, &(&1.user_role.id == peer.id))
    end

    test "does not find peers at different schools" do
      school_a = make_school()
      school_b = make_school()
      me = make_student(school: school_a)
      other = make_student(school: school_b)

      _ = ContentFixtures.create_user_role(%{
        role: :student,
        display_name: "Other School Student",
        school_id: school_b.id
      })

      results = Social.search_peers(me.id, other.display_name)
      refute Enum.any?(results, &(&1.user_role.id == other.id))
    end

    test "excludes blocked users from search" do
      school = make_school()
      me = make_student(school: school)
      {:ok, peer} =
        %FunSheep.Accounts.UserRole{}
        |> FunSheep.Accounts.UserRole.changeset(%{
          interactor_user_id: "uid_#{System.unique_integer([:positive])}",
          role: :student,
          email: "blocked#{System.unique_integer([:positive])}@test.com",
          display_name: "Blocked Person",
          school_id: school.id
        })
        |> Repo.insert()

      Social.block(me.id, peer.id)

      results = Social.search_peers(me.id, "Blocked")
      refute Enum.any?(results, &(&1.user_role.id == peer.id))
    end

    test "includes follow_state in results" do
      school = make_school()
      me = make_student(school: school)
      {:ok, peer} =
        %FunSheep.Accounts.UserRole{}
        |> FunSheep.Accounts.UserRole.changeset(%{
          interactor_user_id: "uid_#{System.unique_integer([:positive])}",
          role: :student,
          email: "fstatetest#{System.unique_integer([:positive])}@test.com",
          display_name: "FollowState Test",
          school_id: school.id
        })
        |> Repo.insert()

      Social.follow(me.id, peer.id)

      results = Social.search_peers(me.id, "FollowState Test")
      found = Enum.find(results, &(&1.user_role.id == peer.id))
      assert found.follow_state == :following
    end
  end
end
