defmodule FunSheepWeb.StudentLive.Shared.ForecastCard do
  @moduledoc """
  Shared readiness-forecast card (spec §6.2).

  Accepts a `forecast` map as returned by
  `FunSheep.Assessments.Forecaster.forecast/2` and renders either:

    * the projection + gap-to-target + suggested daily-minute delta, or
    * an honest empty-state card explaining what's missing (no target set,
      not enough history, test already in the past, etc.).

  Per spec §6.2, copy always frames the delta as a *behaviour suggestion*,
  never a judgement.
  """

  use FunSheepWeb, :html

  attr :forecast, :map, required: true
  attr :class, :string, default: nil

  def card(assigns) do
    ~H"""
    <section class={["bg-white rounded-2xl border border-gray-100 p-4 sm:p-5", @class]}>
      <div class="mb-3">
        <h3 class="text-sm font-extrabold text-gray-900">
          {gettext("Forecast")}
        </h3>
        <p class="text-xs text-gray-500">
          {gettext("At current pace — a product signal, not a guarantee")}
        </p>
      </div>

      <%= case @forecast do %>
        <% %{status: :ok} = f -> %>
          <.projection forecast={f} />
        <% %{status: :insufficient_data, reason: reason} -> %>
          <p class="text-sm text-gray-500 py-3">
            {reason_copy(reason)}
          </p>
        <% _ -> %>
          <p class="text-sm text-gray-500 py-3">
            {gettext("Forecast not available yet.")}
          </p>
      <% end %>
    </section>
    """
  end

  attr :forecast, :map, required: true

  defp projection(assigns) do
    f = assigns.forecast

    gap_copy =
      cond do
        f.gap <= 0 ->
          gettext("On track to hit the target.")

        f.minutes_delta <= 0 ->
          gettext("A small daily push would close the gap.")

        true ->
          gettext("Roughly %{min} more min/day would close the gap.", min: f.minutes_delta)
      end

    assigns = assign(assigns, :gap_copy, gap_copy)

    ~H"""
    <div class="space-y-3">
      <div class="flex items-baseline gap-3">
        <p class="text-3xl font-extrabold text-[#4CD964]">{@forecast.projected_readiness}%</p>
        <p class="text-sm text-gray-500">
          {gettext("projected for test day")}
        </p>
      </div>

      <div class="grid grid-cols-3 gap-3">
        <div class="rounded-xl bg-gray-50 border border-gray-100 p-3">
          <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider">
            {gettext("Target")}
          </p>
          <p class="text-base font-extrabold text-gray-900">{@forecast.target}%</p>
        </div>
        <div class="rounded-xl bg-gray-50 border border-gray-100 p-3">
          <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider">
            {gettext("Gap")}
          </p>
          <p class={[
            "text-base font-extrabold",
            if(@forecast.gap > 0, do: "text-amber-600", else: "text-[#4CD964]")
          ]}>
            {format_gap(@forecast.gap)}
          </p>
        </div>
        <div class="rounded-xl bg-gray-50 border border-gray-100 p-3">
          <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider">
            {gettext("Days left")}
          </p>
          <p class="text-base font-extrabold text-gray-900">{@forecast.days_to_test}</p>
        </div>
      </div>

      <p class="text-sm text-gray-700">{@gap_copy}</p>

      <p class="text-[11px] text-gray-400">
        {confidence_copy(@forecast.confidence)} · {gettext("%{d} days of readiness history",
          d: @forecast.history_days
        )}
      </p>
    </div>
    """
  end

  defp format_gap(gap) when gap > 0, do: "+#{gap}"
  defp format_gap(gap), do: "#{gap}"

  defp confidence_copy(:tight),
    do: gettext("Tight range — based on several weeks of consistent practice.")

  defp confidence_copy(:wide_range),
    do: gettext("Wide range — not enough history yet for a tight forecast.")

  defp confidence_copy(_), do: ""

  defp reason_copy(:no_target),
    do: gettext("Set a target score to see a forecast.")

  defp reason_copy(:no_readiness_history),
    do: gettext("Run an assessment once to unlock the forecast.")

  defp reason_copy(:single_snapshot),
    do: gettext("One readiness point so far — we need a little more history.")

  defp reason_copy(:short_history),
    do: gettext("Fewer than two weeks of history — the forecast will firm up with time.")

  defp reason_copy(:test_in_past), do: gettext("The test date has already passed.")

  defp reason_copy(:no_schedule), do: gettext("No upcoming test to forecast against.")

  defp reason_copy(_), do: gettext("Forecast not available yet.")
end
