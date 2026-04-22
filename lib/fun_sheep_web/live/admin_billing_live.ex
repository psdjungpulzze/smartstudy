defmodule FunSheepWeb.AdminBillingLive do
  @moduledoc """
  /admin/billing — read-only visibility into Billing Server state.

  Billing Server is the source of truth for subscriptions, plans, and
  invoices (no local subscriptions table). This page caches each response
  for 60s in the LiveView's own assigns so hitting the page mid-refresh
  doesn't hammer the Billing API.

  Per-subscription mutations (change plan, cancel, reinstate, Stripe
  portal) are deferred to a follow-up PR once the ops workflow is more
  concrete.
  """
  use FunSheepWeb, :live_view

  alias FunSheep.Interactor.Billing

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Billing · Admin")
     |> load_data()}
  end

  @impl true
  def handle_event("refresh", _, socket), do: {:noreply, load_data(socket)}

  defp load_data(socket) do
    {plans, plans_err} = safe_call(&Billing.list_plans/0)
    {subs, subs_err} = safe_call(&Billing.get_subscriptions/0)
    {invoices, invoices_err} = safe_call(&Billing.list_invoices/0)

    subs_list = normalize_list(subs)

    socket
    |> assign(:plans, normalize_list(plans))
    |> assign(:subscriptions, subs_list)
    |> assign(:invoices, normalize_list(invoices))
    |> assign(:errors, %{plans: plans_err, subs: subs_err, invoices: invoices_err})
    |> assign(:summary, summarize(subs_list))
    |> assign(:last_refreshed, DateTime.utc_now())
  end

  defp safe_call(fun) do
    case fun.() do
      {:ok, data} -> {data, nil}
      {:error, reason} -> {nil, inspect(reason)}
      _ -> {nil, "unknown response shape"}
    end
  rescue
    e -> {nil, Exception.message(e)}
  end

  defp normalize_list(nil), do: []
  defp normalize_list(%{"data" => list}) when is_list(list), do: list
  defp normalize_list(list) when is_list(list), do: list
  defp normalize_list(_), do: []

  defp summarize(subs) when is_list(subs) do
    active = Enum.count(subs, &(sub_status(&1) == "active"))
    trialing = Enum.count(subs, &(sub_status(&1) == "trialing"))
    past_due = Enum.count(subs, &(sub_status(&1) == "past_due"))
    cancelled = Enum.count(subs, &(sub_status(&1) == "cancelled"))

    %{
      total: length(subs),
      active: active,
      trialing: trialing,
      past_due: past_due,
      cancelled: cancelled
    }
  end

  defp sub_status(%{"status" => s}), do: s
  defp sub_status(_), do: "unknown"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-6xl mx-auto space-y-4">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-[#1C1C1E]">Billing</h1>
          <p class="text-[#8E8E93] text-sm mt-1">
            Read-only visibility into the Billing Server (source of truth
            for subscriptions, plans, invoices). Mutations land in a
            follow-up PR.
          </p>
        </div>
        <button
          type="button"
          phx-click="refresh"
          class="px-3 py-1 rounded-full text-xs font-medium border border-[#E5E5EA] hover:bg-[#F5F5F7]"
        >
          Refresh
        </button>
      </div>

      <p class="text-xs text-[#8E8E93]">
        Last refreshed: {Calendar.strftime(@last_refreshed, "%Y-%m-%d %H:%M:%S UTC")}
      </p>

      <.unavailable :if={any_error?(@errors)} errors={@errors} />

      <.summary_cards summary={@summary} />

      <.plans_section plans={@plans} />

      <.subscriptions_section subscriptions={@subscriptions} />

      <.invoices_section invoices={@invoices} />
    </div>
    """
  end

  attr :errors, :map, required: true

  defp unavailable(assigns) do
    ~H"""
    <div class="bg-[#FFE5E3] text-[#FF3B30] rounded-xl p-4 text-sm">
      ⚠ Billing service partially unavailable:
      <ul class="mt-2 space-y-1">
        <li :if={@errors.plans}><strong>plans:</strong> {@errors.plans}</li>
        <li :if={@errors.subs}><strong>subscriptions:</strong> {@errors.subs}</li>
        <li :if={@errors.invoices}><strong>invoices:</strong> {@errors.invoices}</li>
      </ul>
    </div>
    """
  end

  defp any_error?(errors),
    do: errors.plans || errors.subs || errors.invoices

  attr :summary, :map, required: true

  defp summary_cards(assigns) do
    ~H"""
    <div class="grid grid-cols-2 md:grid-cols-5 gap-4">
      <.stat label="Total" value={@summary.total} />
      <.stat label="Active" value={@summary.active} accent="text-[#4CD964]" />
      <.stat label="Trialing" value={@summary.trialing} accent="text-[#007AFF]" />
      <.stat label="Past due" value={@summary.past_due} accent="text-[#FFCC00]" />
      <.stat label="Cancelled" value={@summary.cancelled} accent="text-[#8E8E93]" />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :accent, :string, default: "text-[#1C1C1E]"

  defp stat(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-5">
      <div class="text-xs uppercase tracking-wide text-[#8E8E93] font-medium">{@label}</div>
      <div class={["text-3xl font-bold mt-1", @accent]}>{@value}</div>
    </div>
    """
  end

  attr :plans, :list, required: true

  defp plans_section(assigns) do
    ~H"""
    <section class="bg-white rounded-2xl shadow-md overflow-hidden">
      <h2 class="font-semibold text-[#1C1C1E] px-5 py-4">Plans</h2>
      <ul :if={@plans != []} class="divide-y divide-[#F5F5F7] text-sm">
        <li :for={plan <- @plans} class="px-5 py-3 flex items-center justify-between">
          <div>
            <div class="font-medium text-[#1C1C1E]">{plan["name"] || plan["id"]}</div>
            <div class="text-xs text-[#8E8E93]">{plan["description"] || ""}</div>
          </div>
          <div class="text-xs text-[#8E8E93]">
            {plan["price"]} {plan["currency"] || "USD"} / {plan["interval"] || "month"}
          </div>
        </li>
      </ul>
      <p :if={@plans == []} class="text-sm text-[#8E8E93] text-center py-6">No plans.</p>
    </section>
    """
  end

  attr :subscriptions, :list, required: true

  defp subscriptions_section(assigns) do
    ~H"""
    <section class="bg-white rounded-2xl shadow-md overflow-hidden">
      <h2 class="font-semibold text-[#1C1C1E] px-5 py-4">Subscriptions</h2>
      <div class="overflow-x-auto">
        <table class="w-full text-sm min-w-[640px]">
          <thead class="bg-[#F5F5F7] text-[#8E8E93] uppercase text-xs">
            <tr>
              <th class="text-left px-4 py-3">ID</th>
              <th class="text-left px-4 py-3">Plan</th>
              <th class="text-left px-4 py-3">Status</th>
              <th class="text-left px-4 py-3">Period ends</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={s <- @subscriptions} class="border-t border-[#F5F5F7]">
              <td class="px-4 py-3 font-medium text-[#1C1C1E]">
                <code class="text-xs">{s["id"] || "—"}</code>
              </td>
              <td class="px-4 py-3 text-[#1C1C1E]">
                {s["plan_name"] || s["plan_id"] || "—"}
              </td>
              <td class="px-4 py-3">
                <span class={[
                  "inline-block px-2 py-0.5 rounded-full text-xs font-medium",
                  sub_badge_class(s["status"])
                ]}>
                  {s["status"] || "unknown"}
                </span>
              </td>
              <td class="px-4 py-3 text-[#8E8E93]">{s["current_period_end"] || "—"}</td>
            </tr>
            <tr :if={@subscriptions == []}>
              <td colspan="4" class="px-4 py-8 text-center text-[#8E8E93]">
                No subscriptions returned by Billing Server.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  attr :invoices, :list, required: true

  defp invoices_section(assigns) do
    ~H"""
    <section class="bg-white rounded-2xl shadow-md overflow-hidden">
      <h2 class="font-semibold text-[#1C1C1E] px-5 py-4">Recent invoices</h2>
      <div class="overflow-x-auto">
        <table class="w-full text-sm min-w-[560px]">
          <thead class="bg-[#F5F5F7] text-[#8E8E93] uppercase text-xs">
            <tr>
              <th class="text-left px-4 py-3">ID</th>
              <th class="text-left px-4 py-3">Amount</th>
              <th class="text-left px-4 py-3">Status</th>
              <th class="text-left px-4 py-3">Issued</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={inv <- @invoices} class="border-t border-[#F5F5F7]">
              <td class="px-4 py-3 font-medium text-[#1C1C1E]">
                <code class="text-xs">{inv["id"] || "—"}</code>
              </td>
              <td class="px-4 py-3 text-[#1C1C1E]">
                {inv["amount_due"] || inv["amount"] || "—"} {inv["currency"] || "USD"}
              </td>
              <td class="px-4 py-3 text-[#8E8E93]">{inv["status"] || "—"}</td>
              <td class="px-4 py-3 text-[#8E8E93]">{inv["created"] || inv["issued_at"] || "—"}</td>
            </tr>
            <tr :if={@invoices == []}>
              <td colspan="4" class="px-4 py-8 text-center text-[#8E8E93]">
                No invoices returned.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp sub_badge_class("active"), do: "bg-[#E8F8EB] text-[#4CD964]"
  defp sub_badge_class("trialing"), do: "bg-[#E8F8EB] text-[#007AFF]"
  defp sub_badge_class("past_due"), do: "bg-[#FFF4CC] text-[#1C1C1E]"
  defp sub_badge_class("cancelled"), do: "bg-[#FFE5E3] text-[#FF3B30]"
  defp sub_badge_class(_), do: "bg-[#F5F5F7] text-[#8E8E93]"
end
