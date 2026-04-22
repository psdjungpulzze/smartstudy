defmodule FunSheepWeb.StudentLive.Shared.GoalsPanel do
  @moduledoc """
  Shared goals-panel component (spec §7.1).

  Renders:

    * any proposed goals awaiting the viewer's action, with Accept /
      Counter-propose / Decline buttons wired to parent-side events, and
    * the student's active goals with real progress bars.

  This component is parent-facing in Phase 3; the student side will
  reuse the same renderer in a later pass — the events carry
  `phx-value-goal-id` so either LiveView can react.
  """

  use FunSheepWeb, :html

  alias FunSheep.Accountability.StudyGoal

  attr :pending_for_viewer, :list, required: true, doc: "Proposed goals awaiting the viewer"
  attr :active_goals, :list, required: true
  attr :progress_by_goal, :map, required: true, doc: "%{goal_id => progress-map}"
  attr :propose_open?, :boolean, default: false
  attr :student_id, :string, required: true
  attr :class, :string, default: nil

  def panel(assigns) do
    ~H"""
    <section class={["bg-white rounded-2xl border border-gray-100 p-4 sm:p-5", @class]}>
      <div class="flex items-start justify-between gap-3 mb-3">
        <div>
          <h3 class="text-sm font-extrabold text-gray-900">
            {gettext("Goals")}
          </h3>
          <p class="text-xs text-gray-500">
            {gettext("Proposed together, tracked against real activity")}
          </p>
        </div>
        <button
          type="button"
          phx-click="open_propose_goal"
          class="text-xs font-bold bg-[#4CD964] hover:bg-[#3DBF55] text-white px-4 py-2 rounded-full shadow-md"
        >
          {gettext("Propose")}
        </button>
      </div>

      <.propose_form :if={@propose_open?} student_id={@student_id} />

      <div :if={@pending_for_viewer != []} class="space-y-3 mb-4">
        <p class="text-[10px] font-bold text-amber-700 uppercase tracking-wider">
          {gettext("Awaiting your response")}
        </p>
        <.pending_row :for={goal <- @pending_for_viewer} goal={goal} />
      </div>

      <div :if={@active_goals == [] and @pending_for_viewer == []} class="py-6 text-center">
        <p class="text-sm text-gray-500">
          {gettext("No goals yet. Propose one to start a joint plan.")}
        </p>
      </div>

      <ul :if={@active_goals != []} class="space-y-3">
        <.active_row
          :for={goal <- @active_goals}
          goal={goal}
          progress={Map.get(@progress_by_goal, goal.id, %{status: :insufficient_data})}
        />
      </ul>
    </section>
    """
  end

  attr :goal, :any, required: true

  defp pending_row(assigns) do
    ~H"""
    <li class="rounded-xl border border-amber-200 bg-amber-50 p-3 space-y-2 list-none">
      <p class="text-sm font-bold text-amber-900">
        {goal_description(@goal)}
      </p>
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          phx-click="accept_goal"
          phx-value-goal-id={@goal.id}
          class="text-xs font-bold bg-[#4CD964] hover:bg-[#3DBF55] text-white px-3 py-1.5 rounded-full"
        >
          {gettext("Accept")}
        </button>
        <button
          type="button"
          phx-click="open_counter_goal"
          phx-value-goal-id={@goal.id}
          class="text-xs font-bold bg-white border border-gray-200 text-gray-700 px-3 py-1.5 rounded-full hover:border-[#4CD964]"
        >
          {gettext("Counter-propose")}
        </button>
        <button
          type="button"
          phx-click="decline_goal"
          phx-value-goal-id={@goal.id}
          class="text-xs font-bold bg-white border border-gray-200 text-gray-500 px-3 py-1.5 rounded-full hover:text-[#FF3B30]"
        >
          {gettext("Decline")}
        </button>
      </div>
    </li>
    """
  end

  attr :goal, :any, required: true
  attr :progress, :map, required: true

  defp active_row(assigns) do
    pct = progress_pct(assigns.progress)
    summary = progress_summary(assigns.goal, assigns.progress)
    assigns = assigns |> assign(:pct, pct) |> assign(:summary, summary)

    ~H"""
    <li class="rounded-xl border border-gray-100 p-3 list-none">
      <div class="flex items-start justify-between gap-3">
        <p class="text-sm font-bold text-gray-900">
          {goal_description(@goal)}
        </p>
        <span class={[
          "text-[10px] font-bold px-2 py-0.5 rounded-full",
          if(@progress[:on_track?],
            do: "bg-[#E8F8EB] text-[#256029]",
            else: "bg-amber-50 text-amber-700"
          )
        ]}>
          {if @progress[:on_track?], do: gettext("on track"), else: gettext("behind")}
        </span>
      </div>
      <p class="text-xs text-gray-500 mt-1">{@summary}</p>
      <div class="mt-2 w-full h-2 bg-gray-100 rounded-full overflow-hidden">
        <div class="h-full bg-[#4CD964]" style={"width: #{@pct}%"}></div>
      </div>
    </li>
    """
  end

  attr :student_id, :string, required: true

  defp propose_form(assigns) do
    ~H"""
    <form
      phx-submit="propose_goal"
      class="rounded-xl border border-gray-200 bg-gray-50 p-3 mb-4 space-y-2"
    >
      <input type="hidden" name="student_id" value={@student_id} />
      <label class="block text-[10px] font-bold text-gray-500 uppercase tracking-wider">
        {gettext("Goal type")}
      </label>
      <select
        name="goal_type"
        class="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm"
      >
        <option value="daily_minutes">{gettext("Daily minutes")}</option>
        <option value="weekly_practice_count">{gettext("Weekly practice count")}</option>
        <option value="streak_days">{gettext("Streak days")}</option>
      </select>

      <label class="block text-[10px] font-bold text-gray-500 uppercase tracking-wider">
        {gettext("Target value")}
      </label>
      <input
        type="number"
        name="target_value"
        min="1"
        max="300"
        class="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm"
        required
      />

      <label class="block text-[10px] font-bold text-gray-500 uppercase tracking-wider">
        {gettext("End date (optional)")}
      </label>
      <input
        type="date"
        name="end_date"
        class="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm"
      />

      <div class="flex justify-end gap-2 pt-1">
        <button
          type="button"
          phx-click="close_propose_goal"
          class="text-xs font-bold px-4 py-2 rounded-full text-gray-500"
        >
          {gettext("Cancel")}
        </button>
        <button
          type="submit"
          class="text-xs font-bold bg-[#4CD964] hover:bg-[#3DBF55] text-white px-4 py-2 rounded-full shadow-md"
        >
          {gettext("Propose to student")}
        </button>
      </div>
    </form>
    """
  end

  ## ── Helpers ─────────────────────────────────────────────────────────────

  def goal_description(%StudyGoal{goal_type: :daily_minutes, target_value: v}),
    do: gettext("%{n} min/day of study", n: v)

  def goal_description(%StudyGoal{goal_type: :weekly_practice_count, target_value: v}),
    do: gettext("%{n} practice sessions / week", n: v)

  def goal_description(%StudyGoal{goal_type: :target_readiness_score, target_value: v}),
    do: gettext("%{n}%% readiness by test day", n: v)

  def goal_description(%StudyGoal{goal_type: :streak_days, target_value: v}),
    do: gettext("%{n}-day streak", n: v)

  defp progress_pct(%{adherence_pct: p}) when is_integer(p), do: p
  defp progress_pct(_), do: 0

  defp progress_summary(
         %StudyGoal{goal_type: :daily_minutes},
         %{status: :ok, actual_daily_minutes: a, target_daily_minutes: t}
       ),
       do: gettext("%{a} min/day so far · target %{t} min/day", a: a, t: t)

  defp progress_summary(
         %StudyGoal{goal_type: :weekly_practice_count},
         %{status: :ok, actual_per_week: a, target_per_week: t}
       ),
       do: gettext("%{a} sessions/wk · target %{t}/wk", a: a, t: t)

  defp progress_summary(
         %StudyGoal{goal_type: :streak_days},
         %{status: :ok, current_streak: s, target_streak: t}
       ),
       do: gettext("%{s} of %{t} days", s: s, t: t)

  defp progress_summary(_, _), do: gettext("Progress not ready yet.")
end
