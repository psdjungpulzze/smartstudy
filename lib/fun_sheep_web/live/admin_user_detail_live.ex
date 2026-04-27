defmodule FunSheepWeb.AdminUserDetailLive do
  @moduledoc """
  /admin/users/:id — everything about one user on a single page, so an admin
  doesn't need to impersonate them to triage. Always renders every section
  (graceful empty states) so a brand-new user doesn't crash the view.

  Writes `admin.user.view` to the audit log on mount because the surface
  exposes per-user PII (email, activity, AI token attribution).
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Accounts, Admin}
  alias FunSheep.Accounts.UserRole
  alias FunSheep.Admin.UserDetail

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Accounts.get_user_role(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "User not found.")
         |> push_navigate(to: ~p"/admin/users")}

      %UserRole{} = user ->
        UserDetail.record_view(user, socket.assigns.current_user)

        {:ok,
         socket
         |> assign(:page_title, "#{user.email} · Admin")
         |> assign(:aggregate, UserDetail.load(id))}
    end
  end

  @impl true
  def handle_event("suspend", _, socket) do
    case Admin.suspend_user(socket.assigns.aggregate.user, socket.assigns.current_user) do
      {:ok, _} -> refresh(socket, "User suspended.")
      _ -> {:noreply, put_flash(socket, :error, "Failed to suspend user.")}
    end
  end

  def handle_event("unsuspend", _, socket) do
    case Admin.unsuspend_user(socket.assigns.aggregate.user, socket.assigns.current_user) do
      {:ok, _} -> refresh(socket, "User reinstated.")
      _ -> {:noreply, put_flash(socket, :error, "Failed to reinstate user.")}
    end
  end

  def handle_event("promote", _, socket) do
    case Admin.promote_to_admin(socket.assigns.aggregate.user, socket.assigns.current_user) do
      {:ok, _} -> refresh(socket, "Promoted to admin.")
      _ -> {:noreply, put_flash(socket, :error, "Failed to promote.")}
    end
  end

  def handle_event("demote", _, socket) do
    case Admin.demote_admin(socket.assigns.aggregate.user, socket.assigns.current_user) do
      {:ok, _} ->
        # demote_admin deletes the admin UserRole row; the detail page for this
        # row can no longer render, so bounce back to the list.
        {:noreply,
         socket
         |> put_flash(:info, "Admin role removed.")
         |> push_navigate(to: ~p"/admin/users")}

      {:error, :not_admin} ->
        {:noreply, put_flash(socket, :error, "User is not an admin.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to demote.")}
    end
  end

  defp refresh(socket, msg) do
    user_id = socket.assigns.aggregate.user.id

    {:noreply,
     socket
     |> put_flash(:info, msg)
     |> assign(:aggregate, UserDetail.load(user_id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto space-y-6">
      <.back_link />

      <.header_card user={@aggregate.user} />

      <.quick_actions user={@aggregate.user} />

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <.activity_timeline entries={@aggregate.activity_timeline} />
        <.audit_trail_section entries={@aggregate.audit_trail} />
      </div>

      <.courses_section courses={@aggregate.courses_owned} />

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <.ai_usage_section usage={@aggregate.ai_usage} />
        <.subscription_section data={@aggregate.subscription} />
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <.interactor_profile_section data={@aggregate.interactor_profile} />
        <.credentials_section data={@aggregate.credentials} />
      </div>
    </div>
    """
  end

  ## --- Components ------------------------------------------------------

  defp back_link(assigns) do
    ~H"""
    <.link navigate={~p"/admin/users"} class="text-sm text-[#4CD964] font-medium">
      ← All users
    </.link>
    """
  end

  attr :user, :map, required: true

  defp header_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-6">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h1 class="text-2xl font-bold text-[#1C1C1E] truncate">
            {@user.display_name || @user.email}
          </h1>
          <p class="text-[#8E8E93] text-sm mt-1 truncate">{@user.email}</p>
          <div class="flex items-center gap-2 mt-3 flex-wrap">
            <span class={[
              "inline-block px-2 py-0.5 rounded-full text-xs font-medium",
              role_badge_class(@user.role)
            ]}>
              {String.capitalize(Atom.to_string(@user.role))}
            </span>
            <span
              :if={UserRole.suspended?(@user)}
              class="inline-block px-2 py-0.5 rounded-full bg-[#FFE5E3] text-[#FF3B30] text-xs font-medium"
            >
              Suspended
            </span>
            <span
              :if={not UserRole.suspended?(@user)}
              class="inline-block px-2 py-0.5 rounded-full bg-[#E8F8EB] text-[#4CD964] text-xs font-medium"
            >
              Active
            </span>
          </div>
        </div>
        <dl class="text-xs text-[#8E8E93] text-right shrink-0 space-y-1">
          <div>
            <dt class="inline">Joined:</dt>
            <dd class="inline ml-1 text-[#1C1C1E]">
              {Calendar.strftime(@user.inserted_at, "%Y-%m-%d")}
            </dd>
          </div>
          <div>
            <dt class="inline">Last login:</dt>
            <dd class="inline ml-1 text-[#1C1C1E]">
              {format_last_login(@user.last_login_at)}
            </dd>
          </div>
        </dl>
      </div>
    </div>
    """
  end

  attr :user, :map, required: true

  defp quick_actions(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-4">
      <div class="flex items-center gap-2 flex-wrap">
        <button
          :if={not UserRole.suspended?(@user)}
          type="button"
          phx-click="suspend"
          data-confirm="Suspend this user?"
          class="px-4 py-1.5 rounded-full text-sm font-medium text-[#FF3B30] border border-[#FF3B30]/30 hover:bg-[#FFE5E3]"
        >
          Suspend
        </button>
        <button
          :if={UserRole.suspended?(@user)}
          type="button"
          phx-click="unsuspend"
          class="px-4 py-1.5 rounded-full text-sm font-medium text-[#4CD964] border border-[#4CD964]/30 hover:bg-[#E8F8EB]"
        >
          Reinstate
        </button>
        <button
          :if={@user.role != :admin}
          type="button"
          phx-click="promote"
          data-confirm="Promote to admin?"
          class="px-4 py-1.5 rounded-full text-sm font-medium text-[#1C1C1E] border border-[#E5E5EA] hover:bg-[#F5F5F7]"
        >
          Promote
        </button>
        <button
          :if={@user.role == :admin}
          type="button"
          phx-click="demote"
          data-confirm="Remove admin role?"
          class="px-4 py-1.5 rounded-full text-sm font-medium text-[#1C1C1E] border border-[#E5E5EA] hover:bg-[#F5F5F7]"
        >
          Demote
        </button>
        <.form
          :if={@user.role != :admin and not UserRole.suspended?(@user)}
          for={%{}}
          action={~p"/admin/impersonate/#{@user.id}"}
          method="post"
          class="inline"
        >
          <button
            type="submit"
            data-confirm="Impersonate #{@user.email}? Every action will be audited."
            class="px-4 py-1.5 rounded-full text-sm font-medium text-white bg-[#1C1C1E] hover:bg-[#2C2C2E]"
          >
            Impersonate
          </button>
        </.form>
      </div>
    </div>
    """
  end

  attr :entries, :list, required: true

  defp activity_timeline(assigns) do
    ~H"""
    <section class="bg-white rounded-2xl shadow-md p-6">
      <h2 class="font-semibold text-[#1C1C1E] mb-3">Activity timeline</h2>
      <ul :if={@entries != []} class="divide-y divide-[#F5F5F7] text-sm">
        <li :for={e <- @entries} class="py-2 flex items-start justify-between gap-3">
          <div class="min-w-0">
            <span class="text-xs mr-2">{activity_icon(e.kind)}</span>
            <span class="text-[#1C1C1E]">{e.summary}</span>
          </div>
          <span class="text-xs text-[#8E8E93] whitespace-nowrap">
            {Calendar.strftime(e.at, "%Y-%m-%d %H:%M")}
          </span>
        </li>
      </ul>
      <p :if={@entries == []} class="text-sm text-[#8E8E93] py-4 text-center">
        No activity yet.
      </p>
    </section>
    """
  end

  attr :entries, :list, required: true

  defp audit_trail_section(assigns) do
    ~H"""
    <section class="bg-white rounded-2xl shadow-md p-6">
      <div class="flex items-center justify-between mb-3">
        <h2 class="font-semibold text-[#1C1C1E]">Audit trail</h2>
        <.link navigate={~p"/admin/audit-log"} class="text-xs text-[#4CD964] font-medium">
          Full log →
        </.link>
      </div>
      <ul :if={@entries != []} class="divide-y divide-[#F5F5F7] text-sm">
        <li :for={log <- @entries} class="py-2 flex items-start justify-between gap-3">
          <div class="min-w-0">
            <code class="text-xs text-[#1C1C1E]">{log.action}</code>
            <div class="text-xs text-[#8E8E93] truncate">{log.actor_label}</div>
          </div>
          <span class="text-xs text-[#8E8E93] whitespace-nowrap">
            {Calendar.strftime(log.inserted_at, "%Y-%m-%d")}
          </span>
        </li>
      </ul>
      <p :if={@entries == []} class="text-sm text-[#8E8E93] py-4 text-center">
        No admin actions on record for this user.
      </p>
    </section>
    """
  end

  attr :courses, :list, required: true

  defp courses_section(assigns) do
    ~H"""
    <section class="bg-white rounded-2xl shadow-md overflow-hidden">
      <h2 class="font-semibold text-[#1C1C1E] px-6 py-4">Courses owned</h2>
      <div class="overflow-x-auto">
        <table class="w-full text-sm min-w-[600px]">
          <thead class="bg-[#F5F5F7] text-[#8E8E93] uppercase text-xs">
            <tr>
              <th class="text-left px-4 py-3">Name</th>
              <th class="text-left px-4 py-3">Subject · Grade</th>
              <th class="text-left px-4 py-3">Status</th>
              <th class="text-left px-4 py-3">Created</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={c <- @courses} class="border-t border-[#F5F5F7]">
              <td class="px-4 py-3 font-medium text-[#1C1C1E]">
                <.link navigate={~p"/admin/courses"} class="hover:text-[#4CD964]">
                  {c.name || "(no name)"}
                </.link>
              </td>
              <td class="px-4 py-3 text-[#1C1C1E]">
                {c.subject} · {Enum.join(c.grades || [], ", ")}
              </td>
              <td class="px-4 py-3 text-[#8E8E93]">{c.processing_status || "—"}</td>
              <td class="px-4 py-3 text-[#8E8E93]">
                {Calendar.strftime(c.inserted_at, "%Y-%m-%d")}
              </td>
            </tr>
            <tr :if={@courses == []}>
              <td colspan="4" class="px-4 py-6 text-center text-[#8E8E93]">
                No courses created by this user.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  attr :usage, :map, required: true

  defp ai_usage_section(assigns) do
    ~H"""
    <section class="bg-white rounded-2xl shadow-md p-6">
      <h2 class="font-semibold text-[#1C1C1E] mb-3">AI usage — last {@usage.window_days}d</h2>
      <dl class="text-sm space-y-2">
        <div class="flex justify-between">
          <dt class="text-[#8E8E93]">Calls</dt>
          <dd class="text-[#1C1C1E] font-medium">{@usage.calls}</dd>
        </div>
        <div class="flex justify-between">
          <dt class="text-[#8E8E93]">Total tokens</dt>
          <dd class="text-[#1C1C1E] font-medium">{format_int(@usage.total_tokens)}</dd>
        </div>
        <div class="flex justify-between">
          <dt class="text-[#8E8E93]">Top assistant</dt>
          <dd class="text-[#1C1C1E]">{@usage.top_assistant || "—"}</dd>
        </div>
      </dl>
    </section>
    """
  end

  attr :data, :map, required: true

  defp subscription_section(assigns) do
    ~H"""
    <section class="bg-white rounded-2xl shadow-md p-6">
      <h2 class="font-semibold text-[#1C1C1E] mb-3">Subscription</h2>
      <p class="text-sm text-[#8E8E93]">{@data.message}</p>
    </section>
    """
  end

  attr :data, :map, required: true

  defp interactor_profile_section(assigns) do
    ~H"""
    <section class="bg-white rounded-2xl shadow-md p-6">
      <h2 class="font-semibold text-[#1C1C1E] mb-3">Interactor profile</h2>
      <p class="text-sm text-[#8E8E93]">{@data.message}</p>
    </section>
    """
  end

  attr :data, :map, required: true

  defp credentials_section(assigns) do
    ~H"""
    <section class="bg-white rounded-2xl shadow-md p-6">
      <h2 class="font-semibold text-[#1C1C1E] mb-3">Credentials</h2>
      <p class="text-sm text-[#8E8E93]">{@data.message}</p>
    </section>
    """
  end

  ## --- Helpers ---------------------------------------------------------

  defp role_badge_class(:admin), do: "bg-[#1C1C1E] text-white"
  defp role_badge_class(:teacher), do: "bg-[#E8F8EB] text-[#1C1C1E]"
  defp role_badge_class(:parent), do: "bg-[#FFF4CC] text-[#1C1C1E]"
  defp role_badge_class(_), do: "bg-[#F5F5F7] text-[#1C1C1E]"

  defp format_last_login(nil), do: "never"
  defp format_last_login(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_last_login(_), do: "—"

  defp activity_icon(:audit), do: "🛡"
  defp activity_icon(:course_created), do: "📚"
  defp activity_icon(_), do: "•"

  defp format_int(nil), do: "—"
  defp format_int(%Decimal{} = d), do: format_int(Decimal.to_integer(d))

  defp format_int(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_int(_), do: "—"
end
