defmodule FunSheep.SocialTest do
  use FunSheep.DataCase, async: true

  import FunSheep.ContentFixtures

  alias FunSheep.Social

  setup do
    school = create_school()

    alice =
      create_user_role(%{email: "alice@test.com", display_name: "Alice", school_id: school.id})

    bob = create_user_role(%{email: "bob@test.com", display_name: "Bob", school_id: school.id})

    carol =
      create_user_role(%{email: "carol@test.com", display_name: "Carol", school_id: school.id})

    %{alice: alice, bob: bob, carol: carol}
  end

  describe "follow/2" do
    test "follows another user", %{alice: alice, bob: bob} do
      assert {:ok, _follow} = Social.follow(alice.id, bob.id)
      assert Social.following?(alice.id, bob.id)
    end

    test "is idempotent — does not error on duplicate follow", %{alice: alice, bob: bob} do
      assert {:ok, _} = Social.follow(alice.id, bob.id)
      assert {:ok, _} = Social.follow(alice.id, bob.id)
      assert Social.following?(alice.id, bob.id)
    end

    test "cannot follow yourself", %{alice: alice} do
      assert {:error, changeset} = Social.follow(alice.id, alice.id)
      errors = errors_on(changeset)
      # Self-follow is rejected either via the check constraint (follower_id)
      # or an Elixir-level validation (following_id / followee_id).
      assert Map.has_key?(errors, :follower_id) or Map.has_key?(errors, :following_id),
             "Expected a self-follow error on follower_id or following_id, got: #{inspect(errors)}"
    end

    test "cannot follow a blocked user", %{alice: alice, bob: bob} do
      {:ok, _} = Social.block(bob.id, alice.id)
      assert {:error, :blocked} = Social.follow(alice.id, bob.id)
    end
  end

  describe "unfollow/2" do
    test "removes an existing follow", %{alice: alice, bob: bob} do
      {:ok, _} = Social.follow(alice.id, bob.id)
      assert :ok = Social.unfollow(alice.id, bob.id)
      refute Social.following?(alice.id, bob.id)
    end

    test "is a no-op when not following", %{alice: alice, bob: bob} do
      assert :ok = Social.unfollow(alice.id, bob.id)
    end
  end

  describe "block/2 and unblock/2" do
    test "blocks a user and removes existing follows", %{alice: alice, bob: bob} do
      {:ok, _} = Social.follow(alice.id, bob.id)
      {:ok, _} = Social.follow(bob.id, alice.id)

      {:ok, _block} = Social.block(alice.id, bob.id)

      assert Social.blocked?(alice.id, bob.id)
      refute Social.following?(alice.id, bob.id)
      refute Social.following?(bob.id, alice.id)
    end

    test "unblocks a user", %{alice: alice, bob: bob} do
      {:ok, _} = Social.block(alice.id, bob.id)
      :ok = Social.unblock(alice.id, bob.id)
      refute Social.blocked?(alice.id, bob.id)
    end
  end

  describe "follow_state/2" do
    test "returns :self when viewer and subject are the same", %{alice: alice} do
      assert Social.follow_state(alice.id, alice.id) == :self
    end

    test "returns :not_following when no relationship exists", %{alice: alice, bob: bob} do
      assert Social.follow_state(alice.id, bob.id) == :not_following
    end

    test "returns :following when viewer follows subject", %{alice: alice, bob: bob} do
      {:ok, _} = Social.follow(alice.id, bob.id)
      assert Social.follow_state(alice.id, bob.id) == :following
    end

    test "returns :mutual when both follow each other", %{alice: alice, bob: bob} do
      {:ok, _} = Social.follow(alice.id, bob.id)
      {:ok, _} = Social.follow(bob.id, alice.id)
      assert Social.follow_state(alice.id, bob.id) == :mutual
    end

    test "returns :blocked when viewer has blocked subject", %{alice: alice, bob: bob} do
      {:ok, _} = Social.block(alice.id, bob.id)
      assert Social.follow_state(alice.id, bob.id) == :blocked
    end

    test "returns :blocked when subject has blocked viewer", %{alice: alice, bob: bob} do
      {:ok, _} = Social.block(bob.id, alice.id)
      assert Social.follow_state(alice.id, bob.id) == :blocked
    end
  end

  describe "following_ids/1 and follower_ids/1" do
    test "returns IDs of users the given user follows", %{alice: alice, bob: bob, carol: carol} do
      {:ok, _} = Social.follow(alice.id, bob.id)
      {:ok, _} = Social.follow(alice.id, carol.id)

      ids = Social.following_ids(alice.id)
      assert bob.id in ids
      assert carol.id in ids
      refute alice.id in ids
    end

    test "returns IDs of users following the given user", %{alice: alice, bob: bob, carol: carol} do
      {:ok, _} = Social.follow(bob.id, alice.id)
      {:ok, _} = Social.follow(carol.id, alice.id)

      ids = Social.follower_ids(alice.id)
      assert bob.id in ids
      assert carol.id in ids
    end

    test "returns empty lists when no follows exist", %{alice: alice} do
      assert Social.following_ids(alice.id) == []
      assert Social.follower_ids(alice.id) == []
    end
  end

  describe "follower_count/1 and following_count/1" do
    test "counts followers and following correctly", %{alice: alice, bob: bob, carol: carol} do
      {:ok, _} = Social.follow(bob.id, alice.id)
      {:ok, _} = Social.follow(carol.id, alice.id)
      {:ok, _} = Social.follow(alice.id, bob.id)

      assert Social.follower_count(alice.id) == 2
      assert Social.following_count(alice.id) == 1
    end
  end

  describe "school_peers/2" do
    test "returns peers at the same school", %{alice: alice, bob: bob} do
      peers = Social.school_peers(alice.id)
      peer_ids = Enum.map(peers, & &1.id)
      assert bob.id in peer_ids
      refute alice.id in peer_ids
    end

    test "excludes blocked users from peers", %{alice: alice, bob: bob} do
      {:ok, _} = Social.block(alice.id, bob.id)
      peers = Social.school_peers(alice.id)
      peer_ids = Enum.map(peers, & &1.id)
      refute bob.id in peer_ids
    end

    test "returns empty list for user with no school" do
      no_school = create_user_role(%{school_id: nil, email: "noschool@test.com"})
      assert Social.school_peers(no_school.id) == []
    end
  end

  describe "school_peer_count/1" do
    test "counts school peers", %{alice: alice} do
      count = Social.school_peer_count(alice.id)
      assert count >= 2
    end

    test "returns 0 for user with no school" do
      no_school = create_user_role(%{school_id: nil, email: "noschool2@test.com"})
      assert Social.school_peer_count(no_school.id) == 0
    end
  end
end
