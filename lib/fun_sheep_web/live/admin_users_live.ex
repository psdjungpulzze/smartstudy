defmodule FunSheepWeb.AdminUsersLive do
  @moduledoc """
  Admin user management: list, search, filter by role, and per-row
  promote / demote / suspend / unsuspend actions.
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Accounts, Admin, Billing}
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
     |> assign(:editing_subscription, nil)
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

  def handle_event("open_subscription", %{"id" => id}, socket) do
    target = Accounts.get_user_role!(id)
    {:ok, sub} = Billing.get_or_create_subscription(target.id)
    stats = Billing.usage_stats(target.id)

    editing = %{
      user_id: target.id,
      email: target.email,
      current_plan: sub.plan,
      bonus: sub.bonus_free_tests || 0,
      used: stats.total_tests,
      limit: stats.initial_limit
    }

    {:noreply, assign(socket, :editing_subscription, editing)}
  end

  def handle_event("close_subscription", _, socket) do
    {:noreply, assign(socket, :editing_subscription, nil)}
  end

  def handle_event("preview_subscription", %{"plan" => plan}, socket) do
    if plan in ["free", "monthly", "annual"] do
      updated = %{socket.assigns.editing_subscription | current_plan: plan}
      {:noreply, assign(socket, :editing_subscription, updated)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("preview_subscription", _params, socket), do: {:noreply, socket}

  def handle_event("save_subscription", params, socket) do
    editing = socket.assigns.editing_subscription
    target = Accounts.get_user_role!(editing.user_id)
    actor = socket.assigns.current_user
    plan = Map.get(params, "plan", editing.current_plan)
    raw_bonus = Map.get(params, "bonus", "#{editing.bonus}")

    with {:ok, bonus} <- parse_bonus(raw_bonus),
         {:ok, _} <- maybe_override_plan(target, plan, editing.current_plan, actor),
         {:ok, _} <- maybe_update_bonus(target, bonus, editing.bonus, actor) do
      {:noreply,
       socket
       |> put_flash(:info, "Subscription updated for #{target.email}.")
       |> assign(:editing_subscription, nil)
       |> load_users()}
    else
      :error ->
        {:noreply, put_flash(socket, :error, "Bonus must be a non-negative whole number.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update subscription.")}
    end
  end

  def handle_event("reset_usage", _, socket) do
    editing = socket.assigns.editing_subscription
    target = Accounts.get_user_role!(editing.user_id)

    case Admin.reset_test_usage(target, socket.assigns.current_user) do
      {:ok, count} ->
        stats = Billing.usage_stats(target.id)
        {:ok, sub} = Billing.get_or_create_subscription(target.id)

        updated = %{
          editing
          | used: stats.total_tests,
            limit: stats.initial_limit,
            bonus: sub.bonus_free_tests || 0
        }

        {:noreply,
         socket
         |> put_flash(:info, "Reset #{count} test records for #{target.email}.")
         |> assign(:editing_subscription, updated)
         |> load_users()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to reset usage.")}
    end
  end

  defp maybe_override_plan(_target, plan, plan, _actor), do: {:ok, :unchanged}

  defp maybe_override_plan(target, plan, _old_plan, actor)
       when plan in ["free", "monthly", "annual"] do
    Admin.override_subscription_plan(target, plan, actor)
  end

  defp maybe_override_plan(_target, _plan, _old_plan, _actor), do: {:error, :invalid_plan}

  defp maybe_update_bonus(_target, bonus, bonus, _actor), do: {:ok, :unchanged}

  defp maybe_update_bonus(target, bonus, _old_bonus, actor) do
    Admin.set_bonus_free_tests(target, bonus, actor)
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

      <div class="bg-white rounded-2xl shadow-md overflow-x-auto">
        <table class="w-full text-sm min-w-[700px]">
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
                    :if={u.role == :student}
                    type="button"
                    phx-click="open_subscription"
                    phx-value-id={u.id}
                    title="Edit subscription plan and free lessons"
                    class="px-3 py-1 rounded-full text-xs font-medium text-[#1C1C1E] border border-[#4CD964]/40 hover:bg-[#E8F8EB]"
                  >
                    Subscription
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

      <.subscription_modal :if={@editing_subscription} editing={@editing_subscription} />

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

  defp subscription_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      phx-click="close_subscription"
    >
      <div
        class="bg-white rounded-2xl shadow-xl p-6 w-full max-w-md mx-4"
        phx-click-away="close_subscription"
        phx-window-keydown="close_subscription"
        phx-key="escape"
        onclick="event.stopPropagation()"
      >
        <div class="flex items-start justify-between mb-4">
          <div>
            <h2 class="text-lg font-bold text-[#1C1C1E]">Edit Subscription</h2>
            <p class="text-xs text-[#8E8E93] mt-0.5">{@editing.email}</p>
          </div>
          <button
            type="button"
            phx-click="close_subscription"
            aria-label="Close"
            class="text-[#8E8E93] hover:text-[#1C1C1E] text-xl leading-none"
          >
            ×
          </button>
        </div>

        <div class="bg-[#F5F5F7] rounded-xl p-3 text-sm text-[#1C1C1E] mb-4">
          Used <span class="font-semibold">{@editing.used}</span>
          of <span class="font-semibold">{@editing.limit}</span>
          lifetime free lessons <span class="text-[#8E8E93]">(50 base + {@editing.bonus} bonus)</span>
        </div>

        <.form
          for={%{}}
          phx-submit="save_subscription"
          phx-change="preview_subscription"
          class="space-y-4"
        >
          <div>
            <label class="block text-sm font-medium text-[#1C1C1E] mb-2">Plan</label>
            <div class="flex gap-2">
              <label
                :for={plan <- [{"Free", "free"}, {"Monthly", "monthly"}, {"Annual", "annual"}]}
                class={[
                  "flex-1 flex items-center justify-center gap-1.5 px-3 py-2 rounded-full text-xs font-medium border cursor-pointer transition-colors",
                  if(elem(plan, 1) == @editing.current_plan,
                    do: "bg-[#4CD964] text-white border-[#4CD964]",
                    else: "bg-white text-[#1C1C1E] border-[#E5E5EA] hover:border-[#4CD964]/40"
                  )
                ]}
              >
                <input
                  type="radio"
                  name="plan"
                  value={elem(plan, 1)}
                  checked={elem(plan, 1) == @editing.current_plan}
                  class="sr-only"
                />
                {elem(plan, 0)}
              </label>
            </div>
            <p class="text-xs text-[#8E8E93] mt-1">
              Monthly/Annual marks the student as paid — no Stripe billing attached.
            </p>
          </div>

          <div :if={@editing.current_plan == "free"}>
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
            />
            <p class="text-xs text-[#8E8E93] mt-1">
              Granted on top of the 50-lesson base. Set to 0 to revoke.
            </p>
          </div>

          <div :if={@editing.current_plan == "free"} class="border-t border-[#E5E5EA] pt-4">
            <p class="text-xs text-[#8E8E93] mb-2">
              Reset usage gives this student a fresh start (deletes all test records).
            </p>
            <button
              type="button"
              phx-click="reset_usage"
              data-confirm={"Reset all test usage for #{@editing.email}? This deletes #{@editing.used} test records and cannot be undone."}
              class="w-full px-4 py-2 rounded-full text-sm font-medium text-[#FF3B30] border border-[#FF3B30]/30 hover:bg-[#FFE5E3] transition-colors"
            >
              Reset usage ({@editing.used} tests)
            </button>
          </div>

          <div class="flex items-center justify-end gap-2">
            <button
              type="button"
              phx-click="close_subscription"
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
