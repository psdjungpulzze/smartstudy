defmodule FunSheepWeb.StudentLive.Shared.PeerComparison do
  @moduledoc """
  Shared anonymised peer-comparison card (spec §6.3).

  Accepts the result of `Assessments.cohort_percentile_bands/2` and
  renders 25 / 50 / 75 / 90th-percentile bands with the student's
  position marked. For cohorts smaller than the spec's threshold, we
  render a "small cohort — comparison hidden" message instead of
  forging a ranking.

  Strict rule: **never render named peers**. The component only receives
  aggregate bands plus the student's own readiness.
  """

  use FunSheepWeb, :html

  attr :bands, :map, required: true
  attr :student_readiness, :any, default: nil
  attr :class, :string, default: nil

  def card(assigns) do
    ~H"""
    <section class={["bg-white rounded-2xl border border-gray-100 p-4 sm:p-5", @class]}>
      <div class="mb-3">
        <h3 class="text-sm font-extrabold text-gray-900">
          {gettext("Peer comparison")}
        </h3>
        <p class="text-xs text-gray-500">
          {gettext("Same-grade, same-course students on FunSheep")}
        </p>
      </div>

      <%= case @bands do %>
        <% %{status: :small_cohort, size: size} -> %>
          <p class="text-sm text-gray-500 py-3">
            {small_cohort_copy(size)}
          </p>
        <% %{status: :ok} = b -> %>
          <.bands bands={b} student_readiness={@student_readiness} />
        <% _ -> %>
          <p class="text-sm text-gray-500 py-3">
            {gettext("Peer comparison isn't ready yet.")}
          </p>
      <% end %>
    </section>
    """
  end

  attr :bands, :map, required: true
  attr :student_readiness, :any, required: true

  defp bands(assigns) do
    mine = assigns.student_readiness

    mine_band =
      cond do
        mine == nil -> nil
        mine >= assigns.bands.p90 -> "p90"
        mine >= assigns.bands.p75 -> "p75"
        mine >= assigns.bands.p50 -> "p50"
        mine >= assigns.bands.p25 -> "p25"
        true -> "below"
      end

    assigns = assign(assigns, :mine_band, mine_band)

    ~H"""
    <div class="space-y-3">
      <div class="grid grid-cols-4 gap-2">
        <.band label={gettext("P25")} value={@bands.p25} highlight={@mine_band == "p25"} />
        <.band label={gettext("P50")} value={@bands.p50} highlight={@mine_band == "p50"} />
        <.band label={gettext("P75")} value={@bands.p75} highlight={@mine_band == "p75"} />
        <.band label={gettext("P90")} value={@bands.p90} highlight={@mine_band == "p90"} />
      </div>
      <p class="text-[11px] text-gray-400">
        {gettext("Cohort: %{n} students", n: @bands.size)}
      </p>
      <p :if={@student_readiness} class="text-sm text-gray-700">
        {mine_copy(@mine_band, @student_readiness)}
      </p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :float, required: true
  attr :highlight, :boolean, default: false

  defp band(assigns) do
    ~H"""
    <div class={[
      "rounded-xl p-3 text-center border",
      if(@highlight,
        do: "bg-[#E8F8EB] border-[#4CD964]",
        else: "bg-gray-50 border-gray-100"
      )
    ]}>
      <p class="text-[10px] font-bold text-gray-500 uppercase tracking-wider">{@label}</p>
      <p class="text-base font-extrabold text-gray-900">{round(@value)}</p>
    </div>
    """
  end

  defp small_cohort_copy(size) do
    gettext("Small cohort (%{n} students) — comparison hidden until we have more data.", n: size)
  end

  defp mine_copy("p90", score),
    do: gettext("At %{score}% readiness, your student is in the top 10%.", score: round(score))

  defp mine_copy("p75", score),
    do: gettext("At %{score}% readiness, your student is in the top 25%.", score: round(score))

  defp mine_copy("p50", score),
    do: gettext("At %{score}% readiness, your student is above the median.", score: round(score))

  defp mine_copy("p25", score),
    do:
      gettext("At %{score}% readiness, your student is above the lower quartile.",
        score: round(score)
      )

  defp mine_copy("below", score),
    do:
      gettext("At %{score}% readiness, there's room to grow — the next band is within reach.",
        score: round(score)
      )

  defp mine_copy(_, _), do: ""
end
