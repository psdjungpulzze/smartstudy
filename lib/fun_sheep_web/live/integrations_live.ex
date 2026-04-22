defmodule FunSheepWeb.IntegrationsLive do
  @moduledoc """
  Integrations management page.

  Shows one card per available provider (Google Classroom, Canvas,
  ParentSquare), each with a Connect/Disconnect/Sync-now action and
  a status line describing the last sync or error. Live-updates via
  `FunSheep.Integrations` PubSub topic when a webhook or worker
  changes a connection.
  """

  use FunSheepWeb, :live_view

  alias FunSheep.Integrations
  alias FunSheep.Integrations.{IntegrationConnection, Registry}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    user_role_id = user["user_role_id"] || user["id"]

    if connected?(socket) and not is_nil(user_role_id) do
      Integrations.subscribe(user_role_id)
    end

    connections = Integrations.list_for_user(user_role_id)

    socket =
      socket
      |> assign(:page_title, "Connected apps")
      |> assign(:user_role_id, user_role_id)
      |> assign(:connections_by_provider, index_by_provider(connections))
      |> assign(:providers, Registry.all())
      |> assign(:canvas_host_input, "")

    {:ok, socket}
  end

  @impl true
  def handle_info({:integration_event, _event, _payload}, socket) do
    connections = Integrations.list_for_user(socket.assigns.user_role_id)

    {:noreply, assign(socket, :connections_by_provider, index_by_provider(connections))}
  end

  @impl true
  def handle_event("update_canvas_host", %{"canvas_host" => host}, socket) do
    {:noreply, assign(socket, :canvas_host_input, host)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6 space-y-6">
      <header class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold text-[#1C1C1E] dark:text-white">
            Connected apps
          </h1>
          <p class="text-sm text-[#8E8E93] mt-1">
            Auto-import your courses and upcoming tests from your school apps.
            FunSheep never stores your password — Interactor handles the connection.
          </p>
        </div>
      </header>

      <div class="grid gap-4 md:grid-cols-1">
        <%= for {provider_atom, module} <- @providers do %>
          <.provider_card
            provider={provider_atom}
            module={module}
            connection={Map.get(@connections_by_provider, provider_atom)}
            canvas_host={@canvas_host_input}
          />
        <% end %>
      </div>
    </div>
    """
  end

  # ── Components ──────────────────────────────────────────────────────

  attr :provider, :atom, required: true
  attr :module, :atom, required: true
  attr :connection, :any, default: nil
  attr :canvas_host, :string, default: ""

  defp provider_card(assigns) do
    ~H"""
    <div
      class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 border border-[#E5E5EA] dark:border-[#3A3A3C]"
      data-test={"provider-card-#{@provider}"}
    >
      <div class="flex items-start justify-between gap-4">
        <div class="flex-1">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-lg bg-[#E8F8EB] flex items-center justify-center text-xl">
              {provider_emoji(@provider)}
            </div>
            <div>
              <h2 class="text-lg font-semibold text-[#1C1C1E] dark:text-white">
                {Registry.label(@provider)}
              </h2>
              <p class="text-xs text-[#8E8E93]">
                {provider_description(@provider)}
              </p>
            </div>
          </div>

          <.status_line connection={@connection} module={@module} />
        </div>

        <div class="flex flex-col items-end gap-2 shrink-0">
          <.action_buttons
            provider={@provider}
            module={@module}
            connection={@connection}
            canvas_host={@canvas_host}
          />
        </div>
      </div>

      <%= if @provider == :canvas and is_nil(@connection) and @module.supported?() do %>
        <form phx-change="update_canvas_host" class="mt-4">
          <label class="block text-xs text-[#8E8E93] mb-1">
            Canvas URL (e.g. yourschool.instructure.com)
          </label>
          <input
            type="text"
            name="canvas_host"
            value={@canvas_host}
            placeholder="yourschool.instructure.com"
            class="w-full px-4 py-2 bg-[#F5F5F7] dark:bg-[#1C1C1E] border border-transparent focus:border-[#4CD964] rounded-full text-sm outline-none transition-colors"
          />
        </form>
      <% end %>
    </div>
    """
  end

  attr :connection, :any, default: nil
  attr :module, :atom, required: true

  defp status_line(%{connection: nil, module: module} = assigns) do
    assigns = assign(assigns, :supported, module.supported?())

    ~H"""
    <p class="mt-4 text-sm text-[#8E8E93]">
      <%= if @supported do %>
        Not connected.
      <% else %>
        Coming soon — we're investigating a safe way to integrate this provider.
      <% end %>
    </p>
    """
  end

  defp status_line(assigns) do
    ~H"""
    <div class="mt-4 space-y-1">
      <p class="text-sm">
        <span class={status_badge_class(@connection.status)}>
          {status_label(@connection.status)}
        </span>
      </p>
      <%= if @connection.last_sync_at do %>
        <p class="text-xs text-[#8E8E93]">
          Last synced
          <time datetime={DateTime.to_iso8601(@connection.last_sync_at)}>
            {format_time(@connection.last_sync_at)}
          </time>
        </p>
      <% end %>
      <%= if @connection.last_sync_error do %>
        <p class="text-xs text-[#FF3B30]">
          {@connection.last_sync_error}
        </p>
      <% end %>
    </div>
    """
  end

  attr :provider, :atom, required: true
  attr :module, :atom, required: true
  attr :connection, :any, default: nil
  attr :canvas_host, :string, default: ""

  defp action_buttons(%{connection: nil, module: module} = assigns) do
    assigns = assign(assigns, :supported, module.supported?())

    ~H"""
    <%= if @supported do %>
      <.link
        href={connect_href(@provider, @canvas_host)}
        class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors text-sm"
      >
        Connect
      </.link>
    <% else %>
      <button
        disabled
        class="bg-gray-200 text-gray-500 font-medium px-6 py-2 rounded-full text-sm cursor-not-allowed"
      >
        Coming soon
      </button>
    <% end %>
    """
  end

  defp action_buttons(assigns) do
    ~H"""
    <form method="post" action={~p"/integrations/#{@connection.id}/sync"} class="inline">
      <input
        type="hidden"
        name="_csrf_token"
        value={Phoenix.Controller.get_csrf_token()}
      />
      <button
        type="submit"
        class="bg-white hover:bg-gray-50 text-gray-700 border border-gray-200 font-medium px-4 py-2 rounded-full shadow-sm text-sm transition-colors"
      >
        Sync now
      </button>
    </form>
    <form
      method="post"
      action={~p"/integrations/#{@connection.id}"}
      class="inline"
      data-confirm="Disconnect this integration? Your imported courses stay, but they won't update anymore."
    >
      <input type="hidden" name="_method" value="delete" />
      <input
        type="hidden"
        name="_csrf_token"
        value={Phoenix.Controller.get_csrf_token()}
      />
      <button
        type="submit"
        class="bg-[#FF3B30] hover:bg-red-600 text-white font-medium px-4 py-2 rounded-full shadow-md text-sm transition-colors"
      >
        Disconnect
      </button>
    </form>
    """
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp index_by_provider(connections) do
    Map.new(connections, fn %IntegrationConnection{} = c -> {c.provider, c} end)
  end

  defp connect_href(:canvas, host) when is_binary(host) and host != "" do
    "/integrations/connect/canvas?canvas_host=#{URI.encode_www_form(host)}"
  end

  defp connect_href(provider, _host), do: "/integrations/connect/#{provider}"

  defp provider_emoji(:google_classroom), do: "🎓"
  defp provider_emoji(:canvas), do: "🎨"
  defp provider_emoji(:parentsquare), do: "🟦"
  defp provider_emoji(_), do: "🔗"

  defp provider_description(:google_classroom),
    do: "Import your active classes and coursework marked as test/quiz/exam."

  defp provider_description(:canvas),
    do: "Import active courses and any assignment with a future due date."

  defp provider_description(:parentsquare),
    do: "District messaging — not yet wired up."

  defp provider_description(_), do: ""

  defp status_badge_class(status) do
    base = "inline-flex items-center px-3 py-0.5 rounded-full text-xs font-medium "

    base <>
      case status do
        :active -> "bg-[#E8F8EB] text-[#1C7F2F]"
        :syncing -> "bg-blue-50 text-blue-700"
        :pending -> "bg-gray-100 text-gray-700"
        :error -> "bg-red-50 text-[#FF3B30]"
        :expired -> "bg-yellow-50 text-yellow-700"
        :revoked -> "bg-gray-100 text-gray-500"
      end
  end

  defp status_label(:active), do: "Connected"
  defp status_label(:syncing), do: "Syncing…"
  defp status_label(:pending), do: "Pending"
  defp status_label(:error), do: "Error"
  defp status_label(:expired), do: "Expired"
  defp status_label(:revoked), do: "Revoked"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end

  defp format_time(_), do: "—"
end
