defmodule FunSheep.Billing do
  @moduledoc """
  The Billing context.

  Manages subscriptions, test usage tracking, limit enforcement,
  payment methods, and invoices via the Interactor Billing Server.

  ## Free Tier Limits
    - 5 initial free tests (lifetime)
    - 3 free tests per week (rolling 7-day window)

  ## Paid Plans
    - Monthly ($30/month) - unlimited tests
    - Annual ($90/year) - unlimited tests

  ## Role-Based Access
    - Students: subject to billing limits
    - Parents/Teachers: free (admin roles, don't take tests)
  """

  import Ecto.Query

  alias FunSheep.Repo
  alias FunSheep.Billing.{Subscription, TestUsage}
  alias FunSheep.Interactor.Billing, as: BillingClient

  @initial_free_tests 5
  @weekly_free_tests 3

  ## Subscription Management

  def get_or_create_subscription(user_role_id) do
    case Repo.get_by(Subscription, user_role_id: user_role_id) do
      %Subscription{} = sub -> {:ok, sub}
      nil -> create_subscription(user_role_id, %{plan: "free", status: "active"})
    end
  end

  def get_subscription(user_role_id) do
    Repo.get_by(Subscription, user_role_id: user_role_id)
  end

  def create_subscription(user_role_id, attrs) do
    %Subscription{}
    |> Subscription.changeset(Map.put(attrs, :user_role_id, user_role_id))
    |> Repo.insert()
  end

  def update_subscription(%Subscription{} = sub, attrs) do
    sub
    |> Subscription.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Upgrades a user to a paid plan via Stripe checkout.
  Returns `{:ok, checkout_url}` for redirect.
  """
  def create_checkout(interactor_user_id, plan, success_url, cancel_url) do
    plan_id = plan_id_for(plan)

    case BillingClient.create_checkout_session(
           interactor_user_id,
           plan_id,
           success_url,
           cancel_url
         ) do
      {:ok, %{"data" => %{"checkout_url" => url}}} -> {:ok, url}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Activates a subscription after successful payment (called from webhook).
  """
  def activate_subscription(user_role_id, attrs) do
    case get_or_create_subscription(user_role_id) do
      {:ok, sub} ->
        update_subscription(sub, %{
          plan: attrs[:plan] || attrs["plan"],
          status: "active",
          billing_subscription_id:
            attrs[:billing_subscription_id] || attrs["billing_subscription_id"],
          stripe_customer_id: attrs[:stripe_customer_id] || attrs["stripe_customer_id"],
          current_period_start: attrs[:current_period_start] || attrs["current_period_start"],
          current_period_end: attrs[:current_period_end] || attrs["current_period_end"]
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Cancels a user's subscription at end of billing period.
  """
  def cancel_subscription(user_role_id) do
    case get_subscription(user_role_id) do
      %Subscription{billing_subscription_id: billing_id} = sub when not is_nil(billing_id) ->
        case BillingClient.cancel_subscription(billing_id) do
          {:ok, _} ->
            update_subscription(sub, %{
              cancelled_at: DateTime.utc_now(),
              status: "cancelled"
            })

          {:error, reason} ->
            {:error, reason}
        end

      %Subscription{} = sub ->
        update_subscription(sub, %{plan: "free", cancelled_at: DateTime.utc_now()})

      nil ->
        {:error, :no_subscription}
    end
  end

  ## Remote Subscription Data (from Billing Server)

  @doc """
  Fetches the full subscription details from the billing server.
  """
  def fetch_remote_subscriptions do
    BillingClient.get_subscriptions()
  end

  ## Payment Methods

  @doc """
  Creates a Stripe SetupIntent for adding a new payment method.
  Returns `{:ok, %{"client_secret" => ..., "setup_intent_id" => ...}}`.
  """
  def create_setup_intent(subscription_id) do
    BillingClient.create_setup_intent(subscription_id)
  end

  @doc """
  Lists saved payment methods for a subscription.
  """
  def list_payment_methods(subscription_id) do
    BillingClient.list_payment_methods(subscription_id)
  end

  @doc """
  Sets a payment method as the default.
  """
  def set_default_payment_method(payment_method_id) do
    BillingClient.set_default_payment_method(payment_method_id)
  end

  @doc """
  Removes a payment method.
  """
  def remove_payment_method(payment_method_id) do
    BillingClient.remove_payment_method(payment_method_id)
  end

  ## Invoices

  @doc """
  Lists invoices / payment history.
  """
  def list_invoices do
    BillingClient.list_invoices()
  end

  def get_invoice(invoice_id) do
    BillingClient.get_invoice(invoice_id)
  end

  ## Usage Tracking

  def record_test_usage(user_role_id, test_type, course_id \\ nil) do
    attrs = %{
      user_role_id: user_role_id,
      test_type: test_type,
      course_id: course_id
    }

    case %TestUsage{} |> TestUsage.changeset(attrs) |> Repo.insert() do
      {:ok, usage} ->
        report_to_billing_server(user_role_id)
        {:ok, usage}

      error ->
        error
    end
  end

  defp report_to_billing_server(user_role_id) do
    Task.start(fn ->
      case FunSheep.Accounts.get_user_role(user_role_id) do
        %{interactor_user_id: iuid} when not is_nil(iuid) ->
          BillingClient.report_usage(iuid, "tests_taken")

        _ ->
          :ok
      end
    end)
  end

  ## Limit Checking

  def check_test_allowance(user_role_id, role) do
    if role in ["parent", "teacher", :parent, :teacher] do
      :ok
    else
      check_student_allowance(user_role_id)
    end
  end

  defp check_student_allowance(user_role_id) do
    {:ok, sub} = get_or_create_subscription(user_role_id)

    if Subscription.paid?(sub) do
      :ok
    else
      check_free_tier_limits(user_role_id)
    end
  end

  defp check_free_tier_limits(user_role_id) do
    total_tests = count_total_tests(user_role_id)
    weekly_tests = count_weekly_tests(user_role_id)

    cond do
      total_tests < @initial_free_tests ->
        :ok

      weekly_tests < @weekly_free_tests ->
        :ok

      true ->
        {:error, :limit_reached,
         %{
           total_tests: total_tests,
           weekly_tests: weekly_tests,
           initial_limit: @initial_free_tests,
           weekly_limit: @weekly_free_tests,
           resets_at: next_week_reset()
         }}
    end
  end

  def usage_stats(user_role_id) do
    {:ok, sub} = get_or_create_subscription(user_role_id)
    total = count_total_tests(user_role_id)
    weekly = count_weekly_tests(user_role_id)

    %{
      plan: sub.plan,
      status: sub.status,
      paid: Subscription.paid?(sub),
      total_tests: total,
      weekly_tests: weekly,
      initial_limit: @initial_free_tests,
      weekly_limit: @weekly_free_tests,
      initial_remaining: max(0, @initial_free_tests - total),
      weekly_remaining: max(0, @weekly_free_tests - weekly),
      can_test: sub.plan != "free" or total < @initial_free_tests or weekly < @weekly_free_tests,
      resets_at: next_week_reset(),
      subscription: sub
    }
  end

  ## Query Helpers

  defp count_total_tests(user_role_id) do
    from(t in TestUsage, where: t.user_role_id == ^user_role_id, select: count(t.id))
    |> Repo.one()
  end

  defp count_weekly_tests(user_role_id) do
    week_ago = DateTime.add(DateTime.utc_now(), -7, :day)

    from(t in TestUsage,
      where: t.user_role_id == ^user_role_id and t.inserted_at >= ^week_ago,
      select: count(t.id)
    )
    |> Repo.one()
  end

  defp next_week_reset do
    now = DateTime.utc_now()
    days_until_monday = rem(8 - Date.day_of_week(now), 7)
    days_until_monday = if days_until_monday == 0, do: 7, else: days_until_monday

    now
    |> DateTime.add(days_until_monday, :day)
    |> Map.merge(%{hour: 0, minute: 0, second: 0, microsecond: {0, 0}})
  end

  ## Plan Helpers

  def plan_details do
    [
      %{
        id: "free",
        name: "Free",
        price: 0,
        interval: nil,
        description: "Get started with FunSheep",
        features: [
          "5 free tests to try",
          "3 tests per week",
          "Practice mode (unlimited)",
          "Study guides"
        ]
      },
      %{
        id: "monthly",
        name: "Monthly",
        price: 30,
        interval: "month",
        description: "Unlimited access",
        features: [
          "Unlimited tests",
          "All test formats",
          "Practice mode (unlimited)",
          "Study guides",
          "Readiness tracking",
          "Priority support"
        ]
      },
      %{
        id: "annual",
        name: "Annual",
        price: 90,
        interval: "year",
        description: "Best value — save 75%",
        features: [
          "Everything in Monthly",
          "Save 75% vs monthly",
          "Early access to new features"
        ]
      }
    ]
  end

  defp plan_id_for("monthly"), do: "plan_monthly"
  defp plan_id_for("annual"), do: "plan_annual"
  defp plan_id_for(_), do: "plan_free"
end
