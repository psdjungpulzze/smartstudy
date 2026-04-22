defmodule FunSheepWeb.AdminFlagsLive do
  @moduledoc """
  /admin/flags — toggle well-known FunSheep feature flags / kill switches.

  Every toggle is audit-logged. Changes propagate cluster-wide in < 1s
  via Phoenix.PubSub (see fun_with_flags config).
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Admin, FeatureFlags}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Feature flags · Admin")
     |> assign(:flags, FeatureFlags.list())}
  end

  @impl true
  def handle_event("toggle", %{"name" => name_str}, socket) do
    name = String.to_existing_atom(name_str)
    before = FeatureFlags.enabled?(name)

    case FeatureFlags.toggle(name) do
      {:ok, now_enabled} ->
        record_audit(socket, name, before, now_enabled)

        {:noreply,
         socket
         |> put_flash(:info, "Flag #{name}: #{if now_enabled, do: "ON", else: "OFF"}")
         |> assign(:flags, FeatureFlags.list())}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to toggle: #{inspect(reason)}")}
    end
  end

  defp record_audit(socket, name, before, now_enabled) do
    Admin.record(%{
      actor_user_role_id: get_in(socket.assigns, [:current_user, "user_role_id"]),
      actor_label: "admin:#{get_in(socket.assigns, [:current_user, "email"]) || "unknown"}",
      action: "admin.flag.toggle",
      target_type: "feature_flag",
      target_id: Atom.to_string(name),
      metadata: %{"from" => before, "to" => now_enabled}
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-4xl mx-auto">
      <div class="mb-6">
        <h1 class="text-2xl font-bold text-[#1C1C1E]">Feature flags</h1>
        <p class="text-[#8E8E93] text-sm mt-1">
          Kill switches for background work and user-facing gates. Toggling
          a flag propagates cluster-wide in under a second.
        </p>
      </div>

      <div class="bg-white rounded-2xl shadow-md overflow-hidden">
        <ul class="divide-y divide-[#F5F5F7]">
          <li
            :for={flag <- @flags}
            class="px-6 py-4 flex items-start justify-between gap-4"
          >
            <div class="min-w-0">
              <div class="flex items-center gap-2">
                <code class="text-[#1C1C1E] font-medium">{flag.name}</code>
                <span class={[
                  "inline-block px-2 py-0.5 rounded-full text-xs font-medium",
                  status_class(flag.enabled?)
                ]}>
                  {if flag.enabled?, do: "ON", else: "OFF"}
                </span>
              </div>
              <p class="text-sm text-[#8E8E93] mt-1">{flag.description}</p>
            </div>
            <button
              type="button"
              phx-click="toggle"
              phx-value-name={Atom.to_string(flag.name)}
              data-confirm={
                if(flag.enabled?,
                  do: "Turn #{flag.name} OFF? Background work may stop.",
                  else: "Turn #{flag.name} ON?"
                )
              }
              class={toggle_button_class(flag.enabled?)}
            >
              {if flag.enabled?, do: "Disable", else: "Enable"}
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp status_class(true), do: "bg-[#E8F8EB] text-[#4CD964]"
  defp status_class(false), do: "bg-[#FFE5E3] text-[#FF3B30]"

  defp toggle_button_class(true) do
    "px-4 py-1.5 rounded-full text-sm font-medium text-[#FF3B30] border border-[#FF3B30]/40 hover:bg-[#FFE5E3]"
  end

  defp toggle_button_class(false) do
    "px-4 py-1.5 rounded-full text-sm font-medium text-white bg-[#4CD964] hover:bg-[#3DBF55]"
  end
end
