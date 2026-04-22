defmodule FunSheep.Interactor.Billing do
  @moduledoc """
  HTTP client for the Interactor Billing Server API.

  Handles plan listing, subscription management, payment methods,
  invoices, and usage reporting.
  """

  require Logger

  # ── Plans ──────────────────────────────────────────────────────────────────

  def list_plans do
    case get("/api/public/plans") do
      {:ok, %{"data" => plans}} -> {:ok, plans}
      {:ok, body} -> {:ok, body}
      error -> error
    end
  end

  # ── Subscriptions ──────────────────────────────────────────────────────────

  def create_subscription(plan_id) do
    post("/api/subscriptions", %{plan_id: plan_id})
  end

  def get_subscriptions do
    get("/api/subscriptions")
  end

  def change_plan(subscription_id, plan_id) do
    post("/api/subscriptions/#{subscription_id}/change-plan", %{plan_id: plan_id})
  end

  def cancel_subscription(subscription_id, cancellation_type \\ "end_of_cycle") do
    post("/api/subscriptions/#{subscription_id}/cancel", %{
      cancellation_type: cancellation_type
    })
  end

  def reinstate_subscription(subscription_id) do
    post("/api/subscriptions/#{subscription_id}/reinstate", %{})
  end

  # ── Payment Methods ────────────────────────────────────────────────────────

  @doc """
  Creates a Stripe SetupIntent for collecting a payment method.
  Returns `{:ok, %{"client_secret" => ..., "setup_intent_id" => ...}}`.
  """
  def create_setup_intent(subscription_id) do
    case post("/api/payment-methods/setup", %{subscription_id: subscription_id}) do
      {:ok, %{"data" => data}} -> {:ok, data}
      error -> error
    end
  end

  @doc """
  Lists saved payment methods for a subscription.
  """
  def list_payment_methods(subscription_id) do
    case get("/api/payment-methods?subscription_id=#{subscription_id}") do
      {:ok, %{"data" => methods}} -> {:ok, methods}
      error -> error
    end
  end

  @doc """
  Sets a payment method as default.
  """
  def set_default_payment_method(payment_method_id) do
    post("/api/payment-methods/#{payment_method_id}/set-default", %{})
  end

  @doc """
  Removes a payment method.
  """
  def remove_payment_method(payment_method_id) do
    delete("/api/payment-methods/#{payment_method_id}")
  end

  # ── Invoices ───────────────────────────────────────────────────────────────

  @doc """
  Lists invoices for the authenticated subscriber.
  """
  def list_invoices do
    case get("/api/invoices") do
      {:ok, %{"data" => invoices}} -> {:ok, invoices}
      error -> error
    end
  end

  def get_invoice(invoice_id) do
    case get("/api/invoices/#{invoice_id}") do
      {:ok, %{"data" => invoice}} -> {:ok, invoice}
      error -> error
    end
  end

  # ── Usage & Limits ─────────────────────────────────────────────────────────

  def report_usage(subscriber_id, metric_name, quantity \\ 1) do
    post("/api/usage", %{
      subscriber_id: subscriber_id,
      subscriber_type: "user",
      metric_name: metric_name,
      quantity: quantity
    })
  end

  def check_limits(subscriber_id) do
    get("/api/limits?subscriber_id=#{subscriber_id}&subscriber_type=user")
  end

  # ── Portal ─────────────────────────────────────────────────────────────────

  @doc """
  Creates a portal session for self-service management.
  Returns `{:ok, %{"portal_url" => ..., "expires_in" => ...}}`.
  """
  def create_portal_session(subscriber_id, subscriber_name) do
    case post("/api/portal/session", %{
           subscriber_id: subscriber_id,
           subscriber_name: subscriber_name
         }) do
      {:ok, %{"data" => data}} -> {:ok, data}
      error -> error
    end
  end

  # ── Checkout ───────────────────────────────────────────────────────────────

  def create_checkout_session(subscriber_id, plan_id, success_url, cancel_url) do
    post("/api/checkout/session", %{
      subscriber_id: subscriber_id,
      subscriber_type: "user",
      plan_id: plan_id,
      success_url: success_url,
      cancel_url: cancel_url
    })
  end

  # ── HTTP Helpers ───────────────────────────────────────────────────────────

  defp get(path) do
    if mock_mode?() do
      mock_get(path)
    else
      with {:ok, token} <- FunSheep.Interactor.Auth.get_token() do
        case Req.get(billing_url() <> path, headers: auth_headers(token)) do
          {:ok, %{status: 200, body: body}} -> {:ok, body}
          {:ok, %{status: status, body: body}} -> {:error, {status, body}}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  defp post(path, body) do
    if mock_mode?() do
      mock_post(path, body)
    else
      with {:ok, token} <- FunSheep.Interactor.Auth.get_token() do
        case Req.post(billing_url() <> path, json: body, headers: auth_headers(token)) do
          {:ok, %{status: status, body: resp}} when status in [200, 201] -> {:ok, resp}
          {:ok, %{status: status, body: resp}} -> {:error, {status, resp}}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  defp delete(path) do
    if mock_mode?() do
      {:ok, %{"status" => "deleted"}}
    else
      with {:ok, token} <- FunSheep.Interactor.Auth.get_token() do
        case Req.delete(billing_url() <> path, headers: auth_headers(token)) do
          {:ok, %{status: status}} when status in [200, 204] -> :ok
          {:ok, %{status: status, body: resp}} -> {:error, {status, resp}}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  defp auth_headers(token), do: [{"authorization", "Bearer #{token}"}]

  defp billing_url do
    Application.get_env(:fun_sheep, :interactor_billing_url, "https://billing.interactor.com")
  end

  defp mock_mode?, do: Application.get_env(:fun_sheep, :interactor_mock, false)

  # ── Mock Responses ─────────────────────────────────────────────────────────

  defp mock_get("/api/public/plans"), do: mock_get("/api/plans")

  defp mock_get("/api/plans") do
    {:ok,
     %{
       "data" => [
         %{
           "id" => "plan_free",
           "name" => "Free",
           "base_price" => "0.00",
           "currency" => "USD",
           "billing_period" => nil,
           "description" => "Get started with FunSheep",
           "metrics" => [
             %{
               "metric_name" => "tests",
               "base_limit" => 20,
               "reset_period" => "weekly",
               "base_limit_type" => "hard"
             }
           ]
         },
         %{
           "id" => "plan_monthly",
           "name" => "Monthly",
           "base_price" => "30.00",
           "currency" => "USD",
           "billing_period" => "monthly",
           "description" => "Unlimited access, billed monthly",
           "metrics" => [
             %{
               "metric_name" => "tests",
               "base_limit" => nil,
               "reset_period" => "monthly",
               "base_limit_type" => "soft"
             }
           ]
         },
         %{
           "id" => "plan_annual",
           "name" => "Annual",
           "base_price" => "90.00",
           "currency" => "USD",
           "billing_period" => "yearly",
           "description" => "Best value — save 75%",
           "metrics" => [
             %{
               "metric_name" => "tests",
               "base_limit" => nil,
               "reset_period" => "annual",
               "base_limit_type" => "soft"
             }
           ]
         }
       ]
     }}
  end

  defp mock_get("/api/subscriptions") do
    {:ok,
     %{
       "data" => [
         %{
           "id" => "sub_mock_001",
           "plan_id" => "plan_free",
           "status" => "active",
           "current_period_start" => DateTime.utc_now() |> DateTime.to_iso8601(),
           "current_period_end" =>
             DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.to_iso8601(),
           "on_trial" => false,
           "cancelled_at" => nil,
           "plan" => %{
             "id" => "plan_free",
             "name" => "Free",
             "base_price" => "0.00",
             "billing_period" => nil
           }
         }
       ]
     }}
  end

  defp mock_get("/api/payment-methods" <> _) do
    {:ok,
     %{
       "data" => [
         %{
           "id" => "pm_mock_visa",
           "type" => "card",
           "is_default" => true,
           "card" => %{
             "brand" => "visa",
             "last4" => "4242",
             "exp_month" => 12,
             "exp_year" => 2027
           }
         }
       ]
     }}
  end

  defp mock_get("/api/invoices") do
    now = DateTime.utc_now()

    {:ok,
     %{
       "data" => [
         %{
           "id" => "inv_mock_003",
           "invoice_number" => "INV-2026-003",
           "status" => "paid",
           "total" => "30.00",
           "currency" => "USD",
           "issued_at" => now |> DateTime.to_iso8601(),
           "paid_at" => now |> DateTime.add(1, :day) |> DateTime.to_iso8601(),
           "billing_period_start" => now |> DateTime.add(-30, :day) |> DateTime.to_iso8601(),
           "billing_period_end" => now |> DateTime.to_iso8601(),
           "line_items" => [
             %{
               "description" => "Monthly subscription",
               "quantity" => 1,
               "unit_price" => "30.00",
               "amount" => "30.00"
             }
           ]
         },
         %{
           "id" => "inv_mock_002",
           "invoice_number" => "INV-2026-002",
           "status" => "paid",
           "total" => "30.00",
           "currency" => "USD",
           "issued_at" => now |> DateTime.add(-30, :day) |> DateTime.to_iso8601(),
           "paid_at" => now |> DateTime.add(-29, :day) |> DateTime.to_iso8601(),
           "billing_period_start" => now |> DateTime.add(-60, :day) |> DateTime.to_iso8601(),
           "billing_period_end" => now |> DateTime.add(-30, :day) |> DateTime.to_iso8601(),
           "line_items" => [
             %{
               "description" => "Monthly subscription",
               "quantity" => 1,
               "unit_price" => "30.00",
               "amount" => "30.00"
             }
           ]
         }
       ]
     }}
  end

  defp mock_get("/api/invoices/" <> _id) do
    mock_get("/api/invoices")
    |> then(fn {:ok, %{"data" => [first | _]}} -> {:ok, %{"data" => first}} end)
  end

  defp mock_get("/api/limits" <> _), do: {:ok, %{"data" => %{"tests_per_week" => 3}}}
  defp mock_get(_path), do: {:ok, %{"data" => []}}

  defp mock_post("/api/payment-methods/setup", _body) do
    {:ok,
     %{
       "data" => %{
         "client_secret" => "seti_mock_secret_" <> Base.encode16(:crypto.strong_rand_bytes(8)),
         "setup_intent_id" => "seti_mock_" <> Base.encode16(:crypto.strong_rand_bytes(4))
       }
     }}
  end

  defp mock_post("/api/checkout/session", _body) do
    {:ok, %{"data" => %{"checkout_url" => "/subscription?success=true"}}}
  end

  defp mock_post("/api/portal/session", _body) do
    {:ok,
     %{
       "data" => %{
         "portal_url" => "/subscription?portal=mock",
         "expires_in" => 300
       }
     }}
  end

  defp mock_post("/api/subscriptions/" <> rest, _body) do
    cond do
      String.contains?(rest, "cancel") ->
        {:ok, %{"data" => %{"id" => "sub_mock_001", "status" => "cancelled"}}}

      String.contains?(rest, "reinstate") ->
        {:ok, %{"data" => %{"id" => "sub_mock_001", "status" => "active"}}}

      String.contains?(rest, "change-plan") ->
        {:ok, %{"data" => %{"id" => "sub_mock_001", "status" => "active"}}}

      true ->
        {:ok,
         %{
           "data" => %{
             "id" => "sub_mock_" <> Base.encode16(:crypto.strong_rand_bytes(4)),
             "status" => "active"
           }
         }}
    end
  end

  defp mock_post(_path, body) do
    mock_data =
      Map.merge(%{"id" => "mock_#{:rand.uniform(100_000)}"}, stringify_keys(body))

    {:ok, %{"data" => mock_data}}
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
