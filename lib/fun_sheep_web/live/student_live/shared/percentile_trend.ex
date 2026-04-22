defmodule FunSheepWeb.StudentLive.Shared.PercentileTrend do
  @moduledoc """
  Shared percentile-trend sparkline (spec §6.1).

  Renders a weekly percentile trend line plus the current percentile and
  the target (if set) with days-to-test context. No fake data: when fewer
  than 2 weekly snapshots are available, the component renders an honest
  "check back next week" empty state.

  Wellbeing-dampened callers should simply not render this component at
  all (see `WellbeingFraming.dampen_competitive?/1`).
  """

  use FunSheepWeb, :html

  attr :history, :list,
    required: true,
    doc: "Result of Assessments.readiness_percentile_history/3"

  attr :current_percentile, :any, default: nil
  attr :target_readiness, :any, default: nil
  attr :days_to_test, :any, default: nil
  attr :class, :string, default: nil

  def trend(assigns) do
    assigns = assign(assigns, :empty?, length(assigns.history) < 2)

    ~H"""
    <section class={["bg-white rounded-2xl border border-gray-100 p-4 sm:p-5", @class]}>
      <div class="flex items-start justify-between gap-3 mb-3">
        <div>
          <h3 class="text-sm font-extrabold text-gray-900">
            {gettext("Percentile trend")}
          </h3>
          <p class="text-xs text-gray-500">
            {gettext("Weekly rank within same-grade students")}
          </p>
        </div>
        <div :if={@current_percentile} class="text-right">
          <p class="text-xs text-gray-400 uppercase tracking-wider">
            {gettext("Now")}
          </p>
          <p class="text-2xl font-extrabold text-[#4CD964]">
            {@current_percentile}
          </p>
        </div>
      </div>

      <div :if={@empty?} class="py-6 text-center">
        <p class="text-sm text-gray-500">
          {gettext("Check back next week — we'll show a trend once we have two weekly snapshots.")}
        </p>
      </div>

      <.sparkline :if={!@empty?} history={@history} />

      <div
        :if={@target_readiness && @days_to_test}
        class="mt-4 rounded-xl bg-gray-50 border border-gray-100 p-3"
      >
        <p class="text-[10px] font-bold text-gray-500 uppercase tracking-wider">
          {gettext("Joint target")}
        </p>
        <p class="text-sm text-gray-800 mt-1">
          <span class="font-extrabold text-[#4CD964]">{@target_readiness}%</span>
          {gettext("readiness by test day")}
          <span class="text-gray-500">· {@days_to_test} {gettext("days to go")}</span>
        </p>
      </div>
    </section>
    """
  end

  attr :history, :list, required: true

  defp sparkline(assigns) do
    points = assigns.history
    width = 320.0
    height = 56.0
    count = length(points)

    coords =
      points
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {%{percentile: p}, i} ->
        x = if count > 1, do: Float.round(i / (count - 1) * width, 2), else: 0.0
        y = Float.round(height - max(0.0, min(height, p / 100 * height)) * 1.0, 2)
        "#{x},#{y}"
      end)

    assigns = assign(assigns, :coords, coords) |> assign(:width, width) |> assign(:height, height)

    ~H"""
    <div>
      <svg
        viewBox={"0 0 #{@width} #{@height}"}
        class="w-full h-14 text-[#4CD964]"
        preserveAspectRatio="none"
        aria-label={gettext("Weekly percentile trend")}
      >
        <polyline
          points={@coords}
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linejoin="round"
          stroke-linecap="round"
        />
      </svg>
      <div class="mt-1 flex justify-between text-[10px] text-gray-400">
        <span :for={point <- @history}>{point.percentile}</span>
      </div>
    </div>
    """
  end
end
