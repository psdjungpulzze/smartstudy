defmodule FunSheepWeb.AdminInteractorCredentialsLive do
  @moduledoc """
  /admin/interactor/credentials — per-user OAuth troubleshooting.

  Support flow: admin searches for a user, sees their connected services,
  and can force-refresh or revoke a stuck credential.

  Every action is audit-logged.
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Accounts, Admin}
  alias FunSheep.Interactor.Credentials

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Interactor credentials · Admin")
     |> assign(:search, "")
     |> assign(:matches, [])
     |> assign(:selected, nil)
     |> assign(:credentials, [])
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("search", %{"search" => term}, socket) do
    matches =
      if String.length(term) < 2 do
        []
      else
        Accounts.list_users_for_admin(search: term, limit: 10, offset: 0)
      end

    {:noreply, socket |> assign(:search, term) |> assign(:matches, matches)}
  end

  def handle_event("select_user", %{"id" => user_id}, socket) do
    user = Accounts.get_user_role!(user_id)
    {:noreply, load_credentials(socket, user)}
  end

  def handle_event("refresh_credential", %{"id" => cred_id}, socket) do
    case Credentials.force_refresh(cred_id) do
      {:ok, _} ->
        audit(socket, "admin.credential.force_refresh", cred_id)

        {:noreply,
         socket
         |> put_flash(:info, "Credential refreshed.")
         |> load_credentials(socket.assigns.selected)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Refresh failed: #{inspect(reason)}")}
    end
  end

  def handle_event("revoke_credential", %{"id" => cred_id}, socket) do
    case Credentials.delete_credential(cred_id) do
      {:ok, _} ->
        audit(socket, "admin.credential.revoke", cred_id)

        {:noreply,
         socket
         |> put_flash(:info, "Credential revoked.")
         |> load_credentials(socket.assigns.selected)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Revoke failed: #{inspect(reason)}")}
    end
  end

  defp load_credentials(socket, user) do
    {creds, err} =
      case Credentials.list_credentials(user.interactor_user_id) do
        {:ok, %{"data" => items}} when is_list(items) -> {items, nil}
        {:ok, items} when is_list(items) -> {items, nil}
        _ -> {[], "Interactor service is unavailable or returned no data."}
      end

    socket
    |> assign(:selected, user)
    |> assign(:credentials, creds)
    |> assign(:error, err)
  end

  defp audit(socket, action, cred_id) do
    Admin.record(%{
      actor_user_role_id: get_in(socket.assigns, [:current_user, "user_role_id"]),
      actor_label: "admin:#{get_in(socket.assigns, [:current_user, "email"]) || "unknown"}",
      action: action,
      target_type: "interactor_credential",
      target_id: cred_id,
      metadata: %{
        "user_role_id" => socket.assigns.selected && socket.assigns.selected.id
      }
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-5xl mx-auto space-y-4">
      <div>
        <h1 class="text-2xl font-bold text-[#1C1C1E]">Interactor credentials</h1>
        <p class="text-[#8E8E93] text-sm mt-1">
          Troubleshoot per-user OAuth connections (Google, etc.). Force
          refresh or revoke stuck credentials. Every action is audited.
        </p>
      </div>

      <div class="bg-white rounded-2xl shadow-md p-4">
        <form phx-change="search" class="flex items-center gap-3">
          <input
            type="text"
            name="search"
            value={@search}
            placeholder="Search user by email or name…"
            phx-debounce="300"
            class="flex-1 px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none"
          />
        </form>
        <ul :if={@matches != []} class="mt-3 divide-y divide-[#F5F5F7] text-sm">
          <li
            :for={u <- @matches}
            class="py-2 cursor-pointer hover:bg-[#F5F5F7] px-2 rounded-xl"
            phx-click="select_user"
            phx-value-id={u.id}
          >
            <span class="font-medium text-[#1C1C1E]">{u.email}</span>
            <span class="text-[#8E8E93] ml-2">{u.display_name || "—"}</span>
          </li>
        </ul>
      </div>

      <div
        :if={@selected == nil}
        class="bg-white rounded-2xl shadow-md p-12 text-center text-[#8E8E93]"
      >
        Pick a user to view their connected services.
      </div>

      <div :if={@selected}>
        <div class="bg-white rounded-2xl shadow-md p-5 mb-4">
          <div class="font-semibold text-[#1C1C1E]">{@selected.email}</div>
          <div class="text-xs text-[#8E8E93]">
            Interactor user id: <code>{@selected.interactor_user_id}</code>
          </div>
        </div>

        <div :if={@error} class="bg-[#FFE5E3] text-[#FF3B30] rounded-xl p-4 text-sm mb-4">
          {@error}
        </div>

        <div class="bg-white rounded-2xl shadow-md overflow-hidden">
          <div class="overflow-x-auto">
            <table class="w-full text-sm min-w-[640px]">
              <thead class="bg-[#F5F5F7] text-[#8E8E93] uppercase text-xs">
                <tr>
                  <th class="text-left px-4 py-3">Provider</th>
                  <th class="text-left px-4 py-3">Status</th>
                  <th class="text-left px-4 py-3">Scopes</th>
                  <th class="text-left px-4 py-3">Expires</th>
                  <th class="text-right px-4 py-3">Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={c <- @credentials} class="border-t border-[#F5F5F7]">
                  <td class="px-4 py-3 font-medium text-[#1C1C1E]">{cred_provider(c)}</td>
                  <td class="px-4 py-3"><.cred_status_badge status={extract_status(c)} /></td>
                  <td class="px-4 py-3 text-[#8E8E93] truncate max-w-xs">
                    {cred_scopes(c)}
                  </td>
                  <td class="px-4 py-3 text-[#8E8E93]">{cred_expires(c)}</td>
                  <td class="px-4 py-3 text-right">
                    <div class="inline-flex items-center gap-2">
                      <button
                        type="button"
                        phx-click="refresh_credential"
                        phx-value-id={cred_id(c)}
                        class="px-3 py-1 rounded-full text-xs font-medium text-[#4CD964] border border-[#4CD964]/40 hover:bg-[#E8F8EB]"
                      >
                        Refresh
                      </button>
                      <button
                        type="button"
                        phx-click="revoke_credential"
                        phx-value-id={cred_id(c)}
                        data-confirm="Revoke this credential? The user will need to re-authorize the provider."
                        class="px-3 py-1 rounded-full text-xs font-medium text-[#FF3B30] border border-[#FF3B30]/30 hover:bg-[#FFE5E3]"
                      >
                        Revoke
                      </button>
                    </div>
                  </td>
                </tr>
                <tr :if={@credentials == []}>
                  <td colspan="5" class="px-4 py-10 text-center text-[#8E8E93]">
                    No credentials on file for this user.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp cred_status_badge(%{status: status} = assigns) do
    {label, class} =
      case status do
        :active -> {"Active", "bg-[#E8F8EB] text-[#4CD964]"}
        :expired -> {"Expired", "bg-[#FFF4CC] text-[#1C1C1E]"}
        :revoked -> {"Revoked", "bg-[#FFE5E3] text-[#FF3B30]"}
        _ -> {"Unknown", "bg-[#F5F5F7] text-[#8E8E93]"}
      end

    assigns = assign(assigns, label: label, badge_class: class)

    ~H"""
    <span class={["inline-block px-2 py-0.5 rounded-full text-xs font-medium", @badge_class]}>
      {@label}
    </span>
    """
  end

  defp cred_id(%{"id" => id}), do: id
  defp cred_id(%{id: id}), do: id
  defp cred_id(_), do: ""

  defp cred_provider(%{"provider" => p}), do: p
  defp cred_provider(%{"service" => s}), do: s
  defp cred_provider(_), do: "—"

  defp extract_status(%{"status" => "active"}), do: :active
  defp extract_status(%{"status" => "expired"}), do: :expired
  defp extract_status(%{"status" => "revoked"}), do: :revoked
  defp extract_status(_), do: :unknown

  defp cred_scopes(%{"scopes" => list}) when is_list(list), do: Enum.join(list, ", ")
  defp cred_scopes(%{"scope" => s}) when is_binary(s), do: s
  defp cred_scopes(_), do: "—"

  defp cred_expires(%{"expires_at" => nil}), do: "—"
  defp cred_expires(%{"expires_at" => dt}) when is_binary(dt), do: dt
  defp cred_expires(_), do: "—"
end
