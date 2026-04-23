defmodule FunSheepWeb.AdminUsersLive do
  @moduledoc """
  Admin user management: list, search, filter by role, and per-row
  promote / demote / suspend / unsuspend actions.
  """
  use FunSheepWeb, :live_view

  import Ecto.Query, only: [from: 2]

  alias FunSheep.{Accounts, Admin, Billing, Repo}
  alias FunSheep.Accounts.UserRole
  alias FunSheep.Billing.Subscription

  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Users · Admin")
     |> assign(:search, "")
     |> assign(:role_filter, nil)
     |> assign(:page, 0)
     |> assign(:editing_bonus, nil)
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
         |> put_flash(
           :info,
           "Promoted to admin. (Run `mix funsheep.admin.grant` if you also need the Interactor-side metadata.role claim.)"
         )
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

  def handle_event("open_bonus", %{"id" => id}, socket) do
    target = Accounts.get_user_role!(id)
    {:ok, sub} = Billing.get_or_create_subscription(target.id)
    stats = Billing.usage_stats(target.id)

    editing = %{
      user_id: target.id,
      email: target.email,
      bonus: sub.bonus_free_tests || 0,
      used: stats.total_tests,
      limit: stats.initial_limit
    }

    {:noreply, assign(socket, :editing_bonus, editing)}
  end

  def handle_event("close_bonus", _, socket) do
    {:noreply, assign(socket, :editing_bonus, nil)}
  end

  def handle_event("save_bonus", %{"bonus" => raw}, socket) do
    case parse_bonus(raw) do
      {:ok, bonus} ->
        target = Accounts.get_user_role!(socket.assigns.editing_bonus.user_id)

        case Admin.set_bonus_free_tests(target, bonus, socket.assigns.current_user) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Free lessons updated for #{target.email}.")
             |> assign(:editing_bonus, nil)
             |> load_users()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update free lessons.")}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Bonus must be a non-negative whole number.")}
    end
  end

  defp parse_bonus(raw) when is_binary(raw) do
    case Integer.parse(String.trim(raw)) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_bonus(_), do: :error

  defp load_users(socket) do
    opts = [
      search: socket.assigns.search,
      role: socket.assigns.role_filter,
      limit: @page_size,
      offset: socket.assigns.page * @page_size
    ]

    users = Accounts.list_users_for_admin(opts)
    total = Accounts.count_users_for_admin(Keyword.take(opts, [:search, :role]))
    subs_by_user = subscriptions_for(users)

    socket
    |> assign(:users, users)
    |> assign(:subs_by_user, subs_by_user)
    |> assign(:total, total)
    |> assign(:page_size, @page_size)
  end

  defp subscriptions_for([]), do: %{}

  defp subscriptions_for(users) do
    student_ids =
      users
      |> Enum.filter(&(&1.role == :student))
      |> Enum.map(& &1.id)

    case student_ids do
      [] ->
        %{}

      ids ->
        from(s in Subscription, where: s.user_role_id in ^ids)
        |> Repo.all()
        |> Map.new(&{&1.user_role_id, &1})
    end
  end

  defp on_free_plan?(%UserRole{role: :student} = u, subs_by_user) do
    case Map.get(subs_by_user, u.id) do
      nil -> true
      %Subscription{plan: "free"} -> true
      _ -> false
    end
  end

  defp on_free_plan?(_user, _subs), do: false

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
              <td class="px-4 py-3 font-medium text-[#1C1C1E]">
                <.link navigate={~p"/admin/users/#{u.id}"} class="hover:text-[#4CD964]">
                  {u.email}
                </.link>
              </td>
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
                    :if={on_free_plan?(u, @subs_by_user)}
                    type="button"
                    phx-click="open_bonus"
                    phx-value-id={u.id}
                    title="Grant or reset bonus free lessons"
                    class="px-3 py-1 rounded-full text-xs font-medium text-[#1C1C1E] border border-[#4CD964]/40 hover:bg-[#E8F8EB]"
                  >
                    Free lessons
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

      <.bonus_modal :if={@editing_bonus} editing={@editing_bonus} />

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

  attr :editing, :map, required: true

  defp bonus_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      phx-click="close_bonus"
    >
      <div
        class="bg-white rounded-2xl shadow-xl p-6 w-full max-w-md mx-4"
        phx-click-away="close_bonus"
        phx-window-keydown="close_bonus"
        phx-key="escape"
        onclick="event.stopPropagation()"
      >
        <div class="flex items-start justify-between mb-4">
          <div>
            <h2 class="text-lg font-bold text-[#1C1C1E]">Free lessons</h2>
            <p class="text-xs text-[#8E8E93] mt-0.5">{@editing.email}</p>
          </div>
          <button
            type="button"
            phx-click="close_bonus"
            aria-label="Close"
            class="text-[#8E8E93] hover:text-[#1C1C1E] text-xl leading-none"
          >
            ×
          </button>
        </div>

        <div class="bg-[#F5F5F7] rounded-xl p-3 text-sm text-[#1C1C1E] mb-4">
          Used <span class="font-semibold">{@editing.used}</span>
          of <span class="font-semibold">{@editing.limit}</span>
          lifetime free lessons
          <span class="text-[#8E8E93]">
            (50 base + {@editing.bonus} bonus)
          </span>
        </div>

        <.form for={%{}} phx-submit="save_bonus" class="space-y-4">
          <div>
            <label for="bonus" class="block text-sm font-medium text-[#1C1C1E] mb-1">
              Bonus free lessons
            </label>
            <input
              id="bonus"
              type="number"
              name="bonus"
              min="0"
              step="1"
              value={@editing.bonus}
              class="w-full px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] focus:bg-white rounded-lg outline-none transition-colors"
              autofocus
            />
            <p class="text-xs text-[#8E8E93] mt-1">
              Granted on top of the 50-lesson base. Set to 0 to revoke.
            </p>
          </div>

          <div class="flex items-center justify-end gap-2">
            <button
              type="button"
              phx-click="close_bonus"
              class="px-4 py-2 rounded-full text-sm font-medium text-[#1C1C1E] border border-[#E5E5EA] hover:bg-[#F5F5F7]"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="px-4 py-2 rounded-full text-sm font-medium text-white bg-[#4CD964] hover:bg-[#3DBF55] shadow-md"
            >
              Save
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
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
