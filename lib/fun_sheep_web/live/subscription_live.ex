defmodule FunSheepWeb.SubscriptionLive do
  use FunSheepWeb, :live_view

  alias FunSheep.Billing

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    user_role_id = user["user_role_id"] || user["id"]
    role = user["role"]

    stats = Billing.usage_stats(user_role_id)
    plans = Billing.plan_details()

    invoices =
      case Billing.list_invoices() do
        {:ok, inv} -> inv
        {:error, _} -> []
      end

    {:ok, sub} = Billing.get_or_create_subscription(user_role_id)

    payment_methods =
      if sub.billing_subscription_id do
        case Billing.list_payment_methods(sub.billing_subscription_id) do
          {:ok, methods} -> methods
          _ -> []
        end
      else
        case Billing.list_payment_methods("sub_mock_001") do
          {:ok, methods} -> methods
          _ -> []
        end
      end

    socket =
      socket
      |> assign(
        page_title: "Billing & Subscription",
        user_role_id: user_role_id,
        interactor_user_id: user["interactor_user_id"],
        role: role,
        stats: stats,
        plans: plans,
        invoices: invoices,
        payment_methods: payment_methods,
        active_tab: "overview",
        checkout_loading: nil,
        show_add_card: false,
        setup_intent: nil
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    tab = params["tab"] || "overview"

    socket =
      socket
      |> assign(:active_tab, tab)
      |> maybe_handle_checkout_return(params)

    {:noreply, socket}
  end

  defp maybe_handle_checkout_return(socket, %{"success" => "true"}) do
    stats = Billing.usage_stats(socket.assigns.user_role_id)

    socket
    |> assign(:stats, stats)
    |> put_flash(:info, "Welcome to FunSheep Premium! Enjoy unlimited tests.")
  end

  defp maybe_handle_checkout_return(socket, %{"cancelled" => "true"}) do
    put_flash(socket, :info, "Checkout cancelled. No changes made.")
  end

  defp maybe_handle_checkout_return(socket, _), do: socket

  # ── Events ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/subscription?tab=#{tab}")}
  end

  def handle_event("upgrade", %{"plan" => plan}, socket) do
    socket = assign(socket, :checkout_loading, plan)
    success_url = url(socket, ~p"/subscription?tab=overview&success=true")
    cancel_url = url(socket, ~p"/subscription?tab=plans&cancelled=true")

    case Billing.create_checkout(socket.assigns.interactor_user_id, plan, success_url, cancel_url) do
      {:ok, checkout_url} ->
        {:noreply, redirect(socket, external: checkout_url)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:checkout_loading, nil)
         |> put_flash(:error, "Unable to start checkout. Please try again.")}
    end
  end

  def handle_event("cancel_subscription", _params, socket) do
    case Billing.cancel_subscription(socket.assigns.user_role_id) do
      {:ok, _sub} ->
        stats = Billing.usage_stats(socket.assigns.user_role_id)

        {:noreply,
         socket
         |> assign(:stats, stats)
         |> put_flash(
           :info,
           "Subscription cancelled. You'll keep access until the billing period ends."
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Unable to cancel. Please try again.")}
    end
  end

  def handle_event("show_add_card", _params, socket) do
    sub = socket.assigns.stats.subscription
    sub_id = sub.billing_subscription_id || "sub_mock_001"

    case Billing.create_setup_intent(sub_id) do
      {:ok, intent} ->
        {:noreply, assign(socket, show_add_card: true, setup_intent: intent)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not initialize card setup.")}
    end
  end

  def handle_event("cancel_add_card", _params, socket) do
    {:noreply, assign(socket, show_add_card: false, setup_intent: nil)}
  end

  def handle_event("card_setup_complete", %{"payment_method_id" => _pm_id}, socket) do
    sub = socket.assigns.stats.subscription
    sub_id = sub.billing_subscription_id || "sub_mock_001"

    methods =
      case Billing.list_payment_methods(sub_id) do
        {:ok, m} -> m
        _ -> socket.assigns.payment_methods
      end

    {:noreply,
     socket
     |> assign(payment_methods: methods, show_add_card: false, setup_intent: nil)
     |> put_flash(:info, "Payment method added successfully.")}
  end

  def handle_event("set_default_card", %{"id" => pm_id}, socket) do
    case Billing.set_default_payment_method(pm_id) do
      {:ok, _} ->
        sub = socket.assigns.stats.subscription
        sub_id = sub.billing_subscription_id || "sub_mock_001"

        methods =
          case Billing.list_payment_methods(sub_id) do
            {:ok, m} -> m
            _ -> socket.assigns.payment_methods
          end

        {:noreply,
         socket
         |> assign(:payment_methods, methods)
         |> put_flash(:info, "Default payment method updated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update default payment method.")}
    end
  end

  def handle_event("remove_card", %{"id" => pm_id}, socket) do
    case Billing.remove_payment_method(pm_id) do
      :ok ->
        methods = Enum.reject(socket.assigns.payment_methods, &(&1["id"] == pm_id))
        {:noreply, assign(socket, :payment_methods, methods) |> put_flash(:info, "Card removed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove card.")}
    end
  end

  # ── Render ─────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-6">
      <%!-- Header --%>
      <div class="mb-6">
        <h1 class="text-2xl sm:text-3xl font-bold text-[#1C1C1E] dark:text-white">
          Billing & Subscription
        </h1>
        <p class="text-[#8E8E93] text-sm mt-1">Manage your plan, payment methods, and invoices</p>
      </div>

      <%!-- Tab Navigation --%>
      <div class="flex gap-1 mb-6 bg-[#F5F5F7] dark:bg-[#1C1C1E] rounded-full p-1 overflow-x-auto">
        <.tab_button
          :for={
            {label, tab} <- [
              {"Overview", "overview"},
              {"Plans", "plans"},
              {"Payment", "payment"},
              {"History", "history"}
            ]
          }
          label={label}
          tab={tab}
          active={@active_tab}
        />
      </div>

      <%!-- Tab Content --%>
      <div :if={@active_tab == "overview"}>
        <.overview_tab
          stats={@stats}
          role={@role}
          plans={@plans}
          payment_methods={@payment_methods}
          invoices={@invoices}
        />
      </div>

      <div :if={@active_tab == "plans"}>
        <.plans_tab
          stats={@stats}
          plans={@plans}
          role={@role}
          checkout_loading={@checkout_loading}
        />
      </div>

      <div :if={@active_tab == "payment"}>
        <.payment_tab
          payment_methods={@payment_methods}
          show_add_card={@show_add_card}
          setup_intent={@setup_intent}
          stats={@stats}
        />
      </div>

      <div :if={@active_tab == "history"}>
        <.history_tab invoices={@invoices} />
      </div>
    </div>
    """
  end

  # ── Tab Button ─────────────────────────────────────────────────────────────

  attr :label, :string, required: true
  attr :tab, :string, required: true
  attr :active, :string, required: true

  defp tab_button(assigns) do
    ~H"""
    <button
      phx-click="switch_tab"
      phx-value-tab={@tab}
      class={[
        "flex-1 min-w-0 px-4 py-2 rounded-full text-xs sm:text-sm font-medium transition-all whitespace-nowrap",
        if(@active == @tab,
          do: "bg-white dark:bg-[#2C2C2E] text-[#1C1C1E] dark:text-white shadow-sm",
          else: "text-[#8E8E93] hover:text-[#1C1C1E] dark:hover:text-white"
        )
      ]}
    >
      {@label}
    </button>
    """
  end

  # ── Overview Tab ───────────────────────────────────────────────────────────

  attr :stats, :map, required: true
  attr :role, :any, required: true
  attr :plans, :list, required: true
  attr :payment_methods, :list, required: true
  attr :invoices, :list, required: true

  defp overview_tab(assigns) do
    current_plan = Enum.find(assigns.plans, &(&1.id == assigns.stats.plan))
    default_card = Enum.find(assigns.payment_methods, &(&1["is_default"] == true))
    latest_invoice = List.first(assigns.invoices)

    assigns =
      assign(assigns,
        current_plan: current_plan,
        default_card: default_card,
        latest_invoice: latest_invoice
      )

    ~H"""
    <div class="space-y-6">
      <%!-- Current Plan Card --%>
      <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6">
        <div class="flex items-start justify-between">
          <div>
            <p class="text-xs font-medium text-[#8E8E93] uppercase tracking-wide">Current Plan</p>
            <h2 class="text-2xl font-bold text-[#1C1C1E] dark:text-white mt-1">
              {(@current_plan && @current_plan.name) || "Free"}
            </h2>
            <p class="text-sm text-[#8E8E93] mt-1">
              {if @current_plan && @current_plan.price > 0,
                do: "$#{@current_plan.price}/#{@current_plan.interval}",
                else: "No charge"}
            </p>
          </div>

          <div class={[
            "px-3 py-1 rounded-full text-xs font-medium",
            case @stats.status do
              "active" -> "bg-[#E8F8EB] text-[#4CD964]"
              "cancelled" -> "bg-red-50 text-[#FF3B30]"
              "past_due" -> "bg-[#FFCC00]/10 text-[#FFCC00]"
              _ -> "bg-[#F5F5F7] text-[#8E8E93]"
            end
          ]}>
            {String.capitalize(@stats.status)}
          </div>
        </div>

        <%= if @stats.status == "cancelled" do %>
          <div class="mt-4 p-3 bg-[#FFCC00]/10 border border-[#FFCC00]/30 rounded-xl text-sm text-[#1C1C1E] dark:text-white">
            Your subscription has been cancelled. You'll keep access until the end of the current billing period.
          </div>
        <% end %>

        <div class="flex gap-3 mt-4">
          <%= if @stats.paid do %>
            <button
              phx-click="cancel_subscription"
              data-confirm="Are you sure you want to cancel? You'll keep access until the end of your billing period."
              class="px-4 py-2 rounded-full border border-[#E5E5EA] dark:border-[#3A3A3C] text-sm font-medium text-[#8E8E93] hover:bg-[#F5F5F7] dark:hover:bg-[#1C1C1E] transition-colors"
            >
              Cancel Plan
            </button>
          <% else %>
            <button
              phx-click="switch_tab"
              phx-value-tab="plans"
              class="px-4 py-2 rounded-full bg-[#4CD964] hover:bg-[#3DBF55] text-white text-sm font-medium shadow-md transition-colors"
            >
              Upgrade
            </button>
          <% end %>
        </div>
      </div>

      <%!-- Usage Summary (students only) --%>
      <%= if @role in ["student", :student] do %>
        <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6">
          <h3 class="text-sm font-medium text-[#8E8E93] uppercase tracking-wide mb-4">Usage</h3>

          <div class="grid grid-cols-3 gap-4">
            <div class="text-center">
              <div class="text-2xl font-bold text-[#1C1C1E] dark:text-white">
                {@stats.total_tests}
              </div>
              <div class="text-xs text-[#8E8E93] mt-1">Total Tests</div>
            </div>
            <div class="text-center">
              <div class="text-2xl font-bold text-[#1C1C1E] dark:text-white">
                {@stats.weekly_tests}<span class="text-sm font-normal text-[#8E8E93]">/{@stats.weekly_limit}</span>
              </div>
              <div class="text-xs text-[#8E8E93] mt-1">This Week</div>
            </div>
            <div class="text-center">
              <div class={"text-2xl font-bold #{if @stats.can_test, do: "text-[#4CD964]", else: "text-[#FF3B30]"}"}>
                {if @stats.paid, do: "∞", else: "#{@stats.weekly_remaining}"}
              </div>
              <div class="text-xs text-[#8E8E93] mt-1">Remaining</div>
            </div>
          </div>

          <%= if not @stats.paid do %>
            <%!-- Usage bar --%>
            <div class="mt-4">
              <div class="flex justify-between text-xs text-[#8E8E93] mb-1">
                <span>Weekly usage</span>
                <span>{@stats.weekly_tests} of {@stats.weekly_limit}</span>
              </div>
              <div class="w-full bg-[#F5F5F7] dark:bg-[#1C1C1E] rounded-full h-2">
                <div
                  class={"h-2 rounded-full transition-all #{if @stats.weekly_tests >= @stats.weekly_limit, do: "bg-[#FF3B30]", else: "bg-[#4CD964]"}"}
                  style={"width: #{min(100, round(@stats.weekly_tests / max(@stats.weekly_limit, 1) * 100))}%"}
                />
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Quick Info Cards --%>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <%!-- Payment Method --%>
        <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-5">
          <div class="flex items-center justify-between mb-3">
            <h3 class="text-sm font-medium text-[#8E8E93] uppercase tracking-wide">Payment Method</h3>
            <button
              phx-click="switch_tab"
              phx-value-tab="payment"
              class="text-xs text-[#007AFF] hover:text-[#0066DD] font-medium"
            >
              Manage
            </button>
          </div>
          <%= if @default_card do %>
            <div class="flex items-center gap-3">
              <.card_brand_icon brand={@default_card["card"]["brand"]} />
              <div>
                <p class="text-sm font-medium text-[#1C1C1E] dark:text-white">
                  •••• {@default_card["card"]["last4"]}
                </p>
                <p class="text-xs text-[#8E8E93]">
                  Expires {@default_card["card"]["exp_month"]}/{@default_card["card"]["exp_year"]}
                </p>
              </div>
            </div>
          <% else %>
            <p class="text-sm text-[#8E8E93]">No payment method on file</p>
            <button
              phx-click="switch_tab"
              phx-value-tab="payment"
              class="mt-2 text-sm text-[#4CD964] hover:text-[#3DBF55] font-medium"
            >
              + Add card
            </button>
          <% end %>
        </div>

        <%!-- Latest Invoice --%>
        <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-5">
          <div class="flex items-center justify-between mb-3">
            <h3 class="text-sm font-medium text-[#8E8E93] uppercase tracking-wide">Latest Invoice</h3>
            <button
              phx-click="switch_tab"
              phx-value-tab="history"
              class="text-xs text-[#007AFF] hover:text-[#0066DD] font-medium"
            >
              View all
            </button>
          </div>
          <%= if @latest_invoice do %>
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm font-medium text-[#1C1C1E] dark:text-white">
                  ${@latest_invoice["total"]}
                </p>
                <p class="text-xs text-[#8E8E93]">
                  {format_date(@latest_invoice["issued_at"])}
                </p>
              </div>
              <.invoice_status_badge status={@latest_invoice["status"]} />
            </div>
          <% else %>
            <p class="text-sm text-[#8E8E93]">No invoices yet</p>
          <% end %>
        </div>
      </div>

      <%!-- Parent/Teacher notice --%>
      <%= if @role not in ["student", :student] do %>
        <div class="bg-[#E8F8EB] dark:bg-[#4CD964]/10 rounded-2xl p-6">
          <div class="flex items-center gap-3">
            <svg
              class="w-6 h-6 text-[#4CD964]"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <div>
              <p class="font-medium text-[#1C1C1E] dark:text-white">Free Account</p>
              <p class="text-sm text-[#8E8E93]">
                Parent and teacher accounts are always free. No billing required.
              </p>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Plans Tab ──────────────────────────────────────────────────────────────

  attr :stats, :map, required: true
  attr :plans, :list, required: true
  attr :role, :any, required: true
  attr :checkout_loading, :string, default: nil

  defp plans_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="text-center mb-2">
        <h2 class="text-xl font-bold text-[#1C1C1E] dark:text-white">Choose your plan</h2>
        <p class="text-sm text-[#8E8E93] mt-1">
          Upgrade anytime. Cancel anytime. No hidden fees.
        </p>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-5">
        <%= for plan <- @plans do %>
          <div class={[
            "bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 flex flex-col relative",
            if(plan.id == "annual", do: "ring-2 ring-[#4CD964]", else: "")
          ]}>
            <%= if plan.id == "annual" do %>
              <div class="absolute -top-3 left-1/2 -translate-x-1/2 bg-[#4CD964] text-white text-xs font-bold px-3 py-1 rounded-full">
                Best Value
              </div>
            <% end %>

            <h3 class="text-lg font-bold text-[#1C1C1E] dark:text-white">{plan.name}</h3>
            <p class="text-sm text-[#8E8E93] mt-1">{plan.description}</p>

            <div class="mt-4 mb-5">
              <span class="text-4xl font-bold text-[#1C1C1E] dark:text-white">
                {if plan.price == 0, do: "Free", else: "$#{plan.price}"}
              </span>
              <%= if plan.interval do %>
                <span class="text-[#8E8E93] text-sm">/{plan.interval}</span>
              <% end %>
              <%= if plan.id == "annual" do %>
                <p class="text-xs text-[#4CD964] font-medium mt-1">$7.50/month effective</p>
              <% end %>
            </div>

            <ul class="space-y-2.5 mb-6 flex-grow">
              <%= for feature <- plan.features do %>
                <li class="flex items-start gap-2 text-sm text-[#1C1C1E] dark:text-white">
                  <svg
                    class="w-4 h-4 text-[#4CD964] flex-shrink-0 mt-0.5"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="2"
                    stroke="currentColor"
                  >
                    <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" />
                  </svg>
                  {feature}
                </li>
              <% end %>
            </ul>

            <%= cond do %>
              <% plan.id == @stats.plan -> %>
                <div class="text-center py-2.5 px-6 rounded-full bg-[#F5F5F7] dark:bg-[#1C1C1E] text-[#8E8E93] font-medium text-sm">
                  Current Plan
                </div>
              <% plan.id == "free" and @stats.paid -> %>
                <button
                  phx-click="cancel_subscription"
                  data-confirm="Are you sure? You'll lose premium access at the end of your billing period."
                  class="w-full py-2.5 px-6 rounded-full border border-[#E5E5EA] dark:border-[#3A3A3C] text-[#1C1C1E] dark:text-white font-medium text-sm hover:bg-[#F5F5F7] dark:hover:bg-[#1C1C1E] transition-colors"
                >
                  Downgrade
                </button>
              <% plan.id == "free" -> %>
                <div />
              <% true -> %>
                <button
                  phx-click="upgrade"
                  phx-value-plan={plan.id}
                  disabled={@checkout_loading != nil}
                  class="w-full py-2.5 px-6 rounded-full bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium text-sm shadow-md transition-colors disabled:opacity-50"
                >
                  {if @checkout_loading == plan.id, do: "Loading...", else: "Upgrade to #{plan.name}"}
                </button>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- FAQ --%>
      <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 mt-6">
        <h3 class="font-bold text-[#1C1C1E] dark:text-white mb-4">Frequently Asked Questions</h3>
        <div class="space-y-4">
          <.faq_item
            question="Can I cancel anytime?"
            answer="Yes! You can cancel your subscription at any time. You'll keep access until the end of your current billing period."
          />
          <.faq_item
            question="What happens to my data if I downgrade?"
            answer="Your data is never deleted. All test history, study guides, and progress are preserved even on the free plan."
          />
          <.faq_item
            question="Is practice mode always free?"
            answer="Yes! Practice mode is always unlimited on all plans, including the free plan."
          />
          <.faq_item
            question="Are parent and teacher accounts free?"
            answer="Yes! Parent and teacher accounts are always free. Only student accounts taking tests are subject to plan limits."
          />
        </div>
      </div>
    </div>
    """
  end

  # ── Payment Tab ────────────────────────────────────────────────────────────

  attr :payment_methods, :list, required: true
  attr :show_add_card, :boolean, required: true
  attr :setup_intent, :map, default: nil
  attr :stats, :map, required: true

  defp payment_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Payment Methods --%>
      <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-bold text-[#1C1C1E] dark:text-white">Payment Methods</h3>
          <button
            :if={!@show_add_card}
            phx-click="show_add_card"
            class="px-4 py-2 rounded-full bg-[#4CD964] hover:bg-[#3DBF55] text-white text-sm font-medium shadow-md transition-colors"
          >
            + Add Card
          </button>
        </div>

        <%!-- Card list --%>
        <%= if @payment_methods == [] do %>
          <div class="text-center py-8">
            <svg
              class="w-12 h-12 text-[#E5E5EA] mx-auto mb-3"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M2.25 8.25h19.5M2.25 9h19.5m-16.5 5.25h6m-6 2.25h3m-3.75 3h15a2.25 2.25 0 002.25-2.25V6.75A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25v10.5A2.25 2.25 0 004.5 19.5z"
              />
            </svg>
            <p class="text-[#8E8E93] text-sm">No payment methods on file</p>
            <p class="text-xs text-[#8E8E93] mt-1">Add a card to upgrade to a paid plan</p>
          </div>
        <% else %>
          <div class="space-y-3">
            <div
              :for={pm <- @payment_methods}
              class="flex items-center justify-between p-4 bg-[#F5F5F7] dark:bg-[#1C1C1E] rounded-xl"
            >
              <div class="flex items-center gap-3">
                <.card_brand_icon brand={pm["card"]["brand"]} />
                <div>
                  <p class="text-sm font-medium text-[#1C1C1E] dark:text-white">
                    {String.capitalize(pm["card"]["brand"])} •••• {pm["card"]["last4"]}
                  </p>
                  <p class="text-xs text-[#8E8E93]">
                    Expires {pm["card"]["exp_month"]}/{pm["card"]["exp_year"]}
                  </p>
                </div>
                <span
                  :if={pm["is_default"]}
                  class="px-2 py-0.5 rounded-full bg-[#E8F8EB] text-[#4CD964] text-xs font-medium"
                >
                  Default
                </span>
              </div>
              <div class="flex items-center gap-2">
                <button
                  :if={!pm["is_default"]}
                  phx-click="set_default_card"
                  phx-value-id={pm["id"]}
                  class="text-xs text-[#007AFF] hover:text-[#0066DD] font-medium"
                >
                  Set default
                </button>
                <button
                  phx-click="remove_card"
                  phx-value-id={pm["id"]}
                  data-confirm="Remove this card?"
                  class="text-xs text-[#FF3B30] hover:text-red-700 font-medium"
                >
                  Remove
                </button>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Add Card Form (Stripe Elements) --%>
        <div :if={@show_add_card} class="mt-4 border-t border-[#E5E5EA] dark:border-[#3A3A3C] pt-4">
          <h4 class="text-sm font-medium text-[#1C1C1E] dark:text-white mb-3">Add a new card</h4>

          <div
            id="stripe-card-element"
            phx-hook="StripeCardSetup"
            data-client-secret={@setup_intent && @setup_intent["client_secret"]}
            class="p-4 bg-[#F5F5F7] dark:bg-[#1C1C1E] rounded-xl mb-4"
          >
            <div id="card-element" class="min-h-[40px]">
              <%!-- Stripe Elements will mount here --%>
              <p class="text-sm text-[#8E8E93] animate-pulse">Loading secure card form...</p>
            </div>
            <div id="card-errors" class="text-sm text-[#FF3B30] mt-2 hidden"></div>
          </div>

          <div class="flex gap-3">
            <button
              id="submit-card-btn"
              class="px-6 py-2 rounded-full bg-[#4CD964] hover:bg-[#3DBF55] text-white text-sm font-medium shadow-md transition-colors disabled:opacity-50"
            >
              Save Card
            </button>
            <button
              phx-click="cancel_add_card"
              class="px-6 py-2 rounded-full border border-[#E5E5EA] dark:border-[#3A3A3C] text-sm font-medium text-[#8E8E93] hover:bg-[#F5F5F7] transition-colors"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>

      <%!-- Billing Details --%>
      <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6">
        <h3 class="text-lg font-bold text-[#1C1C1E] dark:text-white mb-4">Billing Details</h3>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <p class="text-xs text-[#8E8E93] uppercase tracking-wide">Plan</p>
            <p class="text-sm font-medium text-[#1C1C1E] dark:text-white mt-1">
              {String.capitalize(@stats.plan)}
            </p>
          </div>
          <div>
            <p class="text-xs text-[#8E8E93] uppercase tracking-wide">Status</p>
            <p class="text-sm font-medium text-[#1C1C1E] dark:text-white mt-1">
              {String.capitalize(@stats.status)}
            </p>
          </div>
          <div>
            <p class="text-xs text-[#8E8E93] uppercase tracking-wide">Billing Period</p>
            <p class="text-sm font-medium text-[#1C1C1E] dark:text-white mt-1">
              {if @stats.paid, do: String.capitalize(@stats.plan <> "ly"), else: "N/A"}
            </p>
          </div>
          <div>
            <p class="text-xs text-[#8E8E93] uppercase tracking-wide">Next Invoice</p>
            <p class="text-sm font-medium text-[#1C1C1E] dark:text-white mt-1">
              {if @stats.subscription.current_period_end,
                do: Calendar.strftime(@stats.subscription.current_period_end, "%B %d, %Y"),
                else: "N/A"}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── History Tab ────────────────────────────────────────────────────────────

  attr :invoices, :list, required: true

  defp history_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md overflow-hidden">
        <div class="p-6 border-b border-[#E5E5EA] dark:border-[#3A3A3C]">
          <h3 class="text-lg font-bold text-[#1C1C1E] dark:text-white">Payment History</h3>
          <p class="text-sm text-[#8E8E93] mt-1">View your past invoices and payments</p>
        </div>

        <%= if @invoices == [] do %>
          <div class="p-12 text-center">
            <svg
              class="w-12 h-12 text-[#E5E5EA] mx-auto mb-3"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z"
              />
            </svg>
            <p class="text-[#8E8E93]">No invoices yet</p>
            <p class="text-xs text-[#8E8E93] mt-1">
              Invoices will appear here when you upgrade to a paid plan
            </p>
          </div>
        <% else %>
          <%!-- Desktop table --%>
          <div class="hidden sm:block">
            <table class="w-full">
              <thead>
                <tr class="text-left text-xs text-[#8E8E93] uppercase tracking-wide">
                  <th class="px-6 py-3 font-medium">Invoice</th>
                  <th class="px-6 py-3 font-medium">Date</th>
                  <th class="px-6 py-3 font-medium">Amount</th>
                  <th class="px-6 py-3 font-medium">Status</th>
                  <th class="px-6 py-3 font-medium"></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-[#E5E5EA] dark:divide-[#3A3A3C]">
                <tr
                  :for={inv <- @invoices}
                  class="hover:bg-[#F5F5F7] dark:hover:bg-[#1C1C1E] transition-colors"
                >
                  <td class="px-6 py-4">
                    <p class="text-sm font-medium text-[#1C1C1E] dark:text-white">
                      {inv["invoice_number"]}
                    </p>
                    <p class="text-xs text-[#8E8E93]">
                      {format_period(inv["billing_period_start"], inv["billing_period_end"])}
                    </p>
                  </td>
                  <td class="px-6 py-4 text-sm text-[#1C1C1E] dark:text-white">
                    {format_date(inv["issued_at"])}
                  </td>
                  <td class="px-6 py-4 text-sm font-medium text-[#1C1C1E] dark:text-white">
                    ${inv["total"]} {String.upcase(inv["currency"] || "USD")}
                  </td>
                  <td class="px-6 py-4">
                    <.invoice_status_badge status={inv["status"]} />
                  </td>
                  <td class="px-6 py-4 text-right">
                    <button class="text-xs text-[#007AFF] hover:text-[#0066DD] font-medium">
                      Download
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <%!-- Mobile list --%>
          <div class="sm:hidden divide-y divide-[#E5E5EA] dark:divide-[#3A3A3C]">
            <div :for={inv <- @invoices} class="p-4">
              <div class="flex items-center justify-between">
                <div>
                  <p class="text-sm font-medium text-[#1C1C1E] dark:text-white">
                    {inv["invoice_number"]}
                  </p>
                  <p class="text-xs text-[#8E8E93] mt-0.5">{format_date(inv["issued_at"])}</p>
                </div>
                <div class="text-right">
                  <p class="text-sm font-bold text-[#1C1C1E] dark:text-white">${inv["total"]}</p>
                  <.invoice_status_badge status={inv["status"]} />
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ── Shared Components ──────────────────────────────────────────────────────

  attr :brand, :string, required: true

  defp card_brand_icon(assigns) do
    ~H"""
    <div class="w-10 h-7 bg-white dark:bg-[#2C2C2E] rounded-lg border border-[#E5E5EA] dark:border-[#3A3A3C] flex items-center justify-center">
      <span class="text-xs font-bold text-[#1C1C1E] dark:text-white uppercase">
        {card_brand_abbr(@brand)}
      </span>
    </div>
    """
  end

  defp card_brand_abbr("visa"), do: "VISA"
  defp card_brand_abbr("mastercard"), do: "MC"
  defp card_brand_abbr("amex"), do: "AMEX"
  defp card_brand_abbr("discover"), do: "DISC"
  defp card_brand_abbr(other), do: String.upcase(String.slice(other || "CARD", 0..3))

  attr :status, :string, required: true

  defp invoice_status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-block px-2 py-0.5 rounded-full text-xs font-medium",
      case @status do
        "paid" -> "bg-[#E8F8EB] text-[#4CD964]"
        "draft" -> "bg-[#F5F5F7] text-[#8E8E93]"
        "issued" -> "bg-blue-50 text-[#007AFF]"
        "past_due" -> "bg-red-50 text-[#FF3B30]"
        _ -> "bg-[#F5F5F7] text-[#8E8E93]"
      end
    ]}>
      {String.capitalize(@status || "unknown")}
    </span>
    """
  end

  attr :question, :string, required: true
  attr :answer, :string, required: true

  defp faq_item(assigns) do
    ~H"""
    <details class="group">
      <summary class="flex items-center justify-between cursor-pointer list-none py-2">
        <span class="text-sm font-medium text-[#1C1C1E] dark:text-white">{@question}</span>
        <svg
          class="w-4 h-4 text-[#8E8E93] group-open:rotate-180 transition-transform"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
        >
          <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 8.25l-7.5 7.5-7.5-7.5" />
        </svg>
      </summary>
      <p class="text-sm text-[#8E8E93] pb-2 pl-0">{@answer}</p>
    </details>
    """
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp format_date(nil), do: "—"

  defp format_date(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%b %d, %Y")
      _ -> date_string
    end
  end

  defp format_period(nil, _), do: ""
  defp format_period(_, nil), do: ""

  defp format_period(start_str, end_str) do
    with {:ok, s, _} <- DateTime.from_iso8601(start_str),
         {:ok, e, _} <- DateTime.from_iso8601(end_str) do
      "#{Calendar.strftime(s, "%b %d")} – #{Calendar.strftime(e, "%b %d, %Y")}"
    else
      _ -> ""
    end
  end
end
