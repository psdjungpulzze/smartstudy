defmodule FunSheepWeb.AdminHealthLive do
  @moduledoc """
  /admin/health — at-a-glance service status.

  Pulls one snapshot per mount. Every 30s the page refreshes via a
  self-scheduled `:tick` message so admins can leave the page open as a
  makeshift status page.
  """
  use FunSheepWeb, :live_view

  alias FunSheep.Admin.Health

  @refresh_ms 30_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_tick()

    {:ok,
     socket
     |> assign(:page_title, "Health · Admin")
     |> assign(:snapshot, Health.snapshot())
     |> assign(:last_refreshed, DateTime.utc_now())}
  end

  @impl true
  def handle_info(:tick, socket) do
    schedule_tick()

    {:noreply,
     socket
     |> assign(:snapshot, Health.snapshot())
     |> assign(:last_refreshed, DateTime.utc_now())}
  end

  @impl true
  def handle_event("refresh", _, socket) do
    {:noreply,
     socket
     |> assign(:snapshot, Health.snapshot())
     |> assign(:last_refreshed, DateTime.utc_now())}
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @refresh_ms)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-4xl mx-auto space-y-4">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-[#1C1C1E]">System health</h1>
          <p class="text-[#8E8E93] text-sm mt-1">
            Live probes of Postgres, Oban, Interactor, and the mailer.
            Refreshes automatically every 30s.
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
        Last checked: {Calendar.strftime(@last_refreshed, "%Y-%m-%d %H:%M:%S UTC")}
      </p>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <.tile label="Postgres" probe={@snapshot.postgres} />
        <.tile label="Oban" probe={@snapshot.oban} />
        <.tile label="Interactor (via ai_calls)" probe={@snapshot.ai_calls} />
        <.tile label="Mailer" probe={@snapshot.mailer} />
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :probe, :map, required: true

  defp tile(assigns) do
    {label, ring, text_class} =
      case assigns.probe.status do
        :ok -> {"OK", "ring-[#4CD964]/40", "text-[#4CD964]"}
        :degraded -> {"Degraded", "ring-[#FFCC00]/40", "text-[#1C1C1E]"}
        :down -> {"Down", "ring-[#FF3B30]/40", "text-[#FF3B30]"}
      end

    assigns = assign(assigns, status_label: label, ring: ring, text_class: text_class)

    ~H"""
    <div class={["bg-white rounded-2xl shadow-md p-6 ring-2", @ring]}>
      <div class="flex items-center justify-between">
        <h3 class="font-semibold text-[#1C1C1E]">{@label}</h3>
        <span class={["text-xs font-medium", @text_class]}>● {@status_label}</span>
      </div>
      <pre class="text-xs bg-[#F5F5F7] p-3 rounded-lg mt-3 whitespace-pre-wrap break-all">{format_detail(@probe.detail)}</pre>
    </div>
    """
  end

  defp format_detail(nil), do: "(no detail)"

  defp format_detail(data) do
    case Jason.encode(data, pretty: true) do
      {:ok, json} -> json
      _ -> inspect(data, pretty: true)
    end
  end
end
