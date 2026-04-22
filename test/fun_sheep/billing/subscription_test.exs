defmodule FunSheep.Billing.SubscriptionTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Accounts
  alias FunSheep.Billing.Subscription
  alias FunSheep.PracticeRequests.Request
  alias FunSheep.Repo

  defp create_user_role(attrs) do
    defaults = %{
      interactor_user_id: Ecto.UUID.generate(),
      role: :student,
      email: "user_#{System.unique_integer([:positive])}@test.com",
      display_name: "Test User"
    }

    {:ok, user_role} = Accounts.create_user_role(Map.merge(defaults, attrs))
    user_role
  end

  defp student, do: create_user_role(%{role: :student})
  defp parent, do: create_user_role(%{role: :parent})

  describe "changeset/2 — payer/beneficiary fields (§3.1, §7.2)" do
    test "accepts paid_by_user_role_id pointing at a different user_role" do
      kid = student()
      mom = parent()

      {:ok, sub} =
        Subscription.changeset(%Subscription{}, %{
          user_role_id: kid.id,
          paid_by_user_role_id: mom.id,
          plan: "annual",
          status: "active"
        })
        |> Repo.insert()

      assert sub.user_role_id == kid.id
      assert sub.paid_by_user_role_id == mom.id
      assert Subscription.paid?(sub)
    end

    test "accepts origin_practice_request_id linking back to the request" do
      kid = student()
      mom = parent()

      {:ok, req} =
        Request.create_changeset(%Request{}, %{
          student_id: kid.id,
          guardian_id: mom.id,
          reason_code: :upcoming_test,
          metadata: %{"streak_days" => 1}
        })
        |> Repo.insert()

      {:ok, sub} =
        Subscription.changeset(%Subscription{}, %{
          user_role_id: kid.id,
          paid_by_user_role_id: mom.id,
          origin_practice_request_id: req.id,
          plan: "monthly",
          status: "active"
        })
        |> Repo.insert()

      assert sub.origin_practice_request_id == req.id
    end

    test "self-purchase: paid_by_user_role_id may equal user_role_id" do
      adult_learner = create_user_role(%{role: :student, display_name: "Adult"})

      {:ok, sub} =
        Subscription.changeset(%Subscription{}, %{
          user_role_id: adult_learner.id,
          paid_by_user_role_id: adult_learner.id,
          plan: "annual",
          status: "active"
        })
        |> Repo.insert()

      assert sub.user_role_id == sub.paid_by_user_role_id
    end

    test "paid_by and origin_practice_request are both optional (free plan)" do
      kid = student()

      {:ok, sub} =
        Subscription.changeset(%Subscription{}, %{
          user_role_id: kid.id,
          plan: "free",
          status: "active"
        })
        |> Repo.insert()

      assert is_nil(sub.paid_by_user_role_id)
      assert is_nil(sub.origin_practice_request_id)
    end

    test "rejects non-existent paid_by_user_role_id via FK constraint" do
      kid = student()
      bogus = Ecto.UUID.generate()

      {:error, cs} =
        Subscription.changeset(%Subscription{}, %{
          user_role_id: kid.id,
          paid_by_user_role_id: bogus,
          plan: "monthly",
          status: "active"
        })
        |> Repo.insert()

      refute cs.valid?
      assert errors_on(cs)[:paid_by_user_role_id]
    end
  end

  describe "paid?/1 (regression)" do
    test "active monthly is paid" do
      assert Subscription.paid?(%Subscription{plan: "monthly", status: "active"})
    end

    test "active annual is paid" do
      assert Subscription.paid?(%Subscription{plan: "annual", status: "active"})
    end

    test "free or cancelled is not paid" do
      refute Subscription.paid?(%Subscription{plan: "free", status: "active"})
      refute Subscription.paid?(%Subscription{plan: "monthly", status: "cancelled"})
    end
  end
end
