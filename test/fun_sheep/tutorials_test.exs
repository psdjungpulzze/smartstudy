defmodule FunSheep.TutorialsTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.ContentFixtures
  alias FunSheep.Tutorials

  describe "seen?/2" do
    test "returns false for an unseen tutorial" do
      user_role = ContentFixtures.create_user_role()
      refute Tutorials.seen?(user_role.id, "quick_practice")
    end

    test "returns true after mark_seen" do
      user_role = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user_role.id, "quick_practice")
      assert Tutorials.seen?(user_role.id, "quick_practice")
    end

    test "is scoped per user_role_id" do
      user_a = ContentFixtures.create_user_role()
      user_b = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user_a.id, "quick_practice")

      assert Tutorials.seen?(user_a.id, "quick_practice")
      refute Tutorials.seen?(user_b.id, "quick_practice")
    end

    test "is scoped per tutorial_key" do
      user_role = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user_role.id, "quick_practice")

      assert Tutorials.seen?(user_role.id, "quick_practice")
      refute Tutorials.seen?(user_role.id, "other_feature")
    end

    test "nil user_role_id returns false" do
      refute Tutorials.seen?(nil, "quick_practice")
    end

    test "non-uuid user_role_id returns false safely" do
      refute Tutorials.seen?("not-a-uuid", "quick_practice")
    end
  end

  describe "mark_seen/2" do
    test "is idempotent" do
      user_role = ContentFixtures.create_user_role()
      assert {:ok, _} = Tutorials.mark_seen(user_role.id, "quick_practice")
      # Second call on conflict must not error
      assert {:ok, _} = Tutorials.mark_seen(user_role.id, "quick_practice")
    end

    test "nil user_role_id returns {:error, :no_user}" do
      assert {:error, :no_user} = Tutorials.mark_seen(nil, "quick_practice")
    end
  end

  describe "reset/2" do
    test "clears seen state so tutorial auto-shows again" do
      user_role = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user_role.id, "quick_practice")
      assert Tutorials.seen?(user_role.id, "quick_practice")

      {_count, _} = Tutorials.reset(user_role.id, "quick_practice")
      refute Tutorials.seen?(user_role.id, "quick_practice")
    end
  end
end
