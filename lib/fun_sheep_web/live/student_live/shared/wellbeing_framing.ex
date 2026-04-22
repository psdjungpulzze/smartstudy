defmodule FunSheepWeb.StudentLive.Shared.WellbeingFraming do
  @moduledoc """
  Wellbeing-aware framing helpers (spec §5.4).

  The parent dashboard calls `Engagement.Wellbeing.classify/1` to get a
  signal atom, then uses the helpers here to:

    * decide whether to `dampen_competitive?` (hide percentile / rank)
    * render a supportive framing banner (`framing_banner/1`) when the
      signal suggests the parent would do more harm than good by
      doubling down on competitive pressure

  Per design principle #6, the signal itself is **never rendered as a
  number**. It only selects which copy to show.
  """

  use FunSheepWeb, :html

  @doc """
  True when the parent UI should dampen competitive framing (hide
  percentile, rank, peer-comparison) for this signal.
  """
  def dampen_competitive?(:under_pressure), do: true
  def dampen_competitive?(:disengaged), do: true
  def dampen_competitive?(_), do: false

  attr :signal, :atom,
    required: true,
    values: [:thriving, :steady, :under_pressure, :disengaged, :insufficient_data]

  attr :student_name, :string, default: nil
  attr :class, :string, default: nil

  @doc """
  Renders a supportive-framing banner. For `:under_pressure` and
  `:disengaged` we surface the supportive-conversation prompt from
  spec §5.4; for `:thriving` we celebrate without judgement; for
  `:steady` / `:insufficient_data` we render nothing (the dashboard's
  default copy stands).
  """
  def framing_banner(%{signal: :under_pressure} = assigns) do
    ~H"""
    <aside class={[
      "rounded-2xl border border-amber-200 bg-amber-50 p-4 sm:p-5",
      @class
    ]}>
      <p class="text-[11px] font-bold text-amber-800 uppercase tracking-wider mb-1">
        {gettext("Support signal")}
      </p>
      <p class="text-sm text-amber-900 font-semibold leading-snug">
        {gettext(
          "Your student has been studying longer but accuracy is dipping — often a sign of fatigue. A non-academic check-in may help more than extra practice this week."
        )}
      </p>
    </aside>
    """
  end

  def framing_banner(%{signal: :disengaged} = assigns) do
    ~H"""
    <aside class={[
      "rounded-2xl border border-sky-200 bg-sky-50 p-4 sm:p-5",
      @class
    ]}>
      <p class="text-[11px] font-bold text-sky-800 uppercase tracking-wider mb-1">
        {gettext("Getting back on track")}
      </p>
      <p class="text-sm text-sky-900 font-semibold leading-snug">
        {gettext(
          "Short 15-minute sessions tend to restart momentum better than a long one — you could suggest one today."
        )}
      </p>
    </aside>
    """
  end

  def framing_banner(%{signal: :thriving} = assigns) do
    ~H"""
    <aside class={[
      "rounded-2xl border border-[#A4E9AE] bg-[#E8F8EB] p-4 sm:p-5",
      @class
    ]}>
      <p class="text-[11px] font-bold text-[#256029] uppercase tracking-wider mb-1">
        {gettext("Going strong")}
      </p>
      <p class="text-sm text-[#256029] font-semibold leading-snug">
        {gettext(
          "Consistent sessions across the day and steady accuracy — a great time to celebrate effort, not just outcomes."
        )}
      </p>
    </aside>
    """
  end

  def framing_banner(assigns) do
    ~H"""
    <div></div>
    """
  end
end
