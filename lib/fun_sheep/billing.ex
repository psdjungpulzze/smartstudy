defmodule FunSheep.Billing do
  @moduledoc """
  The Billing context.

  Manages subscriptions, test usage tracking, limit enforcement,
  payment methods, and invoices via the Interactor Billing Server.

  ## Free Tier Limits
    - 50 initial free tests (lifetime)
    - 50 free tests per week (rolling 7-day window)

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
  alias FunSheep.Questions.QuestionAttempt
  alias FunSheep.Interactor.Billing, as: BillingClient

  @initial_free_tests 50
  @weekly_free_tests 50

  ## Subscription Management

  @doc """
  Returns true if the user's active subscription includes AI scored freeform grading.
  Currently gates on any paid plan (monthly/annual). Narrows to premium/professional
  when those tiers are added.
  """
  def subscription_has_scored_grading?(user_role_id) do
    case get_subscription(user_role_id) do
      %Subscription{} = sub -> Subscription.paid?(sub)
      nil -> false
    end
  end

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

  Optional `metadata` is forwarded to the Stripe checkout session (via
  Interactor Billing). Used by Flow A (§4.7) to carry
  `practice_request_id` and `paid_by_interactor_user_id` so the webhook
  can stamp `Subscription.paid_by_user_role_id` +
  `origin_practice_request_id` on activation.
  """
  def create_checkout(interactor_user_id, plan, success_url, cancel_url, metadata \\ %{}) do
    plan_id = plan_id_for(plan)

    case BillingClient.create_checkout_session(
           interactor_user_id,
           plan_id,
           success_url,
           cancel_url,
           metadata
         ) do
      {:ok, %{"data" => %{"checkout_url" => url}}} -> {:ok, url}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Activates a subscription after successful payment (called from webhook).

  Accepts optional `:paid_by_user_role_id` (payer, for Flow A / Flow B)
  and `:origin_practice_request_id` (the ask that produced this
  purchase, Flow A only). See §3.1, §7.2.
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
          current_period_end: attrs[:current_period_end] || attrs["current_period_end"],
          paid_by_user_role_id: attrs[:paid_by_user_role_id] || attrs["paid_by_user_role_id"],
          origin_practice_request_id:
            attrs[:origin_practice_request_id] || attrs["origin_practice_request_id"]
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
    initial_limit = effective_initial_limit(user_role_id)

    cond do
      total_tests < initial_limit ->
        :ok

      weekly_tests < @weekly_free_tests ->
        :ok

      true ->
        {:error, :limit_reached,
         %{
           total_tests: total_tests,
           weekly_tests: weekly_tests,
           initial_limit: initial_limit,
           weekly_limit: @weekly_free_tests,
           resets_at: next_week_reset()
         }}
    end
  end

  def usage_stats(user_role_id) do
    {:ok, sub} = get_or_create_subscription(user_role_id)
    total = count_total_tests(user_role_id)
    weekly = count_weekly_tests(user_role_id)
    initial_limit = @initial_free_tests + (sub.bonus_free_tests || 0)

    %{
      plan: sub.plan,
      status: sub.status,
      paid: Subscription.paid?(sub),
      total_tests: total,
      weekly_tests: weekly,
      initial_limit: initial_limit,
      weekly_limit: @weekly_free_tests,
      initial_remaining: max(0, initial_limit - total),
      weekly_remaining: max(0, @weekly_free_tests - weekly),
      can_test: sub.plan != "free" or total < initial_limit or weekly < @weekly_free_tests,
      resets_at: next_week_reset(),
      subscription: sub
    }
  end

  ## Flow A usage helpers (§7.3)
  ##
  ## Roll up existing `TestUsage` data. Do NOT introduce a parallel counter
  ## table. Used by the student usage meter (§4.1) and by
  ## `FunSheep.PracticeRequests` to gate the 70%/85%/100% surfaces.

  @doc """
  Returns weekly usage for a student:
  `%{used, limit, remaining, resets_at}`.

  `:resets_at` is a sliding-window timestamp — when the oldest of the
  current weekly tests ages past 7 days (the moment the student regains
  exactly one free slot). If the student is under the limit, returns
  the current time.
  """
  def weekly_usage(user_role_id) do
    used = count_weekly_tests(user_role_id)
    limit = @weekly_free_tests
    remaining = max(0, limit - used)

    %{
      used: used,
      limit: limit,
      remaining: remaining,
      resets_at: compute_weekly_resets_at(user_role_id, used, limit)
    }
  end

  @doc """
  Returns lifetime usage for a student:
  `%{used, limit, remaining}`.
  """
  def lifetime_usage(user_role_id) do
    used = count_total_tests(user_role_id)
    limit = effective_initial_limit(user_role_id)
    %{used: used, limit: limit, remaining: max(0, limit - used)}
  end

  defp effective_initial_limit(user_role_id) do
    bonus =
      case get_subscription(user_role_id) do
        %Subscription{bonus_free_tests: b} when is_integer(b) -> b
        _ -> 0
      end

    @initial_free_tests + bonus
  end

  @doc """
  Returns the pill/dashboard state per §4.1:

    * `:paid`           — user has an active paid subscription
    * `:not_applicable` — non-student role (parent/teacher/admin)
    * `:fresh`          — 0–50% of weekly cap used
    * `:warming`        — 50–70%
    * `:nudge`          — 70–85% (soft pre-prompt threshold)
    * `:ask`            — 85–99% (Ask card unlocks)
    * `:hardwall`       — 100%+ (soft hard-wall)
  """
  def usage_state(user_role_id) do
    cond do
      paid_subscription?(user_role_id) -> :paid
      not student_role?(user_role_id) -> :not_applicable
      true -> free_tier_state(user_role_id)
    end
  end

  @doc """
  Returns `true` if the student can start a new test right now.

  Paid subscribers and non-student roles always return `true`. Free-tier
  students return `true` while under both the lifetime cap and the
  weekly cap — matching the existing `check_test_allowance/2` logic.
  """
  def can_start_test?(user_role_id) do
    case usage_state(user_role_id) do
      :paid ->
        true

      :not_applicable ->
        true

      :hardwall ->
        false

      _ ->
        count_total_tests(user_role_id) < effective_initial_limit(user_role_id)
    end
  end

  defp paid_subscription?(user_role_id) do
    case get_subscription(user_role_id) do
      %Subscription{} = sub -> Subscription.paid?(sub)
      nil -> false
    end
  end

  defp student_role?(user_role_id) do
    case FunSheep.Accounts.get_user_role(user_role_id) do
      %{role: :student} -> true
      _ -> false
    end
  end

  defp free_tier_state(user_role_id) do
    %{used: used, limit: limit} = weekly_usage(user_role_id)
    # §4.1 thresholds — `>=` at each boundary so 17/20 (exactly 85%)
    # advances into `:ask`, matching the spec's "at 85%" Ask-card trigger.
    ratio = if limit == 0, do: 1.0, else: used / limit

    cond do
      ratio >= 1.0 -> :hardwall
      ratio >= 0.85 -> :ask
      ratio >= 0.7 -> :nudge
      ratio >= 0.5 -> :warming
      true -> :fresh
    end
  end

  defp compute_weekly_resets_at(_user_role_id, used, limit) when used < limit do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp compute_weekly_resets_at(user_role_id, _used, _limit) do
    week_ago = DateTime.add(DateTime.utc_now(), -7, :day)

    oldest =
      from(t in TestUsage,
        where: t.user_role_id == ^user_role_id and t.inserted_at >= ^week_ago,
        order_by: [asc: t.inserted_at],
        limit: 1,
        select: t.inserted_at
      )
      |> Repo.one()

    case oldest do
      nil -> DateTime.utc_now() |> DateTime.truncate(:second)
      ts -> DateTime.add(ts, 7, :day) |> DateTime.truncate(:second)
    end
  end

  @doc """
  Returns question stats for the past 7 days for a paid (unlimited) student.
  Used by the dashboard card to show motivating progress instead of a quota meter.
  """
  def paid_weekly_stats(user_role_id) do
    week_ago = DateTime.add(DateTime.utc_now(), -7, :day)

    result =
      from(a in QuestionAttempt,
        where: a.user_role_id == ^user_role_id and a.inserted_at >= ^week_ago,
        select: %{
          total: count(a.id),
          correct: sum(fragment("CASE WHEN ? THEN 1 ELSE 0 END", a.is_correct))
        }
      )
      |> Repo.one()

    %{questions: result.total || 0, correct: result.correct || 0}
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
          "50 free tests to try",
          "50 tests per week",
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

  @doc """
  Returns `true` if the user's subscription includes AI-powered essay grading.

  Essay grading uses Claude Opus and is gated to paid plans. Free-tier
  students see a locked overlay with an upgrade CTA.
  """
  def subscription_has_essay_grading?(user_role_id) do
    paid_subscription?(user_role_id)
  end

  # Maps plan names to the maximum course access_level they unlock.
  # This mirrors the rank table in the Courses context.
  @plan_max_access_level %{
    "free" => "preview",
    "monthly" => "standard",
    "annual" => "standard",
    "premium_monthly" => "premium",
    "premium_annual" => "professional",
    "professional_monthly" => "professional",
    "professional_annual" => "professional"
  }

  # Maps plan names to the catalog test types they unlock.
  # nil means "all test types".
  @plan_catalog_types %{
    "free" => [],
    "monthly" => ["sat", "act"],
    "annual" => ["sat", "act"],
    "premium_monthly" => ["sat", "act", "ap", "ib", "hsc", "clt"],
    "premium_annual" => nil,
    "professional_monthly" => nil,
    "professional_annual" => nil
  }

  @doc """
  Returns true if the given subscription plan grants access to the course's
  access_level.

  Access tiers (ascending):
    free → public + preview only
    monthly/annual → + standard
    premium_monthly → + premium
    premium_annual/professional → + professional
  """
  @spec subscription_grants_access?(Subscription.t() | nil, map()) :: boolean()
  def subscription_grants_access?(nil, course), do: course.access_level in ["public", "preview"]

  def subscription_grants_access?(%Subscription{} = sub, course) do
    plan = sub.plan || "free"
    max_level = Map.get(@plan_max_access_level, to_string(plan), "preview")

    access_level_rank = fn level ->
      case level do
        "public" -> 0
        "preview" -> 1
        "standard" -> 2
        "premium" -> 3
        "professional" -> 4
        _ -> 0
      end
    end

    access_level_rank.(course.access_level) <= access_level_rank.(max_level)
  end

  @doc """
  Returns the list of catalog test types accessible under a given plan,
  or nil if all types are accessible.
  """
  @spec catalog_types_for_plan(String.t()) :: [String.t()] | nil
  def catalog_types_for_plan(plan) do
    Map.get(@plan_catalog_types, to_string(plan), [])
  end

  defp plan_id_for("monthly"), do: "plan_monthly"
  defp plan_id_for("annual"), do: "plan_annual"
  defp plan_id_for(_), do: "plan_free"
end
