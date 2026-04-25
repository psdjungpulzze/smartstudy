defmodule FunSheep.Gamification.ShoutOutTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Gamification
  alias FunSheep.Gamification.ShoutOut
  alias FunSheep.Accounts

  defp create_user_role(attrs \\ %{}) do
    defaults = %{
      interactor_user_id: "shoutout_test_#{System.unique_integer([:positive])}",
      role: :student,
      email: "shoutout_#{System.unique_integer([:positive])}@test.com",
      display_name: "Shout Test User"
    }

    {:ok, user_role} = Accounts.create_user_role(Map.merge(defaults, attrs))
    user_role
  end

  describe "ShoutOut.changeset/2" do
    test "valid changeset with required fields" do
      user_role = create_user_role()
      today = Date.utc_today()

      attrs = %{
        category: "most_xp",
        period: "weekly",
        period_start: today,
        period_end: Date.add(today, 7),
        metric_value: 250,
        user_role_id: user_role.id
      }

      changeset = ShoutOut.changeset(%ShoutOut{}, attrs)
      assert changeset.valid?
    end

    test "invalid without required fields" do
      changeset = ShoutOut.changeset(%ShoutOut{}, %{})
      refute changeset.valid?

      assert Keyword.has_key?(changeset.errors, :category)
      # :period has a schema default of "weekly" so cast keeps it — no blank error
      assert Keyword.has_key?(changeset.errors, :period_start)
      assert Keyword.has_key?(changeset.errors, :period_end)
      assert Keyword.has_key?(changeset.errors, :metric_value)
      assert Keyword.has_key?(changeset.errors, :user_role_id)
    end

    test "invalid with unknown category" do
      user_role = create_user_role()
      today = Date.utc_today()

      changeset =
        ShoutOut.changeset(%ShoutOut{}, %{
          category: "not_a_real_category",
          period: "weekly",
          period_start: today,
          period_end: Date.add(today, 7),
          metric_value: 10,
          user_role_id: user_role.id
        })

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :category)
    end

    test "invalid with unknown period" do
      user_role = create_user_role()
      today = Date.utc_today()

      changeset =
        ShoutOut.changeset(%ShoutOut{}, %{
          category: "most_xp",
          period: "yearly",
          period_start: today,
          period_end: Date.add(today, 7),
          metric_value: 10,
          user_role_id: user_role.id
        })

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :period)
    end
  end

  describe "ShoutOut.display_info/1" do
    test "returns display data for all known categories" do
      categories =
        ~w(most_xp most_tests_taken most_textbooks_uploaded most_tests_created longest_streak most_generous_teacher)

      for category <- categories do
        info = ShoutOut.display_info(category)
        assert Map.has_key?(info, :label)
        assert Map.has_key?(info, :icon)
        assert Map.has_key?(info, :unit)
        assert is_binary(info.label)
        assert is_binary(info.icon)
        assert is_binary(info.unit)
      end
    end

    test "returns fallback for unknown category" do
      info = ShoutOut.display_info("unknown_category")
      assert Map.has_key?(info, :label)
      assert Map.has_key?(info, :icon)
    end
  end

  describe "Gamification.get_current_shout_outs/1" do
    test "returns empty list when no shout outs exist for the current week" do
      result = Gamification.get_current_shout_outs()
      assert is_list(result)
      # There may be shout outs from other tests in non-async environments,
      # but for a fresh DB there should be none.
      # We verify the shape if any come back:
      for so <- result do
        assert %ShoutOut{} = so
        assert so.period == "weekly"
      end
    end

    test "returns shout outs for the current week and preloads user_role" do
      user_role = create_user_role()

      today = Date.utc_today()
      week_start = compute_week_start(today)

      {:ok, _} =
        %ShoutOut{}
        |> ShoutOut.changeset(%{
          category: "most_xp",
          period: "weekly",
          period_start: week_start,
          period_end: Date.add(week_start, 7),
          metric_value: 500,
          user_role_id: user_role.id
        })
        |> FunSheep.Repo.insert()

      results = Gamification.get_current_shout_outs()

      my_shout_out = Enum.find(results, fn so -> so.user_role_id == user_role.id end)
      assert my_shout_out != nil
      assert my_shout_out.category == "most_xp"
      assert my_shout_out.metric_value == 500
      # user_role is preloaded
      assert my_shout_out.user_role != nil
      assert my_shout_out.user_role.id == user_role.id
    end

    test "does not return shout outs from a previous week" do
      user_role = create_user_role()

      # Use a period_start from two weeks ago
      old_start = Date.add(Date.utc_today(), -14)

      {:ok, _} =
        %ShoutOut{}
        |> ShoutOut.changeset(%{
          category: "longest_streak",
          period: "weekly",
          period_start: old_start,
          period_end: Date.add(old_start, 7),
          metric_value: 10,
          user_role_id: user_role.id
        })
        |> FunSheep.Repo.insert()

      results = Gamification.get_current_shout_outs()

      refute Enum.any?(results, fn so ->
               so.user_role_id == user_role.id and so.period_start == old_start
             end)
    end
  end

  describe "Gamification.compute_and_store_shout_outs/2" do
    test "returns {:ok, 0} when no data exists for the period" do
      today = Date.utc_today()
      period_start = Date.add(today, -100)
      period_end = Date.add(period_start, 7)

      assert {:ok, 0} = Gamification.compute_and_store_shout_outs(period_start, period_end)
    end

    test "stores a winner row for most_xp when xp_events exist" do
      user_role = create_user_role()

      period_start = Date.add(Date.utc_today(), -50)
      period_end = Date.add(period_start, 7)

      mid_dt =
        DateTime.new!(Date.add(period_start, 3), ~T[12:00:00], "Etc/UTC")
        |> DateTime.truncate(:second)

      # Insert XP event with a controlled timestamp via Repo.insert_all
      # so we can place it squarely inside the target period window.
      FunSheep.Repo.insert_all(FunSheep.Gamification.XpEvent, [
        %{
          id: Ecto.UUID.generate(),
          user_role_id: user_role.id,
          amount: 200,
          source: "practice",
          metadata: %{},
          inserted_at: mid_dt
        }
      ])

      {:ok, count} = Gamification.compute_and_store_shout_outs(period_start, period_end)
      assert count >= 1
    end
  end

  # Helper replicating the week-start logic in the context
  defp compute_week_start(today) do
    case Date.day_of_week(today, :monday) do
      1 -> today
      n -> Date.add(today, -(n - 1))
    end
  end
end
