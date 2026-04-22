defmodule FunSheepWeb.ParentDashboardLive do
  use FunSheepWeb, :live_view

  import FunSheepWeb.SheepMascot

  alias FunSheep.{Accounts, Assessments, Gamification}
  alias FunSheep.Engagement.StudySessions
  alias FunSheep.Courses

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {students, user_role} =
      case Accounts.get_user_role_by_interactor_id(user["interactor_user_id"]) do
        nil ->
          {[], nil}

        ur ->
          links = Accounts.list_students_for_guardian(ur.id)
          enriched = Enum.map(links, fn sg -> enrich_student(sg.student) end)
          {enriched, ur}
      end

    selected_id =
      case students do
        [first | _] -> first.id
        [] -> nil
      end

    socket =
      socket
      |> assign(
        page_title: "Parent Dashboard",
        user_role: user_role,
        students: students,
        selected_id: selected_id,
        shared_student_id: nil
      )
      |> FunSheepWeb.LiveHelpers.assign_tutorial(
        key: "parent_dashboard",
        title: "Welcome, grown-up!",
        subtitle: "Here's what you can do from the parent dashboard.",
        steps: [
          %{
            emoji: "👋",
            title: "Link a student",
            body: "Add your child via Guardians to see their progress."
          },
          %{
            emoji: "📊",
            title: "Track readiness",
            body: "See upcoming tests and how prepared each student is."
          },
          %{
            emoji: "💬",
            title: "Share progress",
            body: "Celebrate wins — share a proof card with family or teachers."
          }
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("select_student", %{"id" => id}, socket) do
    {:noreply, assign(socket, selected_id: id)}
  end

  @impl true
  def handle_event("share_progress", %{"id" => student_id}, socket) do
    {:noreply, assign(socket, shared_student_id: student_id)}
  end

  # ── Data Loading ──────────────────────────────────────────────────────────

  defp enrich_student(student) do
    student_id = student.id

    # Upcoming tests + readiness
    upcoming = Assessments.list_upcoming_schedules(student_id, 90)
    primary_test = List.first(upcoming)

    {readiness_score, readiness_trend, percentile, test_name, course_name, weakest_area,
     previous_score} =
      if primary_test do
        readiness = Assessments.latest_readiness(student_id, primary_test.id)
        trend = Assessments.readiness_trend(student_id, primary_test.id)
        pctile = Assessments.readiness_percentile(student_id, primary_test.id)

        score = if readiness, do: round(readiness.aggregate_score), else: nil

        # Find weakest chapter from readiness breakdown
        weak = weakest_chapter(readiness, primary_test)

        # Get previous score for proof card comparison
        prev = previous_readiness_score(trend)

        {score, trend, pctile, primary_test.name,
         if(primary_test.course, do: primary_test.course.name, else: "Test Prep"), weak, prev}
      else
        {nil, %{direction: :none, change: 0, scores: []}, nil, nil, nil, nil, nil}
      end

    # Activity summary
    activity = StudySessions.parent_activity_summary(student_id)

    # Gamification
    gam = Gamification.dashboard_summary(student_id)

    %{
      id: student_id,
      name: student.display_name || student.email,
      grade: student.grade,
      readiness_score: readiness_score,
      readiness_trend: readiness_trend,
      percentile: percentile,
      test_name: test_name,
      course_name: course_name,
      previous_score: previous_score,
      weakest_area: weakest_area,
      activity: activity,
      gamification: gam,
      upcoming_count: length(upcoming)
    }
  end

  defp weakest_chapter(nil, _schedule), do: nil

  defp weakest_chapter(readiness, schedule) do
    chapter_scores = readiness.chapter_scores || %{}

    if map_size(chapter_scores) == 0 do
      nil
    else
      chapter_ids = get_in(schedule.scope, ["chapter_ids"]) || Map.keys(chapter_scores)
      chapters = Courses.list_chapters_by_ids(chapter_ids)

      chapters
      |> Enum.map(fn ch ->
        score = Map.get(chapter_scores, ch.id, 0.0)
        %{name: ch.name, score: score}
      end)
      |> Enum.min_by(& &1.score, fn -> nil end)
      |> case do
        nil -> nil
        %{name: name} -> name
      end
    end
  end

  defp previous_readiness_score(%{scores: scores}) when length(scores) >= 2 do
    # Second-to-last score is the "before"
    scores
    |> Enum.reverse()
    |> Enum.at(1)
    |> case do
      %{score: s} -> round(s)
      _ -> nil
    end
  end

  defp previous_readiness_score(_), do: nil

  # ── Render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4 sm:space-y-6">
      <%!-- ── Header ── --%>
      <div class="animate-slide-up">
        <h1 class="text-xl sm:text-2xl font-extrabold text-gray-900">
          {greeting()}, {@current_user["display_name"]}
        </h1>
        <p class="text-gray-500 text-sm mt-0.5">
          Here's how your children are doing
        </p>
      </div>

      <%!-- ── Connected apps ── --%>
      <div class="animate-slide-up">
        <.link
          navigate={~p"/integrations"}
          class="block bg-white rounded-2xl border border-gray-100 p-5 hover:border-[#4CD964] transition-colors"
        >
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-lg bg-[#E8F8EB] flex items-center justify-center text-xl">
              🔗
            </div>
            <div class="flex-1">
              <h3 class="font-semibold text-gray-900 text-sm">
                School apps
              </h3>
              <p class="text-gray-500 text-xs">
                Auto-import your child's courses and tests.
              </p>
            </div>
            <span class="text-[#4CD964] text-xs font-medium">Manage →</span>
          </div>
        </.link>
      </div>

      <%!-- ── Empty State ── --%>
      <div :if={@students == []} class="animate-slide-up">
        <div class="bg-white rounded-2xl border border-gray-100 p-6 sm:p-8 text-center">
          <.sheep
            state={:encouraging}
            size="xl"
            wool_level={0}
            message="Invite your child to connect their account!"
          />
          <h3 class="font-extrabold text-gray-900 text-lg mt-4">
            No students linked yet
          </h3>
          <p class="text-gray-500 text-sm mt-1 mb-5 max-w-sm mx-auto">
            Connect your child's Fun Sheep account to see their study progress
            and celebrate their achievements together.
          </p>
          <.link
            navigate={~p"/guardians"}
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-bold px-6 py-3 sm:py-2.5 rounded-full shadow-md text-sm transition-colors touch-target inline-flex items-center justify-center"
          >
            Connect a Student
          </.link>
        </div>
      </div>

      <%!-- ── Student Tabs (if multiple) ── --%>
      <div :if={length(@students) > 1} class="flex gap-2 overflow-x-auto animate-slide-up">
        <button
          :for={student <- @students}
          phx-click="select_student"
          phx-value-id={student.id}
          class={[
            "px-4 py-2 rounded-full text-sm font-bold transition-colors shrink-0",
            if(student.id == @selected_id,
              do: "bg-[#4CD964] text-white shadow-md",
              else: "bg-white text-gray-600 border border-gray-200 hover:border-[#4CD964]"
            )
          ]}
        >
          {student.name}
        </button>
      </div>

      <%!-- ── Student Cards ── --%>
      <div :for={student <- @students} class="animate-slide-up">
        <div
          :if={student.id == @selected_id || length(@students) == 1}
          class="space-y-4"
        >
          <.student_card
            student={student}
            shared={@shared_student_id == student.id}
          />
        </div>
      </div>
    </div>
    """
  end

  # ── Student Card ──────────────────────────────────────────────────────────

  defp student_card(assigns) do
    ~H"""
    <div class="space-y-3">
      <%!-- ── Student Header ── --%>
      <div class="bg-white rounded-2xl border border-gray-100 p-4 sm:p-5">
        <div class="flex items-center justify-between gap-3">
          <div class="flex items-center gap-3 min-w-0">
            <.sheep
              state={@student.gamification.sheep_state}
              size="sm"
              wool_level={@student.gamification.streak.wool_level}
            />
            <div class="min-w-0">
              <div class="flex items-center gap-2">
                <h2 class="text-lg font-extrabold text-gray-900 truncate">
                  {@student.name}
                </h2>
                <span
                  :if={@student.gamification.streak.current_streak > 0}
                  class="text-sm"
                  title={"#{@student.gamification.streak.current_streak} day streak"}
                >
                  {"🔥 #{@student.gamification.streak.current_streak}"}
                </span>
              </div>
              <p :if={@student.grade} class="text-xs text-gray-400">
                Grade {@student.grade}
              </p>
            </div>
          </div>
          <div class="text-right shrink-0">
            <p class="text-xs text-gray-400">{@student.upcoming_count} upcoming tests</p>
          </div>
        </div>
      </div>

      <%!-- ── 4 Key Metrics (2x2 grid) ── --%>
      <div class="grid grid-cols-2 gap-3">
        <.readiness_metric
          score={@student.readiness_score}
          test_name={@student.test_name}
        />
        <.trend_metric trend={@student.readiness_trend} />
        <.activity_metric activity={@student.activity} />
        <.focus_metric weakest_area={@student.weakest_area} />
      </div>

      <%!-- ── Proof Card (shareable progress) ── --%>
      <.proof_card_section
        :if={show_proof_card?(@student)}
        student={@student}
        shared={@shared}
      />

      <%!-- ── Weekly Summary Bar ── --%>
      <.weekly_summary activity={@student.activity} />
    </div>
    """
  end

  # ── Readiness Metric ──────────────────────────────────────────────────────

  defp readiness_metric(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-4">
      <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider mb-1">
        Readiness
      </p>
      <div :if={@score} class="flex items-baseline gap-1">
        <span class={["text-3xl font-extrabold", readiness_text_color(@score)]}>
          {@score}
        </span>
        <span class={["text-sm font-bold", readiness_text_color(@score)]}>%</span>
      </div>
      <p :if={!@score} class="text-lg font-bold text-gray-300 mt-1">
        No data yet
      </p>
      <p :if={@test_name} class="text-[10px] text-gray-400 mt-1 truncate">
        {@test_name}
      </p>
    </div>
    """
  end

  # ── Trend Metric ──────────────────────────────────────────────────────────

  defp trend_metric(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-4">
      <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider mb-1">
        Trend
      </p>
      <div class="flex items-center gap-1.5">
        <span class={["text-2xl", trend_arrow_color(@trend.direction)]}>
          {trend_arrow(@trend.direction)}
        </span>
        <span
          :if={@trend.change != 0}
          class={[
            "text-lg font-extrabold",
            trend_arrow_color(@trend.direction)
          ]}
        >
          {format_change(@trend.change)}
        </span>
        <span :if={@trend.direction == :none} class="text-lg font-bold text-gray-300">
          --
        </span>
      </div>
      <p class="text-[10px] text-gray-400 mt-1">last 2 weeks</p>
    </div>
    """
  end

  # ── Activity Metric ───────────────────────────────────────────────────────

  defp activity_metric(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-4">
      <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider mb-1">
        Activity
      </p>
      <div class="flex items-baseline gap-1">
        <span class={["text-2xl font-extrabold", activity_color(@activity.sessions_today)]}>
          {@activity.sessions_today}
        </span>
        <span class="text-xs text-gray-500">sessions today</span>
      </div>
      <p class="text-[10px] text-gray-400 mt-1">
        {@activity.total_study_minutes_today} min studied
      </p>
    </div>
    """
  end

  # ── Focus Metric (weakest area) ───────────────────────────────────────────

  defp focus_metric(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-4">
      <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider mb-1">
        Next Action
      </p>
      <div :if={@weakest_area} class="mt-1">
        <span class="text-xs font-bold text-amber-600 bg-amber-50 px-2 py-1 rounded-full">
          Focus: {@weakest_area}
        </span>
      </div>
      <p :if={!@weakest_area} class="text-sm font-bold text-gray-300 mt-1">
        Keep it up!
      </p>
    </div>
    """
  end

  # ── Proof Card Section ────────────────────────────────────────────────────

  defp proof_card_section(assigns) do
    improvement = (assigns.student.readiness_score || 0) - (assigns.student.previous_score || 0)
    assigns = assign(assigns, :improvement, improvement)

    ~H"""
    <div class="bg-gradient-to-br from-[#4CD964] to-emerald-500 rounded-2xl p-4 sm:p-5 text-white shadow-lg">
      <div class="flex items-center gap-2 mb-3">
        <span class="text-lg">🏆</span>
        <p class="text-xs font-bold text-white/80 uppercase tracking-wider">
          Progress Achievement
        </p>
      </div>

      <%!-- Card preview area — designed to be screenshot-friendly --%>
      <div class="bg-white/15 rounded-xl p-4 backdrop-blur-sm">
        <p class="text-sm font-bold text-white/90">{@student.course_name}</p>
        <div class="flex items-center gap-3 mt-2">
          <div class="text-center">
            <p class="text-2xl font-extrabold">{@student.previous_score}%</p>
            <p class="text-[10px] text-white/60">before</p>
          </div>
          <span class="text-xl text-white/80">→</span>
          <div class="text-center">
            <p class="text-2xl font-extrabold">{@student.readiness_score}%</p>
            <p class="text-[10px] text-white/60">now</p>
          </div>
          <div class="ml-auto text-right">
            <p class="text-xl font-extrabold text-yellow-200">
              +{@improvement}%
            </p>
          </div>
        </div>
        <p :if={@student.percentile} class="text-xs text-white/70 mt-2">
          Top {100 - @student.percentile}% of students
        </p>
      </div>

      <div class="mt-3 flex items-center justify-between">
        <p class="text-xs text-white/70">
          {if @shared, do: "Shared! Screenshot to save.", else: "Your child is making great progress!"}
        </p>
        <button
          :if={!@shared}
          phx-click="share_progress"
          phx-value-id={@student.id}
          class="bg-white text-[#4CD964] text-xs font-bold px-4 py-2 rounded-full shadow-md hover:bg-green-50 transition-colors"
        >
          Share Progress
        </button>
        <span
          :if={@shared}
          class="bg-white/20 text-white text-xs font-bold px-4 py-2 rounded-full"
        >
          ✓ Shared
        </span>
      </div>
    </div>
    """
  end

  # ── Weekly Summary Bar ────────────────────────────────────────────────────

  defp weekly_summary(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-4">
      <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider mb-3">
        This Week
      </p>
      <div class="grid grid-cols-3 gap-3 text-center">
        <div>
          <p class="text-lg sm:text-xl font-extrabold text-gray-900">
            {@activity.total_study_minutes_week}
          </p>
          <p class="text-[10px] text-gray-400">minutes</p>
        </div>
        <div>
          <p class={[
            "text-lg sm:text-xl font-extrabold",
            accuracy_color(@activity.average_accuracy)
          ]}>
            {format_accuracy(@activity.average_accuracy)}%
          </p>
          <p class="text-[10px] text-gray-400">accuracy</p>
        </div>
        <div>
          <p class="text-lg sm:text-xl font-extrabold text-gray-900">
            {@activity.sessions_this_week}
          </p>
          <p class="text-[10px] text-gray-400">sessions</p>
        </div>
      </div>
    </div>
    """
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp greeting do
    hour = DateTime.utc_now().hour

    cond do
      hour < 12 -> "Good morning"
      hour < 17 -> "Good afternoon"
      true -> "Good evening"
    end
  end

  defp readiness_text_color(score) when score >= 70, do: "text-[#4CD964]"
  defp readiness_text_color(score) when score >= 40, do: "text-amber-500"
  defp readiness_text_color(_), do: "text-[#FF3B30]"

  defp trend_arrow(:improving), do: "↑"
  defp trend_arrow(:declining), do: "↓"
  defp trend_arrow(:stable), do: "→"
  defp trend_arrow(:none), do: "—"

  defp trend_arrow_color(:improving), do: "text-[#4CD964]"
  defp trend_arrow_color(:declining), do: "text-[#FF3B30]"
  defp trend_arrow_color(:stable), do: "text-amber-500"
  defp trend_arrow_color(:none), do: "text-gray-300"

  defp format_change(change) when change > 0, do: "+#{abs(round(change))}"
  defp format_change(change), do: "#{round(change)}"

  defp activity_color(sessions) when sessions >= 3, do: "text-[#4CD964]"
  defp activity_color(sessions) when sessions >= 1, do: "text-amber-500"
  defp activity_color(_), do: "text-[#FF3B30]"

  defp accuracy_color(acc) when acc >= 70, do: "text-[#4CD964]"
  defp accuracy_color(acc) when acc >= 40, do: "text-amber-500"
  defp accuracy_color(_), do: "text-[#FF3B30]"

  defp format_accuracy(nil), do: "0"
  defp format_accuracy(acc), do: round(acc)

  defp show_proof_card?(student) do
    score = student.readiness_score
    prev = student.previous_score
    score != nil and prev != nil and score - prev >= 5
  end
end
