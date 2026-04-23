defmodule FunSheepWeb.ProgressPanel do
  @moduledoc """
  Live progress panel for long-running user-triggered operations.

  Pairs with `FunSheep.Progress` broadcasts. Caller passes an ordered list of
  `%FunSheep.Progress.Event{}` (typically one per chapter/subject being
  processed) and this component renders named phases, per-item counts, and
  terminal states.

  See `.claude/rules/i/progress-feedback.md` for the contract this
  component enforces.
  """
  use Phoenix.Component

  import FunSheepWeb.CoreComponents, only: [icon: 1]

  alias FunSheep.Progress.Event

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :events, :list, required: true, doc: "list of %Progress.Event{}"
  attr :class, :string, default: ""

  def panel(assigns) do
    total = length(assigns.events)

    succeeded =
      Enum.count(assigns.events, fn %Event{status: s} -> s == :succeeded end)

    failed =
      Enum.count(assigns.events, fn %Event{status: s} -> s == :failed end)

    all_terminal = total > 0 and succeeded + failed == total

    assigns =
      assigns
      |> assign(total: total, succeeded: succeeded, failed: failed, all_terminal: all_terminal)

    ~H"""
    <div class={["bg-white rounded-2xl shadow-md p-6 border border-[#E5E5EA]", @class]}>
      <div class="flex items-start justify-between mb-4">
        <div>
          <h3 class="text-base font-semibold text-[#1C1C1E]">{@title}</h3>
          <p :if={@subtitle} class="text-sm text-[#8E8E93] mt-1">{@subtitle}</p>
        </div>
        <div class="text-xs text-[#8E8E93] whitespace-nowrap">
          <%= cond do %>
            <% @all_terminal and @failed == 0 -> %>
              <span class="text-[#4CD964] font-medium">All complete</span>
            <% @all_terminal -> %>
              <span class="text-[#FF3B30] font-medium">
                {@failed} failed · {@succeeded} ready
              </span>
            <% true -> %>
              <span>{@succeeded + @failed} of {@total} done</span>
          <% end %>
        </div>
      </div>

      <ul class="space-y-3">
        <.row :for={event <- @events} event={event} />
      </ul>
    </div>
    """
  end

  attr :event, :map, required: true

  defp row(assigns) do
    ~H"""
    <li class={[
      "rounded-xl border p-4 transition-colors",
      row_border(@event)
    ]}>
      <div class="flex items-start gap-3">
        <div class="flex-shrink-0 mt-0.5">
          <.status_icon status={@event.status} />
        </div>

        <div class="flex-1 min-w-0">
          <div class="flex items-baseline justify-between gap-3">
            <p class="font-medium text-[#1C1C1E] truncate">
              {@event.subject_label || "(unnamed)"}
            </p>
            <span
              :if={@event.status in [:running, :queued]}
              class="text-xs text-[#8E8E93] whitespace-nowrap"
            >
              Step {@event.phase_index} of {@event.phase_total}
            </span>
          </div>

          <p class="text-sm text-[#8E8E93] mt-1">
            {phase_description(@event)}
          </p>

          <.progress_bar
            :if={show_bar?(@event)}
            current={@event.progress.current}
            total={@event.progress.total}
            unit={@event.progress.unit}
          />

          <p
            :if={@event.status == :failed and @event.error}
            class="text-sm text-[#FF3B30] mt-2"
          >
            {@event.error.message}
          </p>
        </div>
      </div>
    </li>
    """
  end

  attr :status, :atom, required: true

  defp status_icon(%{status: :succeeded} = assigns) do
    ~H"""
    <.icon name="hero-check-circle-solid" class="w-5 h-5 text-[#4CD964]" />
    """
  end

  defp status_icon(%{status: :failed} = assigns) do
    ~H"""
    <.icon name="hero-x-circle-solid" class="w-5 h-5 text-[#FF3B30]" />
    """
  end

  defp status_icon(%{status: :queued} = assigns) do
    ~H"""
    <.icon name="hero-clock" class="w-5 h-5 text-[#8E8E93]" />
    """
  end

  defp status_icon(assigns) do
    # :running — animated spinner
    ~H"""
    <svg
      class="w-5 h-5 text-[#4CD964] animate-spin"
      fill="none"
      viewBox="0 0 24 24"
      aria-hidden="true"
    >
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="3" />
      <path
        class="opacity-75"
        fill="currentColor"
        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
      />
    </svg>
    """
  end

  attr :current, :integer, required: true
  attr :total, :any, required: true
  attr :unit, :string, required: true

  defp progress_bar(assigns) do
    pct =
      cond do
        is_integer(assigns.total) and assigns.total > 0 ->
          trunc(assigns.current / assigns.total * 100)

        true ->
          0
      end

    assigns = assign(assigns, pct: pct)

    ~H"""
    <div class="mt-2">
      <div class="flex justify-between text-xs text-[#8E8E93] mb-1">
        <span>{@current} of {@total} {@unit}</span>
        <span>{@pct}%</span>
      </div>
      <div class="w-full bg-[#F5F5F7] rounded-full h-1.5 overflow-hidden">
        <div
          class="bg-[#4CD964] h-full rounded-full transition-all duration-300"
          style={"width: #{@pct}%"}
        />
      </div>
    </div>
    """
  end

  defp show_bar?(%Event{status: :running, progress: %{total: total}})
       when is_integer(total) and total > 0,
       do: true

  defp show_bar?(_), do: false

  defp phase_description(%Event{status: :succeeded, progress: %{current: n, unit: unit}}),
    do: "#{n} #{unit} ready"

  defp phase_description(%Event{status: :failed}),
    do: "Generation failed"

  defp phase_description(%Event{status: :queued}),
    do: "Waiting to start..."

  defp phase_description(%Event{phase_label: label, detail: detail}) when is_binary(detail),
    do: "#{label} — #{detail}"

  defp phase_description(%Event{phase_label: label}),
    do: label

  defp row_border(%Event{status: :succeeded}), do: "border-[#4CD964]/30 bg-[#E8F8EB]/40"
  defp row_border(%Event{status: :failed}), do: "border-[#FF3B30]/30 bg-red-50"
  defp row_border(%Event{status: :running}), do: "border-[#4CD964]/30"
  defp row_border(_), do: "border-[#E5E5EA]"
end
