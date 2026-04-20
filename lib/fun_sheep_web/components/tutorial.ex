defmodule FunSheepWeb.Components.Tutorial do
  @moduledoc """
  Reusable first-visit tutorial overlay.

  Each page passes a `title` and a list of `steps` (emoji/title/body). The
  overlay is dismissed via the `dismiss_tutorial` event, which the parent
  LiveView must handle to persist `FunSheep.Tutorials.mark_seen/2` and hide
  the overlay.

  ## Example

      <.tutorial
        :if={@show_tutorial}
        title="Welcome to your dashboard"
        steps={[
          %{emoji: "👋", title: "Your home base", body: "Jump into practice any time."},
          %{emoji: "📚", title: "Browse courses", body: "Find what you want to learn."}
        ]}
      />

  The parent LiveView handles the close/replay events:

      def handle_event("dismiss_tutorial", _params, socket) do
        Tutorials.mark_seen(socket.assigns.current_user["user_role_id"], "dashboard")
        {:noreply, assign(socket, show_tutorial: false)}
      end

      def handle_event("replay_tutorial", _params, socket) do
        {:noreply, assign(socket, show_tutorial: true)}
      end
  """

  use Phoenix.Component

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :cta_label, :string, default: "Got it!"

  attr :steps, :list,
    required: true,
    doc: "List of maps with keys :emoji, :title, :body"

  def tutorial(assigns) do
    ~H"""
    <div
      id="tutorial-overlay"
      class="fixed inset-0 z-[60] bg-black/70 backdrop-blur-sm flex items-center justify-center p-4"
      phx-click="dismiss_tutorial"
      role="dialog"
      aria-modal="true"
      aria-labelledby="tutorial-title"
    >
      <div
        class="w-full max-w-md bg-white rounded-2xl shadow-2xl p-6 space-y-4"
        onclick="event.stopPropagation()"
      >
        <div class="flex items-start justify-between gap-3">
          <div>
            <h2 id="tutorial-title" class="text-xl font-bold text-[#1C1C1E]">
              {@title}
            </h2>
            <p :if={@subtitle} class="text-sm text-[#8E8E93] mt-1">
              {@subtitle}
            </p>
          </div>
          <button
            type="button"
            phx-click="dismiss_tutorial"
            class="p-1 text-[#8E8E93] hover:text-[#1C1C1E] shrink-0"
            aria-label="Close tutorial"
          >
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <ul class="space-y-3">
          <li
            :for={step <- @steps}
            class="flex items-start gap-3 p-3 bg-[#F5F5F7] rounded-xl"
          >
            <span class="text-2xl shrink-0" aria-hidden="true">{step[:emoji] || step["emoji"]}</span>
            <div class="flex-1 min-w-0">
              <p class="font-semibold text-[#1C1C1E] text-sm">
                {step[:title] || step["title"]}
              </p>
              <p class="text-xs text-[#8E8E93] mt-0.5">
                {step[:body] || step["body"]}
              </p>
            </div>
          </li>
        </ul>

        <button
          type="button"
          phx-click="dismiss_tutorial"
          class="w-full py-3 bg-[#4CD964] hover:bg-[#3DBF55] text-white font-semibold rounded-full shadow-md transition-colors min-h-[44px]"
        >
          {@cta_label}
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Small help (?) button to replay the tutorial. Parent must handle
  `replay_tutorial` by assigning `show_tutorial: true`.
  """
  attr :label, :string, default: "Show tutorial"

  def tutorial_replay_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="replay_tutorial"
      class="w-8 h-8 rounded-full border border-[#E5E5EA] text-[#8E8E93] hover:text-[#4CD964] hover:border-[#4CD964] flex items-center justify-center text-sm font-bold transition-colors"
      aria-label={@label}
      title={@label}
    >
      ?
    </button>
    """
  end
end
