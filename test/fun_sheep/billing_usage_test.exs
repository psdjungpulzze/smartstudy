defmodule FunSheep.BillingUsageTest do
  @moduledoc """
  Covers the Flow A usage helpers added in `FunSheep.Billing` (§7.3):
  `weekly_usage/1`, `lifetime_usage/1`, `usage_state/1`, `can_start_test?/1`.
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.Accounts
  alias FunSheep.Billing
  alias FunSheep.Billing.{Subscription, TestUsage}
  alias FunSheep.Repo

  defp create_student(attrs \\ %{}) do
    defaults = %{
      interactor_user_id: Ecto.UUID.generate(),
      role: :student,
      email: "s_#{System.unique_integer([:positive])}@test.com",
      display_name: "Kid"
    }

    {:ok, role} = Accounts.create_user_role(Map.merge(defaults, attrs))
    role
  end

  defp create_parent do
    {:ok, role} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: :parent,
        email: "p_#{System.unique_integer([:positive])}@test.com",
        display_name: "Parent"
      })

    role
  end

  defp record_tests(user_role_id, count) do
    for _ <- 1..count do
      {:ok, _} = Billing.record_test_usage(user_role_id, "quick_test")
    end
  end

  describe "lifetime_usage/1" do
    test "returns zeros for a fresh student" do
      s = create_student()
      assert %{used: 0, limit: 50, remaining: 50} = Billing.lifetime_usage(s.id)
    end

    test "counts all test_usages regardless of age" do
      s = create_student()
      record_tests(s.id, 3)
      assert %{used: 3, remaining: 47} = Billing.lifetime_usage(s.id)
    end

    test "adds bonus_free_tests on top of the base limit" do
      s = create_student()
      {:ok, sub} = Billing.get_or_create_subscription(s.id)
      {:ok, _} = Billing.update_subscription(sub, %{bonus_free_tests: 25})

      record_tests(s.id, 10)
      assert %{used: 10, limit: 75, remaining: 65} = Billing.lifetime_usage(s.id)
    end
  end

  describe "weekly_usage/1" do
    test "returns zeros with current time for a fresh student" do
      s = create_student()
      %{used: 0, limit: 20, remaining: 20, resets_at: resets_at} = Billing.weekly_usage(s.id)
      assert %DateTime{} = resets_at
    end

    test "counts only tests from the last 7 days" do
      s = create_student()

      # Record 3 recent, then 2 old (backdated via direct insert)
      record_tests(s.id, 3)

      # Backdate 2 tests to 10 days ago
      ten_days_ago = DateTime.add(DateTime.utc_now(), -10, :day) |> DateTime.truncate(:second)

      for _ <- 1..2 do
        {:ok, t} = Billing.record_test_usage(s.id, "quick_test")

        Ecto.Changeset.change(t, inserted_at: ten_days_ago, updated_at: ten_days_ago)
        |> Repo.update!()
      end

      assert %{used: 3, remaining: 17} = Billing.weekly_usage(s.id)
    end

    test "resets_at reflects when the oldest weekly test ages out, when at/over limit" do
      s = create_student()
      # Record 20 tests
      record_tests(s.id, 20)

      %{resets_at: resets_at} = Billing.weekly_usage(s.id)
      # Oldest test was just inserted, so resets_at ~= now + 7d
      assert DateTime.compare(resets_at, DateTime.utc_now()) == :gt
    end
  end

  describe "usage_state/1 (§4.1 thresholds)" do
    test ":fresh at 0% and up to but not including 50%" do
      s = create_student()
      assert Billing.usage_state(s.id) == :fresh

      record_tests(s.id, 9)
      # 9/20 = 45%
      assert Billing.usage_state(s.id) == :fresh
    end

    test ":warming at 50% up to but not including 70%" do
      s = create_student()
      record_tests(s.id, 10)
      # 10/20 = 50%
      assert Billing.usage_state(s.id) == :warming

      record_tests(s.id, 3)
      # 13/20 = 65%
      assert Billing.usage_state(s.id) == :warming
    end

    test ":nudge at 70% up to but not including 85%" do
      s = create_student()
      record_tests(s.id, 14)
      # 14/20 = 70%
      assert Billing.usage_state(s.id) == :nudge

      record_tests(s.id, 2)
      # 16/20 = 80%
      assert Billing.usage_state(s.id) == :nudge
    end

    test ":ask at 85% up to but not including 100%" do
      s = create_student()
      record_tests(s.id, 17)
      # 17/20 = 85% — the Ask-card trigger per §4.3
      assert Billing.usage_state(s.id) == :ask

      record_tests(s.id, 2)
      # 19/20 = 95%
      assert Billing.usage_state(s.id) == :ask
    end

    test ":hardwall at 100%" do
      s = create_student()
      record_tests(s.id, 20)
      assert Billing.usage_state(s.id) == :hardwall
    end

    test "returns :paid for a student with an active monthly sub" do
      s = create_student()

      {:ok, _} =
        %Subscription{}
        |> Subscription.changeset(%{user_role_id: s.id, plan: "monthly", status: "active"})
        |> Repo.insert()

      # Even at hardwall count, paid takes precedence.
      record_tests(s.id, 20)
      assert Billing.usage_state(s.id) == :paid
    end

    test "returns :not_applicable for a parent role" do
      p = create_parent()
      assert Billing.usage_state(p.id) == :not_applicable
    end
  end

  describe "can_start_test?/1" do
    test "true when fresh" do
      s = create_student()
      assert Billing.can_start_test?(s.id)
    end

    test "true when at 19/20 (ask) — still allowed the last slot" do
      s = create_student()
      record_tests(s.id, 19)
      assert Billing.can_start_test?(s.id)
    end

    test "false at hardwall" do
      s = create_student()
      record_tests(s.id, 20)
      refute Billing.can_start_test?(s.id)
    end

    test "true for paid student at hardwall count" do
      s = create_student()

      {:ok, _} =
        %Subscription{}
        |> Subscription.changeset(%{user_role_id: s.id, plan: "annual", status: "active"})
        |> Repo.insert()

      record_tests(s.id, 25)
      assert Billing.can_start_test?(s.id)
    end

    test "true for parent (non-student role)" do
      p = create_parent()
      assert Billing.can_start_test?(p.id)
    end

    test "false once the lifetime cap of 50 is hit" do
      s = create_student()

      # Backdate 51 tests to skirt the weekly counter but hit the lifetime cap.
      long_ago = DateTime.add(DateTime.utc_now(), -30, :day) |> DateTime.truncate(:second)

      for _ <- 1..51 do
        {:ok, t} = Billing.record_test_usage(s.id, "quick_test")
        Ecto.Changeset.change(t, inserted_at: long_ago) |> Repo.update!()
      end

      # Weekly is 0, so state is :fresh, but lifetime is 51 > 50 — blocked.
      refute Billing.can_start_test?(s.id)
    end

    test "true again once a bonus is granted that lifts the cap above usage" do
      s = create_student()
      long_ago = DateTime.add(DateTime.utc_now(), -30, :day) |> DateTime.truncate(:second)

      for _ <- 1..51 do
        {:ok, t} = Billing.record_test_usage(s.id, "quick_test")
        Ecto.Changeset.change(t, inserted_at: long_ago) |> Repo.update!()
      end

      refute Billing.can_start_test?(s.id)

      {:ok, sub} = Billing.get_or_create_subscription(s.id)
      {:ok, _} = Billing.update_subscription(sub, %{bonus_free_tests: 5})

      assert Billing.can_start_test?(s.id)
    end
  end
end
