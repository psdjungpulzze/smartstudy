defmodule FunSheepWeb.StudentLive.Shared.ShareTriggers do
  @moduledoc """
  Parent-initiated share-CTA component (my interpretation of the
  "peer-sharing triggers" user requirement for Phase 2/3 prerequisites).

  Surfaces a small banner when the student has recently hit a real
  milestone (goal achieved, target score reached). The actual share uses
  the existing `/share/progress/:token` route — this component never
  auto-shares and requires an explicit click.

  The `phx-click="open_share"` event should be handled by the parent
  LiveView and is expected to navigate or toggle share state.
  """

  use FunSheepWeb, :html

  attr :triggers, :list, required: true
  attr :student_id, :string, required: true
  attr :class, :string, default: nil

  def banner(assigns) do
    ~H"""
    <aside
      :if={@triggers != []}
      class={["rounded-2xl border border-[#A4E9AE] bg-[#E8F8EB] p-4 sm:p-5", @class]}
    >
      <p class="text-[11px] font-bold text-[#256029] uppercase tracking-wider mb-1">
        {gettext("Milestone reached")}
      </p>
      <.trigger :for={t <- @triggers} trigger={t} student_id={@student_id} />
    </aside>
    """
  end

  attr :trigger, :map, required: true
  attr :student_id, :string, required: true

  defp trigger(assigns) do
    ~H"""
    <div class="mt-2 flex items-center justify-between gap-3">
      <p class="text-sm text-[#256029] font-semibold">
        {trigger_copy(@trigger)}
      </p>
      <button
        type="button"
        phx-click="open_share"
        phx-value-student-id={@student_id}
        class="shrink-0 text-xs font-bold bg-white text-[#4CD964] border border-[#4CD964] px-3 py-1.5 rounded-full hover:bg-[#CDF3D3]"
      >
        {gettext("Share")}
      </button>
    </div>
    """
  end

  defp trigger_copy(%{kind: :goal_achieved, goal_type: :daily_minutes, target_value: v}),
    do: gettext("Hit the %{n} min/day goal.", n: v)

  defp trigger_copy(%{kind: :goal_achieved, goal_type: :streak_days, target_value: v}),
    do: gettext("Hit a %{n}-day streak.", n: v)

  defp trigger_copy(%{kind: :goal_achieved, goal_type: :weekly_practice_count, target_value: v}),
    do: gettext("Hit %{n} practice sessions this week.", n: v)

  defp trigger_copy(%{kind: :goal_achieved, goal_type: :target_readiness_score, target_value: v}),
    do: gettext("Hit %{n}%% readiness target.", n: v)

  defp trigger_copy(_), do: gettext("Worth celebrating.")
end
