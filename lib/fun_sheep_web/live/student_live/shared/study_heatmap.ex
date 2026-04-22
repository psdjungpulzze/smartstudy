defmodule FunSheepWeb.StudentLive.Shared.StudyHeatmap do
  @moduledoc """
  Shared time-of-day heatmap component (spec §5.2).

  Renders a 4-band × 7-day grid. Cell intensity encodes minutes studied
  in that {day_of_week, window} bucket. Caller passes real, pre-aggregated
  data from `FunSheep.Engagement.StudySessions.study_heatmap/3` — this
  module never fabricates cells.
  """

  use FunSheepWeb, :html

  @windows ["morning", "afternoon", "evening", "night"]
  @days_of_week [1, 2, 3, 4, 5, 6, 7]

  attr :grid, :map, required: true, doc: "%{{dow, window} => minutes}"
  attr :class, :string, default: nil

  def heatmap(assigns) do
    max_minutes =
      case Map.values(assigns.grid) do
        [] -> 0
        values -> Enum.max(values)
      end

    assigns =
      assigns
      |> assign(:max_minutes, max_minutes)
      |> assign(:empty?, max_minutes == 0)
      |> assign(:windows, @windows)
      |> assign(:days, @days_of_week)

    ~H"""
    <section class={["bg-white rounded-2xl border border-gray-100 p-4 sm:p-5", @class]}>
      <div class="mb-3">
        <h3 class="text-sm font-extrabold text-gray-900">
          {gettext("When your student studies")}
        </h3>
        <p class="text-xs text-gray-500">
          {gettext("Minutes per day-of-week × time-of-day (last 4 weeks)")}
        </p>
      </div>

      <div :if={@empty?} class="py-6 text-center">
        <p class="text-sm text-gray-500">
          {gettext("No study sessions in the last four weeks yet.")}
        </p>
      </div>

      <div :if={!@empty?} class="-mx-2 overflow-x-auto pb-2">
        <table class="text-xs border-separate border-spacing-1 mx-auto">
          <thead>
            <tr>
              <th class="text-left text-[10px] font-bold text-gray-400 pr-2"></th>
              <th
                :for={day <- @days}
                class="text-[10px] font-bold text-gray-400 px-1 text-center w-8 sm:w-10"
              >
                {short_day_label(day)}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={window <- @windows}>
              <th class="text-[10px] font-bold text-gray-500 pr-2 text-left align-middle whitespace-nowrap">
                {window_label(window)}
              </th>
              <td :for={day <- @days} class="p-0">
                <.cell minutes={Map.get(@grid, {day, window}, 0)} max={@max_minutes} />
              </td>
            </tr>
          </tbody>
        </table>

        <p class="text-[10px] text-gray-400 mt-3">
          {gettext("Darker green = more minutes. Student local time.")}
        </p>
      </div>
    </section>
    """
  end

  attr :minutes, :integer, required: true
  attr :max, :integer, required: true

  defp cell(assigns) do
    intensity =
      if assigns.max == 0, do: 0, else: min(1.0, assigns.minutes / assigns.max)

    assigns = assign(assigns, :intensity, intensity)

    ~H"""
    <div
      class={[
        "w-8 h-8 sm:w-10 rounded-md flex items-center justify-center",
        cell_bg_class(@intensity)
      ]}
      title={"#{@minutes} min"}
    >
      <span
        :if={@minutes > 0}
        class={[
          "text-[10px] font-bold",
          if(@intensity >= 0.5, do: "text-white", else: "text-gray-700")
        ]}
      >
        {@minutes}
      </span>
    </div>
    """
  end

  defp cell_bg_class(intensity) when intensity <= 0, do: "bg-gray-100"

  defp cell_bg_class(intensity) do
    cond do
      intensity >= 0.8 -> "bg-[#4CD964]"
      intensity >= 0.6 -> "bg-[#76DF85]"
      intensity >= 0.4 -> "bg-[#A4E9AE]"
      intensity >= 0.2 -> "bg-[#CDF3D3]"
      intensity > 0 -> "bg-[#E8F8EB]"
      true -> "bg-gray-100"
    end
  end

  defp window_label("morning"), do: gettext("Morning")
  defp window_label("afternoon"), do: gettext("Afternoon")
  defp window_label("evening"), do: gettext("Evening")
  defp window_label("night"), do: gettext("Late night")
  defp window_label(other), do: other

  defp short_day_label(1), do: gettext("Mon")
  defp short_day_label(2), do: gettext("Tue")
  defp short_day_label(3), do: gettext("Wed")
  defp short_day_label(4), do: gettext("Thu")
  defp short_day_label(5), do: gettext("Fri")
  defp short_day_label(6), do: gettext("Sat")
  defp short_day_label(7), do: gettext("Sun")
end
