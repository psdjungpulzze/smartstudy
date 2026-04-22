defmodule FunSheepWeb.AdminInteractorAgentsLive do
  @moduledoc """
  /admin/interactor/agents — registry + drift detection.

  Lists every FunSheep module implementing `FunSheep.Interactor.AssistantSpec`,
  compares the intended model (from code) to the live Interactor config, and
  surfaces "force re-provision" as an escape hatch for the common drift
  case.

  See the integration rule for Phase 3.1 of the admin buildout plan.
  """
  use FunSheepWeb, :live_view

  alias FunSheep.Admin
  alias FunSheep.Interactor.AgentRegistry

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Interactor agents · Admin")
     |> load_registry()}
  end

  @impl true
  def handle_event("reprovision", %{"module" => mod_str}, socket) do
    mod = String.to_existing_atom("Elixir.#{mod_str}")

    existing = Enum.find(socket.assigns.rows, &(&1.module == mod))

    case AgentRegistry.reprovision(mod) do
      {:ok, new_id} ->
        record_audit(socket, mod, existing, new_id)

        {:noreply,
         socket
         |> put_flash(:info, "#{short(mod)} re-provisioned.")
         |> load_registry()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Re-provision failed: #{inspect(reason)}")}
    end
  end

  def handle_event("refresh", _, socket), do: {:noreply, load_registry(socket)}

  defp record_audit(socket, mod, existing, new_id) do
    Admin.record(%{
      actor_user_role_id: get_in(socket.assigns, [:current_user, "user_role_id"]),
      actor_label: "admin:#{get_in(socket.assigns, [:current_user, "email"]) || "unknown"}",
      action: "admin.agent.reprovision",
      target_type: "interactor_assistant",
      target_id: new_id,
      metadata: %{
        "module" => Atom.to_string(mod),
        "old_live_model" => existing && existing.live_model,
        "old_live_id" => existing && existing.live_id,
        "new_intended_model" => existing && existing.intended_model
      }
    })
  end

  defp load_registry(socket) do
    rows = AgentRegistry.list()
    drift_count = Enum.count(rows, &(&1.status == :drift))

    socket
    |> assign(:rows, rows)
    |> assign(:drift_count, drift_count)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-6xl mx-auto">
      <div class="mb-6 flex items-center justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold text-[#1C1C1E]">Interactor agents</h1>
          <p class="text-[#8E8E93] text-sm mt-1">
            Compares each FunSheep AssistantSpec against its live Interactor
            counterpart. Drift = code says one model, Interactor console has
            another.
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

      <div
        :if={@drift_count > 0}
        class="bg-[#FFF4CC] text-[#1C1C1E] rounded-xl p-4 mb-4 text-sm"
      >
        ⚠ {@drift_count} agent{if @drift_count == 1, do: "", else: "s"} with config drift.
      </div>

      <div class="bg-white rounded-2xl shadow-md overflow-hidden">
        <div class="overflow-x-auto">
          <table class="w-full text-sm min-w-[720px]">
            <thead class="bg-[#F5F5F7] text-[#8E8E93] uppercase text-xs">
              <tr>
                <th class="text-left px-4 py-3">Assistant</th>
                <th class="text-left px-4 py-3">Intended model</th>
                <th class="text-left px-4 py-3">Live model</th>
                <th class="text-left px-4 py-3">Status</th>
                <th class="text-right px-4 py-3">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @rows} class="border-t border-[#F5F5F7]">
                <td class="px-4 py-3">
                  <div class="font-medium text-[#1C1C1E]">{row.name || "(unnamed)"}</div>
                  <div class="text-xs text-[#8E8E93]">
                    <code>{short(row.module)}</code>
                  </div>
                </td>
                <td class="px-4 py-3 text-[#1C1C1E]">{row.intended_model || "—"}</td>
                <td class="px-4 py-3 text-[#1C1C1E]">{row.live_model || "—"}</td>
                <td class="px-4 py-3"><.status_badge status={row.status} /></td>
                <td class="px-4 py-3 text-right">
                  <div class="inline-flex items-center gap-2">
                    <button
                      type="button"
                      phx-click="reprovision"
                      phx-value-module={short(row.module)}
                      data-confirm={"Delete and re-create #{row.name}? Its ID will change and any cached references will need to refresh."}
                      class="px-3 py-1 rounded-full text-xs font-medium text-[#FF3B30] border border-[#FF3B30]/30 hover:bg-[#FFE5E3]"
                    >
                      Force re-provision
                    </button>
                    <a
                      :if={row.live_id}
                      href={"https://console.interactor.com/agents/assistants/#{row.live_id}"}
                      target="_blank"
                      rel="noopener"
                      class="px-3 py-1 rounded-full text-xs font-medium text-[#1C1C1E] border border-[#E5E5EA] hover:bg-[#F5F5F7]"
                    >
                      Open in console
                    </a>
                    <.link
                      :if={row.name}
                      navigate={"/admin/usage/ai?assistant_name=#{URI.encode_www_form(row.name)}"}
                      class="px-3 py-1 rounded-full text-xs font-medium text-[#4CD964] border border-[#4CD964]/40 hover:bg-[#E8F8EB]"
                    >
                      24h calls
                    </.link>
                  </div>
                </td>
              </tr>
              <tr :if={@rows == []}>
                <td colspan="5" class="px-4 py-10 text-center text-[#8E8E93]">
                  No AssistantSpec modules registered.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp status_badge(%{status: status} = assigns) do
    {label, class} =
      case status do
        :in_sync -> {"In sync", "bg-[#E8F8EB] text-[#4CD964]"}
        :drift -> {"⚠ Drift", "bg-[#FFF4CC] text-[#1C1C1E]"}
        :missing -> {"Missing", "bg-[#FFE5E3] text-[#FF3B30]"}
        :unreachable -> {"Unreachable", "bg-[#F5F5F7] text-[#8E8E93]"}
      end

    assigns = assign(assigns, label: label, badge_class: class)

    ~H"""
    <span class={["inline-block px-2 py-0.5 rounded-full text-xs font-medium", @badge_class]}>
      {@label}
    </span>
    """
  end

  defp short(mod) when is_atom(mod) do
    mod |> Module.split() |> Enum.join(".")
  end
end
