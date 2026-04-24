defmodule FunSheepWeb.StudentLive.Shared.TopicMasteryMap do
  @moduledoc """
  Shared topic-level mastery map (spec §5.3).

  Renders chapters → topics (sections) as clickable cells coloured by
  mastery. The parent LiveView is responsible for handling drill-down
  events (`phx-click="topic_drill"`) and rendering the modal. We include
  a helper `drill_modal/1` here so Parent and Teacher share the same
  modal look.
  """

  use FunSheepWeb, :html

  alias FunSheep.Questions.QuestionAttempt

  attr :grid, :list, required: true, doc: "Result of Assessments.topic_mastery_map/2"
  attr :test_name, :string, default: nil
  attr :class, :string, default: nil

  def mastery_map(assigns) do
    assigns = assign(assigns, :empty?, assigns.grid == [])

    ~H"""
    <section class={["bg-white rounded-2xl border border-gray-100 p-4 sm:p-5", @class]}>
      <div class="flex items-start justify-between gap-3 mb-3">
        <div>
          <h3 class="text-sm font-extrabold text-gray-900">
            {gettext("Topic mastery")}
          </h3>
          <p :if={@test_name} class="text-xs text-gray-500">
            {gettext("For")} {@test_name}
          </p>
        </div>
      </div>

      <div :if={@empty?} class="py-6 text-center">
        <p class="text-sm text-gray-500">
          {gettext("No upcoming test has chapter scope set yet.")}
        </p>
      </div>

      <div :if={!@empty?} class="space-y-4">
        <div :for={chapter <- @grid}>
          <p class="text-[11px] font-bold text-gray-700 uppercase tracking-wider mb-2">
            {chapter.chapter_name}
          </p>
          <div :if={chapter.topics == []} class="text-[11px] text-gray-400">
            {gettext("No concepts tagged yet.")}
          </div>
          <div :if={chapter.topics != []} class="grid grid-cols-2 sm:grid-cols-3 gap-2">
            <button
              :for={topic <- chapter.topics}
              type="button"
              phx-click="topic_drill"
              phx-value-section-id={topic.section_id}
              class={[
                "text-left rounded-xl px-3 py-2 border transition-colors",
                topic_cell_classes(topic.status)
              ]}
              title={"#{topic.attempts_count} attempts"}
            >
              <p class="text-xs font-bold truncate">{topic.section_name}</p>
              <p class="text-[10px] opacity-80 mt-0.5">
                <%= if topic.attempts_count > 0 do %>
                  {round(topic.accuracy)}% · {topic.attempts_count} {gettext("attempts")}
                <% else %>
                  {gettext("No attempts yet")}
                <% end %>
              </p>
            </button>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :topic_name, :string, required: true
  attr :chapter_name, :string, default: nil

  attr :attempts, :list,
    required: true,
    doc: "Recent %QuestionAttempt{} structs, question preloaded"

  attr :trend, :list, required: true, doc: "Daily accuracy trend buckets"

  attr :assign_enabled?, :boolean,
    default: false,
    doc: "Whether the 'Assign 10 practice' CTA should be clickable (Phase 3 wires it up)"

  attr :on_close, :string, default: "close_topic_drill"

  def drill_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4 bg-black/40"
      phx-click={@on_close}
      phx-window-keydown={@on_close}
      phx-key="Escape"
    >
      <div
        class="bg-white w-full sm:max-w-lg rounded-t-2xl sm:rounded-2xl shadow-xl max-h-[90vh] overflow-hidden flex flex-col"
        phx-click-away={@on_close}
        onclick="event.stopPropagation()"
      >
        <header class="flex items-start justify-between px-5 py-4 border-b border-gray-100">
          <div class="min-w-0">
            <p :if={@chapter_name} class="text-[10px] text-gray-400 uppercase tracking-wider">
              {@chapter_name}
            </p>
            <h3 class="text-base font-extrabold text-gray-900 truncate">
              {@topic_name}
            </h3>
          </div>
          <button
            type="button"
            phx-click={@on_close}
            class="shrink-0 w-8 h-8 rounded-full bg-gray-100 hover:bg-gray-200 flex items-center justify-center"
            aria-label={gettext("Close")}
          >
            <span class="text-gray-600 text-sm">×</span>
          </button>
        </header>

        <div class="overflow-y-auto p-5 space-y-5">
          <div>
            <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider mb-2">
              {gettext("Accuracy trend (last 30 days)")}
            </p>
            <div :if={@trend == []} class="text-sm text-gray-500">
              {gettext("Not enough attempts in the last 30 days yet.")}
            </div>
            <.trend_sparkline :if={@trend != []} points={@trend} />
          </div>

          <div>
            <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider mb-2">
              {gettext("Recent attempts")}
            </p>
            <div :if={@attempts == []} class="text-sm text-gray-500">
              {gettext("No recent attempts on this topic.")}
            </div>
            <ul :if={@attempts != []} class="space-y-2">
              <.attempt_row :for={attempt <- @attempts} attempt={attempt} />
            </ul>
          </div>
        </div>

        <footer class="px-5 py-4 border-t border-gray-100 flex items-center justify-between gap-3">
          <p class="text-[11px] text-gray-400">
            {gettext("Student-side results are shown here too.")}
          </p>
          <button
            type="button"
            phx-click="assign_topic_practice"
            phx-value-topic-name={@topic_name}
            disabled={!@assign_enabled?}
            class={[
              "text-xs font-bold px-4 py-2 rounded-full shadow-md transition-colors",
              if(@assign_enabled?,
                do: "bg-[#4CD964] text-white hover:bg-[#3DBF55]",
                else: "bg-gray-100 text-gray-400 cursor-not-allowed"
              )
            ]}
            title={
              if @assign_enabled?,
                do: gettext("Assign 10 practice questions"),
                else: gettext("Assigning practice will arrive with parent goals (Phase 3).")
            }
          >
            {gettext("Assign 10 practice questions")}
          </button>
        </footer>
      </div>
    </div>
    """
  end

  attr :attempt, :any, required: true

  defp attempt_row(assigns) do
    ~H"""
    <li class="rounded-xl border border-gray-100 p-3">
      <div class="flex items-start justify-between gap-3">
        <p class="text-xs text-gray-700 line-clamp-2">
          {attempt_preview(@attempt)}
        </p>
        <span class={[
          "text-[10px] font-bold px-2 py-0.5 rounded-full shrink-0",
          attempt_status_classes(@attempt)
        ]}>
          {attempt_status_label(@attempt)}
        </span>
      </div>
      <p class="text-[10px] text-gray-400 mt-1">
        {format_time_taken(@attempt)} · {format_date(@attempt.inserted_at)}
      </p>
    </li>
    """
  end

  attr :points, :list, required: true

  defp trend_sparkline(assigns) do
    points = assigns.points
    max_acc = points |> Enum.map(& &1.accuracy) |> Enum.max(fn -> 100.0 end)
    width = 320.0
    height = 48.0
    count = length(points)

    coords =
      points
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {%{accuracy: acc}, i} ->
        x = if count > 1, do: Float.round(i / (count - 1) * width, 2), else: 0.0
        ratio = acc / max(max_acc, 1) * height
        y_raw = height - max(0.0, min(height, ratio * 1.0))
        "#{x},#{Float.round(y_raw * 1.0, 2)}"
      end)

    assigns =
      assigns
      |> assign(:coords, coords)
      |> assign(:width, width)
      |> assign(:height, height)

    ~H"""
    <svg
      viewBox={"0 0 #{@width} #{@height}"}
      class="w-full h-12 text-[#4CD964]"
      preserveAspectRatio="none"
      aria-label={gettext("Accuracy trend sparkline")}
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
    """
  end

  ## ── Helpers ─────────────────────────────────────────────────────────────

  defp topic_cell_classes(:mastered),
    do: "bg-[#E8F8EB] border-[#4CD964] text-[#256029] hover:bg-[#CDF3D3]"

  defp topic_cell_classes(:probing),
    do: "bg-amber-50 border-amber-200 text-amber-900 hover:bg-amber-100"

  defp topic_cell_classes(:weak),
    do: "bg-red-50 border-[#FF3B30]/50 text-[#B1261F] hover:bg-red-100"

  defp topic_cell_classes(:insufficient_data),
    do: "bg-gray-50 border-gray-200 text-gray-500 hover:bg-gray-100"

  defp topic_cell_classes(_), do: "bg-gray-50 border-gray-200 text-gray-500"

  defp attempt_preview(%QuestionAttempt{question: %{content: content}}) when is_binary(content) do
    content
    |> String.slice(0..119)
    |> String.trim()
  end

  defp attempt_preview(_), do: "—"

  defp attempt_status_classes(%QuestionAttempt{is_correct: true}),
    do: "bg-[#E8F8EB] text-[#256029]"

  defp attempt_status_classes(%QuestionAttempt{is_correct: false}),
    do: "bg-red-50 text-[#B1261F]"

  defp attempt_status_label(%QuestionAttempt{is_correct: true}), do: gettext("Correct")
  defp attempt_status_label(%QuestionAttempt{is_correct: false}), do: gettext("Missed")

  defp format_time_taken(%QuestionAttempt{time_taken_seconds: secs})
       when is_integer(secs) and secs > 0 do
    if secs < 60, do: "#{secs}s", else: "#{div(secs, 60)}m #{rem(secs, 60)}s"
  end

  defp format_time_taken(_), do: "—"

  defp format_date(%DateTime{} = dt), do: dt |> DateTime.to_date() |> Date.to_string()
  defp format_date(_), do: ""
end
