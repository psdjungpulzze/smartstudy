defmodule FunSheepWeb.UpgradeModalComponent do
  @moduledoc """
  Upgrade interstitial modal for locked premium catalog courses.

  Shows when a user clicks "Unlock" on a course they don't have access to.
  Presents subscription options and a per-course à la carte option.
  Emits `close_upgrade_modal` when dismissed.
  """

  use FunSheepWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Backdrop --%>
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in"
      phx-click="close_upgrade_modal"
      phx-target={@myself}
    >
      <%!-- Modal panel — stop click propagation so inner clicks don't close --%>
      <div
        class="relative w-full max-w-md bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-2xl p-8 animate-slide-up"
        phx-click-away="close_upgrade_modal"
        phx-target={@myself}
      >
        <%!-- Close button --%>
        <button
          phx-click="close_upgrade_modal"
          phx-target={@myself}
          class="absolute top-4 right-4 p-1.5 rounded-full text-gray-400 hover:text-gray-600 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
          aria-label="Close"
        >
          <.icon name="hero-x-mark" class="w-5 h-5" />
        </button>

        <%!-- Header --%>
        <div class="text-center mb-6">
          <div class="text-5xl mb-3">🐑</div>
          <h2 class="text-2xl font-extrabold text-gray-900 dark:text-white">FunSheep Premium</h2>
          <p class="text-gray-500 dark:text-[#8E8E93] text-sm mt-2 leading-snug">
            Unlock <strong class="text-gray-900 dark:text-white">{@course.name}</strong>
            &mdash; and every course in the premium catalog.
          </p>
        </div>

        <%!-- Feature list --%>
        <ul class="space-y-2.5 mb-7">
          <.feature_item
            icon="hero-academic-cap"
            text="All AP subjects (Calculus, Biology, Chemistry, and more)"
          />
          <.feature_item icon="hero-question-mark-circle" text="6,000+ exam-quality questions" />
          <.feature_item icon="hero-check-badge" text="College Board & IB aligned content" />
          <.feature_item icon="hero-cpu-chip" text="AI tutor with personalized explanations" />
          <.feature_item icon="hero-chart-bar" text="Readiness tracking to your test date" />
        </ul>

        <%!-- Primary CTA — subscription --%>
        <.link
          navigate={~p"/subscription?tab=plans"}
          class="block w-full text-center bg-[#4CD964] hover:bg-[#3DBF55] text-white font-bold px-6 py-3.5 rounded-full shadow-md btn-bounce text-sm transition-colors mb-3"
        >
          Subscribe — $149/year
        </.link>

        <%!-- Secondary CTA — à la carte --%>
        <.link
          navigate={~p"/subscription?tab=plans"}
          class="block w-full text-center bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-[#3A3A3C] hover:bg-gray-50 dark:hover:bg-[#2C2C2E] text-gray-700 dark:text-white font-medium px-6 py-3 rounded-full text-sm transition-colors mb-4"
        >
          Or get just this course — $9.99 once
        </.link>

        <%!-- Dismiss + Sign-in links --%>
        <div class="flex items-center justify-between text-xs text-gray-400 dark:text-[#8E8E93]">
          <button
            phx-click="close_upgrade_modal"
            phx-target={@myself}
            class="hover:text-gray-600 dark:hover:text-white transition-colors"
          >
            No thanks, go back
          </button>
          <.link navigate={~p"/auth/login"} class="hover:text-[#4CD964] transition-colors">
            Already subscribed? Sign in
          </.link>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("close_upgrade_modal", _params, socket) do
    send(self(), {:close_upgrade_modal})
    {:noreply, socket}
  end

  # ── Feature item component ────────────────────────────────────────────────────

  attr :icon, :string, required: true
  attr :text, :string, required: true

  defp feature_item(assigns) do
    ~H"""
    <li class="flex items-start gap-3">
      <div class="w-5 h-5 rounded-full bg-[#E8F8EB] flex items-center justify-center shrink-0 mt-0.5">
        <.icon name={@icon} class="w-3.5 h-3.5 text-[#4CD964]" />
      </div>
      <span class="text-sm text-gray-700 dark:text-[#E5E5EA]">{@text}</span>
    </li>
    """
  end
end
