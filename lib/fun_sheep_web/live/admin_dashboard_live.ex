defmodule FunSheepWeb.AdminDashboardLive do
  @moduledoc """
  Admin dashboard: real platform metrics + recent audit activity.
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Accounts, Admin, AIUsage, Questions, Repo}
  alias FunSheep.AIUsage.Pricing
  alias FunSheep.Courses.Course

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin")
     |> load_metrics()}
  end

  defp load_metrics(socket) do
    users_by_role = Accounts.count_users_by_role()
    total_users = users_by_role |> Map.values() |> Enum.sum()

    course_total = Repo.aggregate(Course, :count)
    review_count = Questions.count_questions_needing_review()
    recent_audit = Admin.list_audit_logs(limit: 10)
    ai_summary_24h = load_ai_summary_24h()

    socket
    |> assign(:users_by_role, users_by_role)
    |> assign(:total_users, total_users)
    |> assign(:course_total, course_total)
    |> assign(:review_count, review_count)
    |> assign(:recent_audit, recent_audit)
    |> assign(:ai_summary_24h, ai_summary_24h)
  end

  defp load_ai_summary_24h do
    now = DateTime.utc_now()
    since = DateTime.add(now, -24 * 3600, :second)
    AIUsage.summary(%{since: since, until: now})
  rescue
    _ -> %{calls: 0, est_cost_cents: nil}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-[#1C1C1E]">Admin</h1>
        <p class="text-[#8E8E93] text-sm mt-1">
          Welcome back, {@current_user["display_name"]}.
        </p>
      </div>

      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
        <.stat_card label="Total users" value={@total_users} />
        <.stat_card
          label="Students"
          value={Map.get(@users_by_role, :student, 0)}
          accent="text-[#4CD964]"
        />
        <.stat_card
          label="Teachers"
          value={Map.get(@users_by_role, :teacher, 0)}
          accent="text-[#007AFF]"
        />
        <.stat_card
          label="Admins"
          value={Map.get(@users_by_role, :admin, 0)}
          accent="text-[#1C1C1E]"
        />
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
        <.link
          navigate={~p"/admin/courses"}
          class="bg-white rounded-2xl shadow-md p-6 hover:shadow-lg transition-shadow block"
        >
          <div class="flex items-center justify-between mb-4">
            <h3 class="font-semibold text-[#1C1C1E]">Courses</h3>
            <.icon name="hero-book-open" class="w-5 h-5 text-[#8E8E93]" />
          </div>
          <p class="text-3xl font-bold text-[#1C1C1E]">{@course_total}</p>
          <p class="text-sm text-[#8E8E93] mt-1">All courses</p>
        </.link>

        <.link
          navigate={~p"/admin/questions/review"}
          class="bg-white rounded-2xl shadow-md p-6 hover:shadow-lg transition-shadow block"
        >
          <div class="flex items-center justify-between mb-4">
            <h3 class="font-semibold text-[#1C1C1E]">Question review</h3>
            <.icon name="hero-clipboard-document-check" class="w-5 h-5 text-[#8E8E93]" />
          </div>
          <p class={[
            "text-3xl font-bold",
            if(@review_count > 0, do: "text-[#FFCC00]", else: "text-[#4CD964]")
          ]}>
            {@review_count}
          </p>
          <p class="text-sm text-[#8E8E93] mt-1">Flagged for review</p>
        </.link>

        <.link
          navigate={~p"/admin/users"}
          class="bg-white rounded-2xl shadow-md p-6 hover:shadow-lg transition-shadow block"
        >
          <div class="flex items-center justify-between mb-4">
            <h3 class="font-semibold text-[#1C1C1E]">Manage users</h3>
            <.icon name="hero-users" class="w-5 h-5 text-[#8E8E93]" />
          </div>
          <p class="text-sm text-[#8E8E93]">
            Search, suspend, promote, demote, impersonate across every account.
          </p>
        </.link>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
        <.link
          navigate={~p"/admin/usage/ai"}
          class="bg-white rounded-2xl shadow-md p-5 hover:shadow-lg transition-shadow block"
        >
          <div class="flex items-center justify-between">
            <h3 class="font-semibold text-[#1C1C1E]">AI usage (24h)</h3>
            <.icon name="hero-chart-bar" class="w-5 h-5 text-[#8E8E93]" />
          </div>
          <p class="text-2xl font-bold text-[#1C1C1E] mt-2">
            {Pricing.format_cost_cents(@ai_summary_24h.est_cost_cents)}
          </p>
          <p class="text-xs text-[#8E8E93] mt-1">
            {@ai_summary_24h.calls} calls · tokens, cost, latency breakdown
          </p>
        </.link>

        <.link
          navigate={~p"/admin/settings/mfa"}
          class="bg-white rounded-2xl shadow-md p-5 hover:shadow-lg transition-shadow block"
        >
          <div class="flex items-center justify-between">
            <h3 class="font-semibold text-[#1C1C1E]">Two-factor auth</h3>
            <.icon name="hero-bolt" class="w-5 h-5 text-[#8E8E93]" />
          </div>
          <p class="text-xs text-[#8E8E93] mt-1">
            Enroll or review your TOTP setup.
          </p>
        </.link>

        <.link
          navigate="/admin/jobs"
          class="bg-white rounded-2xl shadow-md p-5 hover:shadow-lg transition-shadow block"
        >
          <div class="flex items-center justify-between">
            <h3 class="font-semibold text-[#1C1C1E]">Background jobs</h3>
            <.icon name="hero-cog-6-tooth" class="w-5 h-5 text-[#8E8E93]" />
          </div>
          <p class="text-xs text-[#8E8E93] mt-1">
            Oban Web: queues, jobs, retries.
          </p>
        </.link>

        <.link
          navigate={~p"/admin/audit-log"}
          class="bg-white rounded-2xl shadow-md p-5 hover:shadow-lg transition-shadow block"
        >
          <div class="flex items-center justify-between">
            <h3 class="font-semibold text-[#1C1C1E]">Audit log</h3>
            <.icon name="hero-document-text" class="w-5 h-5 text-[#8E8E93]" />
          </div>
          <p class="text-xs text-[#8E8E93] mt-1">
            Full history of privileged actions.
          </p>
        </.link>
      </div>

      <div class="bg-white rounded-2xl shadow-md p-6">
        <div class="flex items-center justify-between mb-4">
          <h2 class="font-semibold text-[#1C1C1E]">Recent admin activity</h2>
          <.link navigate={~p"/admin/audit-log"} class="text-sm text-[#4CD964] font-medium">
            View all →
          </.link>
        </div>

        <ul :if={@recent_audit != []} class="divide-y divide-[#F5F5F7]">
          <li :for={log <- @recent_audit} class="py-3 flex items-center justify-between gap-4">
            <div class="min-w-0 flex-1">
              <div class="text-sm font-medium text-[#1C1C1E] truncate">{log.actor_label}</div>
              <div class="text-xs text-[#8E8E93]">
                <code>{log.action}</code>
                <span :if={log.target_type}>· {log.target_type}</span>
              </div>
            </div>
            <div class="text-xs text-[#8E8E93] whitespace-nowrap">
              {Calendar.strftime(log.inserted_at, "%Y-%m-%d %H:%M")}
            </div>
          </li>
        </ul>

        <p :if={@recent_audit == []} class="text-sm text-[#8E8E93] text-center py-6">
          No admin actions recorded yet.
        </p>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :accent, :string, default: "text-[#1C1C1E]"

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-5">
      <div class="text-xs uppercase tracking-wide text-[#8E8E93] font-medium">{@label}</div>
      <div class={["text-3xl font-bold mt-1", @accent]}>{@value}</div>
    </div>
    """
  end
end
