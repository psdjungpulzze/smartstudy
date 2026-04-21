defmodule FunSheepWeb.GamificationModals do
  @moduledoc """
  Streak and Fleece Points (FP) detail modals shown when a student taps
  the AppBar badges. Designed to maximize motivation by surfacing
  progress visibility, loss aversion, and the next concrete action.
  """

  use Phoenix.Component
  import FunSheepWeb.CoreComponents, only: [show: 2, hide: 2, icon: 1]
  alias Phoenix.LiveView.JS

  ## ── Streak Modal ─────────────────────────────────────────────────────────

  attr :id, :string, default: "streak-modal"

  attr :summary, :map,
    default: nil,
    doc: "%{current_streak, longest_streak, wool_level, status, next_milestone, ...} or nil"

  def streak_modal(assigns) do
    ~H"""
    <div
      id={@id}
      class="hidden fixed inset-0 z-[60]"
      phx-remove={hide(%JS{}, "##{@id}")}
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
    >
      <%!-- Backdrop --%>
      <div
        class="absolute inset-0 bg-black/40 backdrop-blur-sm"
        phx-click={hide(%JS{}, "##{@id}")}
        aria-hidden="true"
      >
      </div>

      <%!-- Sheet (mobile) / Centered (desktop) --%>
      <div class="absolute inset-x-0 bottom-0 sm:inset-0 sm:flex sm:items-center sm:justify-center p-0 sm:p-4">
        <div
          class="bg-white dark:bg-[#2C2C2E] rounded-t-3xl sm:rounded-2xl shadow-xl w-full sm:max-w-md max-h-[85vh] overflow-y-auto"
          phx-click-away={hide(%JS{}, "##{@id}")}
          phx-window-keydown={hide(%JS{}, "##{@id}")}
          phx-key="escape"
        >
          <div class="sticky top-0 bg-white dark:bg-[#2C2C2E] px-6 pt-6 pb-3 flex items-center justify-between border-b border-[#E5E5EA] dark:border-[#3A3A3C]">
            <h2
              id={"#{@id}-title"}
              class="text-xl font-bold text-[#1C1C1E] dark:text-white flex items-center gap-2"
            >
              <span class="text-2xl animate-streak">🔥</span> Your Streak
            </h2>
            <button
              type="button"
              phx-click={hide(%JS{}, "##{@id}")}
              class="w-9 h-9 rounded-full hover:bg-[#F5F5F7] dark:hover:bg-[#3A3A3C] flex items-center justify-center text-[#8E8E93]"
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>

          <div class="px-6 py-4">
            <%= if @summary do %>
              <.streak_body summary={@summary} />
            <% else %>
              <.loading_skeleton />
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :summary, :map, required: true

  defp streak_body(assigns) do
    ~H"""
    <%!-- Big current streak + status banner --%>
    <div class="text-center py-2">
      <p class="text-7xl font-extrabold text-orange-500 leading-none">
        {@summary.current_streak}
      </p>
      <p class="text-sm text-[#8E8E93] mt-1">
        day{if @summary.current_streak == 1, do: "", else: "s"} in a row
      </p>
    </div>

    <%!-- Plain-language explainer --%>
    <p class="text-sm text-[#1C1C1E] dark:text-white text-center mt-3 leading-snug">
      Your <span class="font-semibold">streak</span>
      counts days in a row you've studied. Answer at least one question today to keep it alive — miss a day and it resets.
    </p>

    <.status_banner status={@summary.status} current_streak={@summary.current_streak} />

    <%!-- 30-day heatmap --%>
    <div class="mt-5">
      <div class="flex items-center justify-between mb-2">
        <h3 class="text-sm font-semibold text-[#1C1C1E] dark:text-white">Last 30 days</h3>
        <span class="text-xs text-[#8E8E93]">
          {Enum.count(@summary.heatmap, & &1.active)} of 30 days studied
        </span>
      </div>
      <div class="grid grid-cols-10 gap-1">
        <div
          :for={cell <- @summary.heatmap}
          class={[
            "aspect-square rounded-md",
            if(cell.active,
              do: "bg-orange-400 dark:bg-orange-500",
              else: "bg-[#F5F5F7] dark:bg-[#3A3A3C]"
            )
          ]}
          title={"#{Calendar.strftime(cell.date, "%b %-d")} — #{if cell.active, do: "studied", else: "missed"}"}
        >
        </div>
      </div>
    </div>

    <%!-- Next milestone --%>
    <%= if @summary.next_milestone do %>
      <div class="mt-5 rounded-2xl bg-amber-50 dark:bg-amber-900/20 border border-amber-100 dark:border-amber-900/40 p-4">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-xs uppercase tracking-wide font-semibold text-amber-700 dark:text-amber-300">
              Next milestone
            </p>
            <p class="text-lg font-bold text-amber-900 dark:text-amber-100 mt-0.5">
              🔥 {@summary.next_milestone}-day streak
            </p>
          </div>
          <div class="text-right">
            <p class="text-2xl font-extrabold text-amber-700 dark:text-amber-300">
              {@summary.next_milestone - @summary.current_streak}
            </p>
            <p class="text-xs text-amber-700/70 dark:text-amber-300/70">to go</p>
          </div>
        </div>
      </div>
    <% end %>

    <%!-- Personal best --%>
    <div class="mt-3 grid grid-cols-2 gap-3">
      <div class="rounded-2xl bg-[#F5F5F7] dark:bg-[#3A3A3C] p-3">
        <p class="text-xs text-[#8E8E93]">Longest streak</p>
        <p class="text-xl font-bold text-[#1C1C1E] dark:text-white mt-0.5">
          {@summary.longest_streak}
          <span class="text-sm font-normal text-[#8E8E93]">
            day{if @summary.longest_streak == 1, do: "", else: "s"}
          </span>
        </p>
      </div>
      <div class="rounded-2xl bg-[#F5F5F7] dark:bg-[#3A3A3C] p-3">
        <p class="text-xs text-[#8E8E93]">Wool level</p>
        <p class="text-xl font-bold text-[#1C1C1E] dark:text-white mt-0.5">
          {@summary.wool_level}<span class="text-sm font-normal text-[#8E8E93]">/10</span>
        </p>
      </div>
    </div>

    <%!-- Primary CTA --%>
    <a
      href="/dashboard"
      class="mt-5 mb-2 w-full bg-[#4CD964] hover:bg-[#3DBF55] text-white font-semibold px-6 py-3 rounded-full shadow-md flex items-center justify-center gap-2 transition-colors"
    >
      <span>{cta_label_for_status(@summary.status)}</span>
      <span aria-hidden="true">→</span>
    </a>
    """
  end

  attr :status, :atom, required: true
  attr :current_streak, :integer, required: true

  defp status_banner(%{status: :safe} = assigns) do
    ~H"""
    <div class="rounded-2xl bg-green-50 dark:bg-green-900/20 border border-green-100 dark:border-green-900/40 p-3 mt-2 flex items-center gap-2">
      <.icon name="hero-check-circle" class="w-5 h-5 text-[#4CD964]" />
      <p class="text-sm font-medium text-green-800 dark:text-green-200">
        Streak safe — you studied today
      </p>
    </div>
    """
  end

  defp status_banner(%{status: :at_risk} = assigns) do
    ~H"""
    <div class="rounded-2xl bg-orange-50 dark:bg-orange-900/20 border border-orange-200 dark:border-orange-900/40 p-3 mt-2 flex items-center gap-2">
      <.icon name="hero-clock" class="w-5 h-5 text-orange-500" />
      <p class="text-sm font-medium text-orange-800 dark:text-orange-200">
        Practice today or lose your {@current_streak}-day streak!
      </p>
    </div>
    """
  end

  defp status_banner(%{status: :broken_today} = assigns) do
    ~H"""
    <div class="rounded-2xl bg-red-50 dark:bg-red-900/20 border border-red-100 dark:border-red-900/40 p-3 mt-2 flex items-center gap-2">
      <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-[#FF3B30]" />
      <p class="text-sm font-medium text-red-800 dark:text-red-200">
        Streak at risk — start now to save it
      </p>
    </div>
    """
  end

  defp status_banner(%{status: :no_streak} = assigns) do
    ~H"""
    <div class="rounded-2xl bg-blue-50 dark:bg-blue-900/20 border border-blue-100 dark:border-blue-900/40 p-3 mt-2 flex items-center gap-2">
      <.icon name="hero-sparkles" class="w-5 h-5 text-[#007AFF]" />
      <p class="text-sm font-medium text-blue-800 dark:text-blue-200">
        Start your streak today — it only takes one session
      </p>
    </div>
    """
  end

  defp cta_label_for_status(:safe), do: "Keep going"
  defp cta_label_for_status(:at_risk), do: "Save your streak"
  defp cta_label_for_status(:broken_today), do: "Save your streak"
  defp cta_label_for_status(:no_streak), do: "Start studying"

  ## ── FP Modal ─────────────────────────────────────────────────────────────

  attr :id, :string, default: "fp-modal"
  attr :summary, :map, default: nil

  def fp_modal(assigns) do
    ~H"""
    <div
      id={@id}
      class="hidden fixed inset-0 z-[60]"
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
    >
      <div
        class="absolute inset-0 bg-black/40 backdrop-blur-sm"
        phx-click={hide(%JS{}, "##{@id}")}
        aria-hidden="true"
      >
      </div>

      <div class="absolute inset-x-0 bottom-0 sm:inset-0 sm:flex sm:items-center sm:justify-center p-0 sm:p-4">
        <div
          class="bg-white dark:bg-[#2C2C2E] rounded-t-3xl sm:rounded-2xl shadow-xl w-full sm:max-w-lg max-h-[88vh] overflow-y-auto"
          phx-click-away={hide(%JS{}, "##{@id}")}
          phx-window-keydown={hide(%JS{}, "##{@id}")}
          phx-key="escape"
        >
          <div class="sticky top-0 bg-white dark:bg-[#2C2C2E] px-6 pt-6 pb-3 flex items-center justify-between border-b border-[#E5E5EA] dark:border-[#3A3A3C] z-10">
            <h2
              id={"#{@id}-title"}
              class="text-xl font-bold text-[#1C1C1E] dark:text-white flex items-center gap-2"
            >
              <span class="text-2xl">⚡</span> Fleece Points
            </h2>
            <button
              type="button"
              phx-click={hide(%JS{}, "##{@id}")}
              class="w-9 h-9 rounded-full hover:bg-[#F5F5F7] dark:hover:bg-[#3A3A3C] flex items-center justify-center text-[#8E8E93]"
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>

          <div class="px-6 py-4">
            <%= if @summary do %>
              <.fp_body summary={@summary} />
            <% else %>
              <.loading_skeleton />
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :summary, :map, required: true

  defp fp_body(assigns) do
    ~H"""
    <%!-- Total + level header --%>
    <div class="text-center py-2">
      <p class="text-5xl font-extrabold text-amber-500 leading-none">
        {@summary.total_xp}
        <span class="text-2xl text-amber-400 font-bold">FP</span>
      </p>
      <p class="text-sm font-semibold text-[#1C1C1E] dark:text-white mt-2">
        Level {@summary.level.level} · {@summary.level.name}
      </p>
    </div>

    <%!-- Plain-language explainer --%>
    <p class="text-sm text-[#1C1C1E] dark:text-white text-center mt-3 leading-snug">
      <span class="font-semibold">Fleece Points</span>
      are what you earn for every question, assessment, and daily challenge. The more you answer, the more you earn — and the higher your level.
    </p>

    <%!-- Level progress --%>
    <div class="mt-3">
      <div class="flex justify-between text-xs text-[#8E8E93] mb-1">
        <span>Level {@summary.level.level}</span>
        <span :if={@summary.level.next_threshold}>Level {@summary.level.level + 1}</span>
      </div>
      <div class="h-2 bg-[#F5F5F7] dark:bg-[#3A3A3C] rounded-full overflow-hidden">
        <div
          class="h-full bg-gradient-to-r from-amber-400 to-amber-500 rounded-full transition-all"
          style={"width: #{@summary.level.progress_pct}%"}
        >
        </div>
      </div>
      <p :if={@summary.level.fp_to_next_level} class="text-xs text-[#8E8E93] mt-1 text-center">
        {@summary.level.fp_to_next_level} FP to Level {@summary.level.level + 1}
      </p>
      <p
        :if={is_nil(@summary.level.next_threshold)}
        class="text-xs text-amber-600 mt-1 text-center font-semibold"
      >
        ✨ Max level reached!
      </p>
    </div>

    <%!-- This week chart --%>
    <div class="mt-5">
      <div class="flex items-center justify-between mb-2">
        <h3 class="text-sm font-semibold text-[#1C1C1E] dark:text-white">This week</h3>
        <span class="text-xs text-[#8E8E93]">{@summary.xp_this_week} FP</span>
      </div>
      <.week_bar_chart chart={@summary.week_chart} today={@summary.today} />
    </div>

    <%!-- Source breakdown --%>
    <div :if={@summary.source_breakdown != []} class="mt-5">
      <h3 class="text-sm font-semibold text-[#1C1C1E] dark:text-white mb-2">
        Where your FP came from
      </h3>
      <div class="space-y-2">
        <div
          :for={entry <- @summary.source_breakdown}
          class="flex items-center justify-between bg-[#F5F5F7] dark:bg-[#3A3A3C] rounded-xl px-3 py-2"
        >
          <div class="flex items-center gap-2">
            <span class="text-base">{source_icon(entry.source)}</span>
            <span class="text-sm font-medium text-[#1C1C1E] dark:text-white">
              {source_label(entry.source)}
            </span>
            <span class="text-xs text-[#8E8E93]">· {entry.count}</span>
          </div>
          <span class="text-sm font-bold text-amber-600">+{entry.amount}</span>
        </div>
      </div>
    </div>

    <%!-- Recent activity --%>
    <div :if={@summary.recent_events != []} class="mt-5">
      <h3 class="text-sm font-semibold text-[#1C1C1E] dark:text-white mb-2">Recent activity</h3>
      <div class="space-y-1">
        <div
          :for={event <- @summary.recent_events}
          class="flex items-center justify-between text-sm py-1"
        >
          <div class="flex items-center gap-2">
            <span>{source_icon(event.source)}</span>
            <span class="text-[#1C1C1E] dark:text-white">{source_label(event.source)}</span>
            <span class="text-xs text-[#8E8E93]">· {time_ago(event.inserted_at)}</span>
          </div>
          <span class="font-semibold text-amber-600">+{event.amount} FP</span>
        </div>
      </div>
    </div>

    <%!-- Earn more --%>
    <div class="mt-5">
      <h3 class="text-sm font-semibold text-[#1C1C1E] dark:text-white mb-2">Earn more FP</h3>
      <div class="space-y-2">
        <a
          :for={rule <- @summary.earn_more}
          href={rule.cta_path}
          class="flex items-start gap-3 p-3 rounded-xl bg-white dark:bg-[#2C2C2E] border border-[#E5E5EA] dark:border-[#3A3A3C] hover:border-[#4CD964] dark:hover:border-[#4CD964] transition-colors"
        >
          <span class="text-lg shrink-0">{rule.icon}</span>
          <div class="flex-1 min-w-0">
            <div class="flex items-baseline justify-between gap-2">
              <p class="text-sm font-semibold text-[#1C1C1E] dark:text-white">{rule.label}</p>
              <p class="text-xs font-bold text-amber-600 shrink-0">{rule.amount_label}</p>
            </div>
            <p class="text-xs text-[#8E8E93] mt-0.5">{rule.description}</p>
          </div>
        </a>
      </div>
    </div>
    """
  end

  attr :chart, :list, required: true
  attr :today, Date, required: true

  defp week_bar_chart(assigns) do
    max_amount = assigns.chart |> Enum.map(& &1.amount) |> Enum.max(fn -> 0 end)
    assigns = assign(assigns, :max_amount, max_amount)

    ~H"""
    <div class="flex items-end gap-1.5 h-24">
      <div :for={day <- @chart} class="flex-1 flex flex-col items-center gap-1">
        <div class="flex-1 w-full flex items-end">
          <div
            class={[
              "w-full rounded-t-md transition-all",
              if(Date.compare(day.date, @today) == :eq,
                do: "bg-amber-500",
                else: "bg-amber-300 dark:bg-amber-400"
              ),
              if(day.amount == 0, do: "min-h-[2px] opacity-40", else: "min-h-[6px]")
            ]}
            style={"height: #{bar_height_pct(day.amount, @max_amount)}%"}
            title={"#{Calendar.strftime(day.date, "%a %b %-d")}: #{day.amount} FP"}
          >
          </div>
        </div>
        <span class="text-[10px] text-[#8E8E93]">
          {String.slice(Calendar.strftime(day.date, "%a"), 0..0)}
        </span>
      </div>
    </div>
    """
  end

  defp bar_height_pct(_amount, 0), do: 0
  defp bar_height_pct(amount, max), do: round(amount * 100 / max)

  ## ── Loading skeleton ─────────────────────────────────────────────────────

  defp loading_skeleton(assigns) do
    ~H"""
    <div class="animate-pulse space-y-3 py-4">
      <div class="h-12 bg-[#F5F5F7] dark:bg-[#3A3A3C] rounded-xl mx-auto w-32"></div>
      <div class="h-4 bg-[#F5F5F7] dark:bg-[#3A3A3C] rounded w-48 mx-auto"></div>
      <div class="h-20 bg-[#F5F5F7] dark:bg-[#3A3A3C] rounded-xl"></div>
      <div class="h-16 bg-[#F5F5F7] dark:bg-[#3A3A3C] rounded-xl"></div>
    </div>
    """
  end

  ## ── Helpers ──────────────────────────────────────────────────────────────

  @doc """
  Returns a JS chain that opens the streak modal with a smooth transition.
  Pairs with a `phx-click` that also pushes `open_streak_detail` to the
  LiveView so the summary is re-fetched fresh.
  """
  def open_streak_modal_js(id \\ "streak-modal") do
    JS.push("open_streak_detail")
    |> show("##{id}")
  end

  def open_fp_modal_js(id \\ "fp-modal") do
    JS.push("open_fp_detail")
    |> show("##{id}")
  end

  defp source_icon("practice"), do: "🎯"
  defp source_icon("assessment"), do: "📝"
  defp source_icon("quick_test"), do: "⚡"
  defp source_icon("daily_challenge"), do: "🔥"
  defp source_icon("review"), do: "🧠"
  defp source_icon("study_session"), do: "🌅"
  defp source_icon("study_guide"), do: "📖"
  defp source_icon("streak_bonus"), do: "✨"
  defp source_icon("achievement"), do: "🏆"
  defp source_icon(_), do: "⭐"

  defp source_label("practice"), do: "Practice"
  defp source_label("assessment"), do: "Assessment"
  defp source_label("quick_test"), do: "Quick Test"
  defp source_label("daily_challenge"), do: "Daily Shear"
  defp source_label("review"), do: "Review"
  defp source_label("study_session"), do: "Study Session"
  defp source_label("study_guide"), do: "Study Guide"
  defp source_label("streak_bonus"), do: "Streak Bonus"
  defp source_label("achievement"), do: "Achievement"
  defp source_label(other), do: String.capitalize(other)

  defp time_ago(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86_400)}d ago"
      true -> Calendar.strftime(dt, "%b %-d")
    end
  end
end
