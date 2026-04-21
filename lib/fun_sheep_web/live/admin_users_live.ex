defmodule FunSheepWeb.AdminUsersLive do
  @moduledoc """
  Admin user management: list, search, filter by role, and per-row
  promote / demote / suspend / unsuspend actions.
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Accounts, Admin}
  alias FunSheep.Accounts.UserRole

  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Users · Admin")
     |> assign(:search, "")
     |> assign(:role_filter, nil)
     |> assign(:page, 0)
     |> load_users()}
  end

  @impl true
  def handle_event("search", %{"search" => term}, socket) do
    {:noreply,
     socket
     |> assign(:search, term)
     |> assign(:page, 0)
     |> load_users()}
  end

  def handle_event("filter_role", %{"role" => role}, socket) do
    role = if role in ~w(student parent teacher admin), do: role, else: nil

    {:noreply,
     socket
     |> assign(:role_filter, role)
     |> assign(:page, 0)
     |> load_users()}
  end

  def handle_event("prev_page", _, socket) do
    {:noreply,
     socket
     |> assign(:page, max(socket.assigns.page - 1, 0))
     |> load_users()}
  end

  def handle_event("next_page", _, socket) do
    next = socket.assigns.page + 1

    if next * @page_size >= socket.assigns.total do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:page, next)
       |> load_users()}
    end
  end

  def handle_event("suspend", %{"id" => id}, socket) do
    target = Accounts.get_user_role!(id)

    case Admin.suspend_user(target, socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "User suspended.") |> load_users()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to suspend user.")}
    end
  end

  def handle_event("unsuspend", %{"id" => id}, socket) do
    target = Accounts.get_user_role!(id)

    case Admin.unsuspend_user(target, socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "User reinstated.") |> load_users()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to reinstate user.")}
    end
  end

  def handle_event("promote", %{"id" => id}, socket) do
    target = Accounts.get_user_role!(id)

    case Admin.promote_to_admin(target, socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Promoted to admin. (Run `mix funsheep.admin.grant` if you also need the Interactor-side metadata.role claim.)")
         |> load_users()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to promote user.")}
    end
  end

  def handle_event("demote", %{"id" => id}, socket) do
    target = Accounts.get_user_role!(id)

    case Admin.demote_admin(target, socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Admin role removed.") |> load_users()}

      {:error, :not_admin} ->
        {:noreply, put_flash(socket, :error, "Row is not an admin role.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to demote.")}
    end
  end

  defp load_users(socket) do
    opts = [
      search: socket.assigns.search,
      role: socket.assigns.role_filter,
      limit: @page_size,
      offset: socket.assigns.page * @page_size
    ]

    users = Accounts.list_users_for_admin(opts)
    total = Accounts.count_users_for_admin(Keyword.take(opts, [:search, :role]))

    socket
    |> assign(:users, users)
    |> assign(:total, total)
    |> assign(:page_size, @page_size)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-[#1C1C1E]">Users</h1>
        <div class="text-sm text-[#8E8E93]">{@total} total</div>
      </div>

      <div class="bg-white rounded-2xl shadow-md p-4 mb-4">
        <form phx-change="search" class="flex items-center gap-3">
          <input
            type="text"
            name="search"
            value={@search}
            placeholder="Search by email or name…"
            phx-debounce="300"
            class="flex-1 px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] focus:bg-white rounded-full outline-none transition-colors"
          />
        </form>

        <div class="mt-3 flex items-center gap-2 flex-wrap">
          <button
            type="button"
            phx-click="filter_role"
            phx-value-role=""
            class={role_pill_class(is_nil(@role_filter))}
          >
            All
          </button>
          <button
            :for={r <- ~w(student parent teacher admin)}
            type="button"
            phx-click="filter_role"
            phx-value-role={r}
            class={role_pill_class(@role_filter == r)}
          >
            {String.capitalize(r)}
          </button>
        </div>
      </div>

      <div class="bg-white rounded-2xl shadow-md overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-[#F5F5F7] text-[#8E8E93] uppercase text-xs">
            <tr>
              <th class="text-left px-4 py-3">Email</th>
              <th class="text-left px-4 py-3">Name</th>
              <th class="text-left px-4 py-3">Role</th>
              <th class="text-left px-4 py-3">Status</th>
              <th class="text-left px-4 py-3">Joined</th>
              <th class="text-right px-4 py-3">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={u <- @users} class="border-t border-[#F5F5F7]">
              <td class="px-4 py-3 font-medium text-[#1C1C1E]">{u.email}</td>
              <td class="px-4 py-3 text-[#1C1C1E]">{u.display_name || "—"}</td>
              <td class="px-4 py-3"><.role_badge role={u.role} /></td>
              <td class="px-4 py-3">
                <span
                  :if={UserRole.suspended?(u)}
                  class="inline-block px-2 py-0.5 rounded-full bg-[#FFE5E3] text-[#FF3B30] text-xs font-medium"
                >
                  Suspended
                </span>
                <span :if={not UserRole.suspended?(u)} class="text-[#4CD964] text-xs font-medium">
                  Active
                </span>
              </td>
              <td class="px-4 py-3 text-[#8E8E93]">
                {Calendar.strftime(u.inserted_at, "%Y-%m-%d")}
              </td>
              <td class="px-4 py-3 text-right">
                <div class="inline-flex items-center gap-2">
                  <button
                    :if={not UserRole.suspended?(u)}
                    type="button"
                    phx-click="suspend"
                    phx-value-id={u.id}
                    data-confirm="Suspend this user? They will be logged out on next page load."
                    class="px-3 py-1 rounded-full text-xs font-medium text-[#FF3B30] border border-[#FF3B30]/30 hover:bg-[#FFE5E3]"
                  >
                    Suspend
                  </button>
                  <button
                    :if={UserRole.suspended?(u)}
                    type="button"
                    phx-click="unsuspend"
                    phx-value-id={u.id}
                    class="px-3 py-1 rounded-full text-xs font-medium text-[#4CD964] border border-[#4CD964]/30 hover:bg-[#E8F8EB]"
                  >
                    Reinstate
                  </button>
                  <button
                    :if={u.role != :admin}
                    type="button"
                    phx-click="promote"
                    phx-value-id={u.id}
                    data-confirm="Promote to admin? Remember to also set metadata.role in Interactor for full access."
                    class="px-3 py-1 rounded-full text-xs font-medium text-[#1C1C1E] border border-[#E5E5EA] hover:bg-[#F5F5F7]"
                  >
                    Promote
                  </button>
                  <button
                    :if={u.role == :admin}
                    type="button"
                    phx-click="demote"
                    phx-value-id={u.id}
                    data-confirm="Remove admin role from this user?"
                    class="px-3 py-1 rounded-full text-xs font-medium text-[#1C1C1E] border border-[#E5E5EA] hover:bg-[#F5F5F7]"
                  >
                    Demote
                  </button>
                  <.form
                    :if={u.role != :admin and not UserRole.suspended?(u)}
                    for={%{}}
                    action={~p"/admin/impersonate/#{u.id}"}
                    method="post"
                    class="inline"
                  >
                    <button
                      type="submit"
                      data-confirm={"Impersonate #{u.email}? A red banner will show across every page and every action is audited."}
                      class="px-3 py-1 rounded-full text-xs font-medium text-white bg-[#1C1C1E] hover:bg-[#2C2C2E]"
                    >
                      Impersonate
                    </button>
                  </.form>
                </div>
              </td>
            </tr>
            <tr :if={@users == []}>
              <td colspan="6" class="px-4 py-10 text-center text-[#8E8E93]">No users match.</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="mt-4 flex items-center justify-between text-sm text-[#8E8E93]">
        <div>
          Page {@page + 1} of {max(div(@total - 1, @page_size) + 1, 1)}
        </div>
        <div class="flex gap-2">
          <button
            type="button"
            phx-click="prev_page"
            disabled={@page == 0}
            class="px-4 py-2 rounded-full border border-[#E5E5EA] bg-white disabled:opacity-40"
          >
            Prev
          </button>
          <button
            type="button"
            phx-click="next_page"
            disabled={(@page + 1) * @page_size >= @total}
            class="px-4 py-2 rounded-full border border-[#E5E5EA] bg-white disabled:opacity-40"
          >
            Next
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp role_pill_class(active?) do
    base = "px-3 py-1 rounded-full text-xs font-medium border transition-colors"

    if active? do
      "#{base} bg-[#4CD964] text-white border-[#4CD964]"
    else
      "#{base} bg-white text-[#1C1C1E] border-[#E5E5EA] hover:border-[#4CD964]/40"
    end
  end

  attr :role, :atom, required: true

  defp role_badge(%{role: role} = assigns) do
    {label, class} =
      case role do
        :admin -> {"Admin", "bg-[#1C1C1E] text-white"}
        :teacher -> {"Teacher", "bg-[#E8F8EB] text-[#1C1C1E]"}
        :parent -> {"Parent", "bg-[#FFF4CC] text-[#1C1C1E]"}
        _ -> {"Student", "bg-[#F5F5F7] text-[#1C1C1E]"}
      end

    assigns = assign(assigns, label: label, badge_class: class)

    ~H"""
    <span class={["inline-block px-2 py-0.5 rounded-full text-xs font-medium", @badge_class]}>
      {@label}
    </span>
    """
  end
end
