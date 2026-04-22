defmodule FunSheepWeb.Components.TOCBanners do
  @moduledoc """
  UI surfaces for the community-approval TOC rebasing flow.

  Three banners live on the course detail page:

  1. `pending_proposal_banner/1` — shown to users authorized to approve a
     pending TOC upgrade. Explains the change in plain language, lists
     preserved vs. new vs. orphaned chapters, and exposes Approve/Reject.

  2. `applied_update_banner/1` — shown once per user per applied rebase,
     after the fact. Reassures that progress was preserved. Dismissable.

  3. `claim_ownership_banner/1` — shown to active users when the course's
     creator has been inactive 90+ days. Lets them adopt the course so
     authority doesn't stay stuck with a graduated student.

  All three delegate phx-events back to the LiveView that mounted them
  (CourseDetailLive). Trust language ("your progress is safe") is
  non-negotiable and lives here — keep the wording consistent across
  banners.
  """

  use Phoenix.Component

  @doc """
  Renders the pending-TOC approval banner. `diff` is a plan_rebase/3
  result with matched/created/orphans/deletes lists.

  Only rendered when the current user can actually approve — the caller
  is responsible for that gate via `TOCRebase.can_approve?/3`.
  """
  attr :course, :map, required: true
  attr :pending_toc, :map, required: true
  attr :diff, :map, required: true
  attr :uploader_name, :string, default: nil

  def pending_proposal_banner(assigns) do
    assigns =
      assign(assigns,
        kept_count: length(assigns.diff.matched),
        new_count: length(assigns.diff.created),
        orphan_count: length(assigns.diff.orphans),
        delete_count: length(assigns.diff.deletes)
      )

    ~H"""
    <div class="bg-white border-2 border-[#007AFF] rounded-2xl p-6 mb-6 shadow-md">
      <div class="flex items-start gap-4">
        <div class="shrink-0 w-10 h-10 rounded-full bg-[#007AFF]/10 flex items-center justify-center">
          <span class="text-xl">📚</span>
        </div>

        <div class="flex-1 min-w-0">
          <h3 class="text-lg font-bold text-[#1C1C1E] mb-1">
            A more complete textbook was uploaded{if @uploader_name, do: " by #{@uploader_name}"}
          </h3>
          <p class="text-sm text-[#8E8E93] mb-4">
            Review the changes below. Applying preserves all progress.
          </p>

          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-5 text-sm">
            <div class="bg-[#E8F8EB] rounded-xl p-3">
              <div class="text-2xl font-bold text-[#1C1C1E]">{@kept_count}</div>
              <div class="text-xs text-[#1C1C1E]/70">Chapters preserved</div>
            </div>
            <div class="bg-blue-50 rounded-xl p-3">
              <div class="text-2xl font-bold text-[#1C1C1E]">{@new_count}</div>
              <div class="text-xs text-[#1C1C1E]/70">New chapters</div>
            </div>
            <div :if={@orphan_count > 0} class="bg-[#FFF4CC] rounded-xl p-3">
              <div class="text-2xl font-bold text-[#1C1C1E]">{@orphan_count}</div>
              <div class="text-xs text-[#1C1C1E]/70">Archived (your answers stay)</div>
            </div>
            <div :if={@delete_count > 0} class="bg-[#F5F5F7] rounded-xl p-3">
              <div class="text-2xl font-bold text-[#8E8E93]">{@delete_count}</div>
              <div class="text-xs text-[#8E8E93]">Empty chapters removed</div>
            </div>
          </div>

          <div class="bg-[#F5F5F7] rounded-xl p-4 mb-5">
            <p class="text-xs font-semibold text-[#8E8E93] uppercase tracking-wider mb-2">
              Your progress is safe
            </p>
            <p class="text-sm text-[#1C1C1E] leading-relaxed">
              Every question you've answered stays linked to its chapter.
              New chapters will automatically generate fresh questions.
              <span :if={@orphan_count > 0}>
                Archived chapters keep your past answers visible but won't generate new questions.
              </span>
            </p>
          </div>

          <div :if={@new_count > 0} class="mb-5">
            <p class="text-xs font-semibold text-[#8E8E93] uppercase tracking-wider mb-2">
              New chapters you'll get ({@new_count})
            </p>
            <ul class="space-y-1 text-sm text-[#1C1C1E]">
              <li :for={ch <- Enum.take(@diff.created, 8)} class="flex items-center gap-2">
                <span class="text-[#4CD964]">+</span>
                <span class="truncate">{Map.get(ch, "name", "Unnamed")}</span>
              </li>
              <li :if={@new_count > 8} class="text-xs text-[#8E8E93] italic">
                …and {@new_count - 8} more
              </li>
            </ul>
          </div>

          <div class="flex flex-wrap gap-2">
            <button
              type="button"
              phx-click="toc_approve"
              data-confirm="Apply the new textbook structure? This preserves all your progress."
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
            >
              Apply changes
            </button>
            <button
              type="button"
              phx-click="toc_reject"
              data-confirm="Reject this textbook structure? The proposal will be dismissed."
              class="bg-white hover:bg-[#F5F5F7] text-[#1C1C1E] font-medium px-6 py-2 rounded-full border border-[#E5E5EA] transition-colors"
            >
              Not now
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the "course was upgraded" post-rebase banner. Dismisses via
  `phx-click=\"toc_ack\"` — the LiveView handler calls
  `TOCRebase.acknowledge!/3` so it doesn't come back.

  `stats` is the return value of `TOCRebase.apply/2` or a compatible
  summary: %{kept: N, created: N, orphaned: N, deleted: N}.
  """
  attr :toc, :map, required: true
  attr :stats, :map, default: %{kept: 0, created: 0, orphaned: 0, deleted: 0}

  def applied_update_banner(assigns) do
    ~H"""
    <div class="bg-[#E8F8EB] border border-[#4CD964]/30 rounded-2xl p-4 mb-6">
      <div class="flex items-start gap-3">
        <div class="shrink-0 w-8 h-8 rounded-full bg-[#4CD964]/20 flex items-center justify-center">
          <span class="text-base">✓</span>
        </div>

        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold text-[#1C1C1E] mb-1">
            Course structure was updated
          </p>
          <p class="text-sm text-[#1C1C1E]/80 leading-relaxed">
            This course now uses {@toc.chapter_count} chapters from a more complete textbook source.
            Your progress is safe — {@stats.kept} chapters preserved{if @stats.created > 0,
              do: ", #{@stats.created} new added"}.
          </p>
        </div>

        <button
          type="button"
          phx-click="toc_ack"
          class="shrink-0 text-[#8E8E93] hover:text-[#1C1C1E] text-sm font-medium"
          aria-label="Dismiss update notice"
        >
          Got it
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders the claim-ownership banner. Shown to any active user when the
  course's creator has been inactive for ≥90 days.
  """
  attr :course, :map, required: true
  attr :creator_name, :string, default: "the creator"

  def claim_ownership_banner(assigns) do
    ~H"""
    <div class="bg-white border border-[#FFCC00]/40 rounded-2xl p-5 mb-6 shadow-sm">
      <div class="flex items-start gap-3">
        <div class="shrink-0 w-8 h-8 rounded-full bg-[#FFF4CC] flex items-center justify-center">
          <span class="text-base">👋</span>
        </div>

        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold text-[#1C1C1E] mb-1">
            This course doesn't have an active caretaker
          </p>
          <p class="text-sm text-[#8E8E93] leading-relaxed mb-3">
            {@creator_name} hasn't been active for 90+ days. As someone currently using this course,
            you can adopt it — which lets you approve textbook upgrades and keep the course healthy.
          </p>

          <button
            type="button"
            phx-click="toc_adopt"
            data-confirm="Adopt this course? You'll become the primary approver for future updates."
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-5 py-2 rounded-full shadow-sm text-sm transition-colors"
          >
            Adopt this course
          </button>
        </div>
      </div>
    </div>
    """
  end
end
