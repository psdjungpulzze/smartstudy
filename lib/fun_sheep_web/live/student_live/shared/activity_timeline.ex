defmodule FunSheepWeb.StudentLive.Shared.ActivityTimeline do
  @moduledoc """
  Shared activity-timeline component (spec §5.1).

  Lives in the `FunSheepWeb.StudentLive.Shared` namespace so both Parent
  and (future) Teacher surfaces can import it. Pure function component —
  stateless, reusable. Callers pass real data; this module never
  fabricates rows.
  """

  use FunSheepWeb, :html

  alias FunSheep.Engagement.StudySession

  attr :sessions, :list, required: true, doc: "Preloaded %StudySession{} structs"
  attr :student_name, :string, default: nil
  attr :class, :string, default: nil

  @doc """
  Renders a scrollable, day-grouped timeline of real study sessions.

  When fewer than 3 sessions are present we render the honest empty
  state called for in spec §5.1 — we never fill with fake rows.
  """
  def timeline(assigns) do
    assigns =
      assigns
      |> assign(:days, group_by_day(assigns.sessions))
      |> assign(:empty?, length(assigns.sessions) < 3)
      |> assign(:rolling_accuracy, rolling_accuracy(assigns.sessions))
      |> assign(:median_duration, median_duration(assigns.sessions))

    ~H"""
    <section class={["bg-white rounded-2xl border border-gray-100 p-4 sm:p-5", @class]}>
      <div class="flex items-center justify-between mb-4">
        <div>
          <h3 class="text-sm font-extrabold text-gray-900">
            {gettext("Recent activity")}
          </h3>
          <p class="text-xs text-gray-500">
            {gettext("Last 30 days of study sessions")}
          </p>
        </div>
      </div>

      <div :if={@empty?} class="py-6 text-center">
        <p class="text-sm text-gray-500">
          {gettext("Not enough activity yet — encourage your student to start a practice session.")}
        </p>
      </div>

      <ol :if={!@empty?} class="space-y-4">
        <li :for={{day, sessions} <- @days}>
          <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider mb-2">
            {format_day(day)}
          </p>
          <ul class="space-y-2">
            <.session_row
              :for={session <- sessions}
              session={session}
              rolling_accuracy={@rolling_accuracy}
              median_duration={@median_duration}
            />
          </ul>
        </li>
      </ol>
    </section>
    """
  end

  attr :session, :any, required: true
  attr :rolling_accuracy, :any, required: true
  attr :median_duration, :any, required: true

  defp session_row(assigns) do
    assigns =
      assigns
      |> assign(:accuracy, session_accuracy(assigns.session))
      |> assign(
        :interpretation,
        interpretation(assigns.session, assigns.rolling_accuracy, assigns.median_duration)
      )

    ~H"""
    <li class="rounded-xl border border-gray-100 p-3 bg-gray-50/50">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0 flex-1">
          <div class="flex flex-wrap items-center gap-2">
            <span class={[
              "text-[10px] font-bold px-2 py-0.5 rounded-full",
              window_pill_color(@session.time_window)
            ]}>
              {format_window(@session.time_window)}
            </span>
            <span class="text-[10px] text-gray-400">
              {format_time(@session.completed_at)}
            </span>
            <span class="text-[10px] text-gray-400">
              · {format_duration(@session.duration_seconds)}
            </span>
          </div>
          <p class="text-sm font-bold text-gray-900 mt-1 truncate">
            {session_label(@session)}
          </p>
          <p class="text-xs text-gray-500 mt-0.5">
            {@session.questions_correct}/{@session.questions_attempted} {gettext("correct")}
            <span :if={@accuracy}>· {@accuracy}%</span>
            <span :if={@session.xp_earned && @session.xp_earned > 0}>
              · {@session.xp_earned} XP
            </span>
          </p>
          <p class="text-xs text-gray-600 mt-1 italic">
            {@interpretation}
          </p>
        </div>
      </div>
    </li>
    """
  end

  ## ── Interpretation (spec §5.1) ──────────────────────────────────────────

  @doc """
  Returns a short, real interpretation line for a study session based on
  its accuracy vs. the student's rolling accuracy and its duration vs.
  median. Exported so callers/tests can verify behaviour without rendering.
  """
  def interpretation(%StudySession{} = session, rolling_accuracy, median_duration) do
    accuracy = session_accuracy(session)
    duration = session.duration_seconds || 0

    interpret_relative(accuracy, rolling_accuracy) ||
      interpret_duration(duration, median_duration) ||
      interpret_absolute(accuracy)
  end

  def interpretation(_, _, _), do: gettext("Session recorded.")

  defp interpret_relative(nil, _), do: gettext("No questions attempted in this session.")

  defp interpret_relative(accuracy, rolling) when is_number(rolling) do
    cond do
      accuracy >= rolling + 10 ->
        gettext("Strong — above their usual accuracy.")

      accuracy <= rolling - 10 ->
        gettext("Below their usual accuracy — worth a supportive check-in.")

      true ->
        nil
    end
  end

  defp interpret_relative(_accuracy, _rolling), do: nil

  defp interpret_duration(duration, median) when is_integer(median) and median > 0 do
    if duration < max(div(median, 2), 180) do
      gettext("Short session — consider a longer block next time.")
    end
  end

  defp interpret_duration(_, _), do: nil

  defp interpret_absolute(accuracy) when is_number(accuracy) do
    cond do
      accuracy >= 90 -> gettext("Excellent accuracy for this session.")
      accuracy >= 70 -> gettext("Solid session.")
      true -> gettext("Mixed result — accuracy is still building.")
    end
  end

  defp interpret_absolute(_), do: gettext("Session recorded.")

  ## ── Grouping / Formatting ───────────────────────────────────────────────

  defp group_by_day(sessions) do
    sessions
    |> Enum.group_by(fn s ->
      case s.completed_at do
        %DateTime{} = dt -> DateTime.to_date(dt)
        _ -> Date.utc_today()
      end
    end)
    |> Enum.sort_by(fn {day, _} -> day end, {:desc, Date})
  end

  defp format_day(%Date{} = day) do
    today = Date.utc_today()
    diff = Date.diff(today, day)

    cond do
      diff == 0 -> gettext("Today")
      diff == 1 -> gettext("Yesterday")
      diff < 7 -> Date.to_string(day)
      true -> Date.to_string(day)
    end
  end

  defp format_time(%DateTime{} = dt) do
    dt
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.slice(0..4)
  end

  defp format_time(_), do: "--:--"

  defp format_duration(nil), do: gettext("0 min")
  defp format_duration(s) when s < 60, do: "#{s} s"
  defp format_duration(s), do: "#{div(s, 60)} min"

  defp format_window("morning"), do: gettext("Morning")
  defp format_window("afternoon"), do: gettext("Afternoon")
  defp format_window("evening"), do: gettext("Evening")
  defp format_window("night"), do: gettext("Late night")
  defp format_window(_), do: gettext("Session")

  defp window_pill_color("morning"), do: "bg-amber-50 text-amber-700"
  defp window_pill_color("afternoon"), do: "bg-sky-50 text-sky-700"
  defp window_pill_color("evening"), do: "bg-indigo-50 text-indigo-700"
  defp window_pill_color("night"), do: "bg-slate-100 text-slate-700"
  defp window_pill_color(_), do: "bg-gray-100 text-gray-600"

  defp session_label(%StudySession{session_type: type, course: %{name: name}}),
    do: "#{session_type_label(type)} — #{name}"

  defp session_label(%StudySession{session_type: type}), do: session_type_label(type)

  defp session_type_label("review"), do: gettext("Review")
  defp session_type_label("practice"), do: gettext("Practice")
  defp session_type_label("assessment"), do: gettext("Assessment")
  defp session_type_label("quick_test"), do: gettext("Quick test")
  defp session_type_label("daily_challenge"), do: gettext("Daily challenge")
  defp session_type_label("just_this"), do: gettext("Focused study")
  defp session_type_label(other) when is_binary(other), do: other
  defp session_type_label(_), do: gettext("Study session")

  defp session_accuracy(%StudySession{questions_attempted: a, questions_correct: c})
       when is_integer(a) and a > 0 and is_integer(c) do
    Float.round(c / a * 100, 1)
  end

  defp session_accuracy(_), do: nil

  defp rolling_accuracy([]), do: nil

  defp rolling_accuracy(sessions) do
    attempted = sessions |> Enum.map(&(&1.questions_attempted || 0)) |> Enum.sum()
    correct = sessions |> Enum.map(&(&1.questions_correct || 0)) |> Enum.sum()
    if attempted > 0, do: Float.round(correct / attempted * 100, 1), else: nil
  end

  defp median_duration([]), do: nil

  defp median_duration(sessions) do
    durations =
      sessions |> Enum.map(&(&1.duration_seconds || 0)) |> Enum.filter(&(&1 > 0)) |> Enum.sort()

    case durations do
      [] -> nil
      ds -> Enum.at(ds, div(length(ds), 2))
    end
  end
end
