defmodule FunSheepWeb.ParentDashboardLive do
  use FunSheepWeb, :live_view

  import FunSheepWeb.SheepMascot

  alias FunSheep.{Accounts, Assessments, Courses, Gamification, Repo}
  alias FunSheep.Assessments.Forecaster
  alias FunSheep.Engagement.{StudySessions, Wellbeing}

  alias FunSheepWeb.StudentLive.Shared.{
    ActivityTimeline,
    ForecastCard,
    PeerComparison,
    PercentileTrend,
    StudyHeatmap,
    TopicMasteryMap,
    WellbeingFraming
  }

  @activity_window_days 30
  @heatmap_weeks 4
  @percentile_history_weeks 4

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {students, user_role} =
      case Accounts.get_user_role_by_interactor_id(user["interactor_user_id"]) do
        nil ->
          {[], nil}

        ur ->
          links = Accounts.list_students_for_guardian(ur.id)

          enriched =
            links
            |> Enum.map(fn sg -> enrich_student(sg.student, guardian_id: ur.id) end)
            |> Enum.reject(&is_nil/1)

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
        shared_student_id: nil,
        drill: nil
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
    {:noreply, assign(socket, selected_id: id, drill: nil)}
  end

  @impl true
  def handle_event("share_progress", %{"id" => student_id}, socket) do
    {:noreply, assign(socket, shared_student_id: student_id)}
  end

  @impl true
  def handle_event("topic_drill", %{"section-id" => section_id}, socket) do
    guardian_id = socket.assigns.user_role && socket.assigns.user_role.id
    student_id = socket.assigns.selected_id

    cond do
      guardian_id == nil or student_id == nil ->
        {:noreply, socket}

      not Accounts.guardian_has_access?(guardian_id, student_id) ->
        {:noreply, socket}

      true ->
        section = Courses.get_section(section_id)
        chapter = section && Courses.get_chapter(section.chapter_id)
        attempts = Assessments.recent_attempts_for_topic(student_id, section_id, 10)
        trend = Assessments.topic_accuracy_trend(student_id, section_id, 30)

        drill = %{
          section_id: section_id,
          topic_name: section && section.name,
          chapter_name: chapter && chapter.name,
          attempts: attempts,
          trend: trend
        }

        {:noreply, assign(socket, drill: drill)}
    end
  end

  @impl true
  def handle_event("close_topic_drill", _params, socket) do
    {:noreply, assign(socket, drill: nil)}
  end

  @impl true
  def handle_event("assign_topic_practice", _params, socket) do
    # Wired up in Phase 3 (§7.2 practice_assignments).
    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "set_target_readiness",
        %{"schedule_id" => schedule_id, "value" => value},
        socket
      ) do
    guardian_id = socket.assigns.user_role && socket.assigns.user_role.id
    student_id = socket.assigns.selected_id

    with true <- is_binary(guardian_id),
         true <- is_binary(student_id),
         true <- Accounts.guardian_has_access?(guardian_id, student_id),
         {:ok, int_value} <- parse_target_value(value),
         schedule when not is_nil(schedule) <-
           Repo.get(FunSheep.Assessments.TestSchedule, schedule_id),
         true <- schedule.user_role_id == student_id,
         {:ok, _} <- Assessments.set_target_readiness(schedule, int_value, :guardian) do
      {:noreply, refresh_students(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  defp refresh_students(socket) do
    user_role = socket.assigns.user_role

    if user_role do
      links = Accounts.list_students_for_guardian(user_role.id)

      students =
        links
        |> Enum.map(fn sg -> enrich_student(sg.student, guardian_id: user_role.id) end)
        |> Enum.reject(&is_nil/1)

      assign(socket, students: students)
    else
      socket
    end
  end

  defp parse_target_value(v) when is_integer(v) and v >= 0 and v <= 100, do: {:ok, v}

  defp parse_target_value(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} when n >= 0 and n <= 100 -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_target_value(_), do: :error

  # ── Data Loading ──────────────────────────────────────────────────────────

  defp enrich_student(student, opts) do
    student_id = student.id
    guardian_id = Keyword.fetch!(opts, :guardian_id)

    # Spec §9.1 authorization guard: never expose data unless access is active.
    if Accounts.guardian_has_access?(guardian_id, student_id) do
      tz = student.timezone || "Etc/UTC"

      # Upcoming tests + readiness
      upcoming = Assessments.list_upcoming_schedules(student_id, 90)
      primary_test = List.first(upcoming)

      {readiness_score, readiness_trend, percentile, test_name, course_name, weakest_area,
       previous_score, topic_grid, test_schedule_id} = readiness_block(student_id, primary_test)

      # Activity summary (existing v1)
      activity = StudySessions.parent_activity_summary(student_id)

      # Gamification (existing v1)
      gam = Gamification.dashboard_summary(student_id)

      # Phase 1 additions
      timeline_sessions =
        StudySessions.list_for_student_in_window(student_id, @activity_window_days)

      heatmap_grid = StudySessions.study_heatmap(student_id, @heatmap_weeks, tz)
      wellbeing = Wellbeing.classify(student_id)

      # Phase 2 additions
      {percentile_history, forecast, peer_bands, target_readiness, days_to_test} =
        benchmarks_block(student_id, student, primary_test)

      %{
        id: student_id,
        name: student.display_name || student.email,
        grade: student.grade,
        timezone: tz,
        readiness_score: readiness_score,
        readiness_trend: readiness_trend,
        percentile: percentile,
        test_name: test_name,
        course_name: course_name,
        previous_score: previous_score,
        weakest_area: weakest_area,
        activity: activity,
        gamification: gam,
        upcoming_count: length(upcoming),
        # Phase 1
        test_schedule_id: test_schedule_id,
        timeline_sessions: timeline_sessions,
        heatmap_grid: heatmap_grid,
        topic_grid: topic_grid,
        wellbeing: wellbeing,
        # Phase 2
        percentile_history: percentile_history,
        forecast: forecast,
        peer_bands: peer_bands,
        target_readiness: target_readiness,
        days_to_test: days_to_test,
        primary_test_schedule_id: primary_test && primary_test.id
      }
    else
      # Defensive: if an in-flight revoke happens between list + enrich, bail.
      nil
    end
  end

  defp benchmarks_block(_student_id, _student, nil),
    do: {[], %{status: :insufficient_data, reason: :no_schedule}, nil, nil, nil}

  defp benchmarks_block(student_id, student, primary_test) do
    history =
      Assessments.readiness_percentile_history(
        student_id,
        primary_test.id,
        @percentile_history_weeks
      )

    forecast = Forecaster.forecast(student_id, primary_test.id)

    peer_bands =
      if primary_test.course_id && student.grade do
        Assessments.cohort_percentile_bands(primary_test.course_id, student.grade)
      end

    days_to_test = Date.diff(primary_test.test_date, Date.utc_today())

    {history, forecast, peer_bands, primary_test.target_readiness_score, max(days_to_test, 0)}
  end

  defp readiness_block(_student_id, nil) do
    {nil, %{direction: :none, change: 0, scores: []}, nil, nil, nil, nil, nil, [], nil}
  end

  defp readiness_block(student_id, primary_test) do
    readiness = Assessments.latest_readiness(student_id, primary_test.id)
    trend = Assessments.readiness_trend(student_id, primary_test.id)
    pctile = Assessments.readiness_percentile(student_id, primary_test.id)

    score = if readiness, do: round(readiness.aggregate_score), else: nil
    weak = weakest_chapter(readiness, primary_test)
    prev = previous_readiness_score(trend)
    topic_grid = Assessments.topic_mastery_map(student_id, primary_test.id)

    {score, trend, pctile, primary_test.name,
     if(primary_test.course, do: primary_test.course.name, else: "Test Prep"), weak, prev,
     topic_grid, primary_test.id}
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
          {gettext("Here's how your children are doing")}
        </p>
      </div>

      <%!-- ── Flow A — pending practice requests (§4.6.2) ── --%>
      <div :if={@user_role} class="animate-slide-up">
        <.live_component
          module={FunSheepWeb.PracticeRequestLive.ParentCardComponent}
          id="parent-practice-requests"
          parent_id={@user_role.id}
        />
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
                {gettext("School apps")}
              </h3>
              <p class="text-gray-500 text-xs">
                {gettext("Auto-import your child's courses and tests.")}
              </p>
            </div>
            <span class="text-[#4CD964] text-xs font-medium">{gettext("Manage")} →</span>
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
            message={gettext("Invite your child to connect their account!")}
          />
          <h3 class="font-extrabold text-gray-900 text-lg mt-4">
            {gettext("No students linked yet")}
          </h3>
          <p class="text-gray-500 text-sm mt-1 mb-5 max-w-sm mx-auto">
            {gettext(
              "Connect your child's Fun Sheep account to see their study progress and celebrate their achievements together."
            )}
          </p>
          <.link
            navigate={~p"/guardians"}
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-bold px-6 py-3 sm:py-2.5 rounded-full shadow-md text-sm transition-colors touch-target inline-flex items-center justify-center"
          >
            {gettext("Connect a Student")}
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
            drill={@drill}
          />
        </div>
      </div>
    </div>
    """
  end

  # ── Student Card ──────────────────────────────────────────────────────────

  defp student_card(assigns) do
    signal = assigns.student.wellbeing.signal
    dampen? = WellbeingFraming.dampen_competitive?(signal)

    assigns =
      assigns
      |> assign(:wellbeing_signal, signal)
      |> assign(:dampen?, dampen?)

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
                {gettext("Grade")} {@student.grade}
              </p>
            </div>
          </div>
          <div class="text-right shrink-0">
            <p class="text-xs text-gray-400">
              {@student.upcoming_count} {gettext("upcoming tests")}
            </p>
          </div>
        </div>
      </div>

      <%!-- ── Wellbeing Framing Banner (§5.4) ── --%>
      <WellbeingFraming.framing_banner signal={@wellbeing_signal} student_name={@student.name} />

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

      <%!-- ── Percentile card (dampened when wellbeing says so) ── --%>
      <.percentile_card
        :if={!@dampen? and @student.percentile}
        percentile={@student.percentile}
      />

      <%!-- ── Phase 2: Percentile Trend (§6.1) ── --%>
      <PercentileTrend.trend
        :if={!@dampen? and @student.primary_test_schedule_id}
        history={@student.percentile_history}
        current_percentile={percentile_value(@student.percentile)}
        target_readiness={@student.target_readiness}
        days_to_test={@student.days_to_test}
      />

      <%!-- ── Phase 2: Target-setter (only if no target yet) ── --%>
      <.target_setter
        :if={@student.primary_test_schedule_id && is_nil(@student.target_readiness)}
        student={@student}
      />

      <%!-- ── Phase 2: Forecast card (§6.2) ── --%>
      <ForecastCard.card
        :if={@student.primary_test_schedule_id}
        forecast={@student.forecast}
      />

      <%!-- ── Phase 2: Peer comparison (§6.3) — dampened too ── --%>
      <PeerComparison.card
        :if={!@dampen? and @student.peer_bands}
        bands={@student.peer_bands}
        student_readiness={@student.readiness_score}
      />

      <%!-- ── Activity Timeline (§5.1) ── --%>
      <ActivityTimeline.timeline
        sessions={@student.timeline_sessions}
        student_name={@student.name}
      />

      <%!-- ── Study Heatmap (§5.2) ── --%>
      <StudyHeatmap.heatmap grid={@student.heatmap_grid} />

      <%!-- ── Topic Mastery Map (§5.3) ── --%>
      <TopicMasteryMap.mastery_map grid={@student.topic_grid} test_name={@student.test_name} />

      <%!-- ── Drill-down Modal ── --%>
      <TopicMasteryMap.drill_modal
        :if={@drill}
        topic_name={@drill.topic_name || gettext("Topic")}
        chapter_name={@drill.chapter_name}
        attempts={@drill.attempts}
        trend={@drill.trend}
        assign_enabled?={false}
      />

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

  attr :student, :map, required: true

  defp target_setter(assigns) do
    ~H"""
    <section class="bg-white rounded-2xl border border-gray-100 p-4 sm:p-5">
      <p class="text-sm font-extrabold text-gray-900 mb-1">
        {gettext("Set a joint target score")}
      </p>
      <p class="text-xs text-gray-500 mb-3">
        {gettext(
          "Pick a readiness target for %{test}. Research suggests aspirational-but-achievable goals beat open-ended pressure.",
          test: @student.test_name
        )}
      </p>
      <form
        phx-submit="set_target_readiness"
        class="flex items-center gap-2"
      >
        <input type="hidden" name="schedule_id" value={@student.primary_test_schedule_id} />
        <label for={"target-#{@student.id}"} class="sr-only">{gettext("Target readiness")}</label>
        <input
          id={"target-#{@student.id}"}
          name="value"
          type="number"
          min="0"
          max="100"
          step="1"
          placeholder="80"
          class="w-20 rounded-full border border-gray-200 px-3 py-2 text-sm focus:border-[#4CD964] focus:outline-none"
        />
        <button
          type="submit"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white text-xs font-bold px-4 py-2 rounded-full shadow-md"
        >
          {gettext("Save target")}
        </button>
      </form>
    </section>
    """
  end

  attr :percentile, :any, required: true

  defp percentile_card(assigns) do
    pct = percentile_value(assigns.percentile)
    assigns = assign(assigns, :pct, pct)

    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-4">
      <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider mb-1">
        {gettext("Cohort standing")}
      </p>
      <p :if={@pct} class="text-sm text-gray-700">
        {gettext("Top")} {100 - @pct}{gettext("% of same-grade FunSheep students")}
      </p>
      <p :if={!@pct} class="text-sm text-gray-500">
        {gettext("Not enough cohort data yet.")}
      </p>
    </div>
    """
  end

  # ── Readiness Metric ──────────────────────────────────────────────────────

  defp readiness_metric(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-4">
      <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider mb-1">
        {gettext("Readiness")}
      </p>
      <div :if={@score} class="flex items-baseline gap-1">
        <span class={["text-3xl font-extrabold", readiness_text_color(@score)]}>
          {@score}
        </span>
        <span class={["text-sm font-bold", readiness_text_color(@score)]}>%</span>
      </div>
      <p :if={!@score} class="text-lg font-bold text-gray-300 mt-1">
        {gettext("No data yet")}
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
        {gettext("Trend")}
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
      <p class="text-[10px] text-gray-400 mt-1">{gettext("last 2 weeks")}</p>
    </div>
    """
  end

  # ── Activity Metric ───────────────────────────────────────────────────────

  defp activity_metric(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-4">
      <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider mb-1">
        {gettext("Activity")}
      </p>
      <div class="flex items-baseline gap-1">
        <span class={["text-2xl font-extrabold", activity_color(@activity.sessions_today)]}>
          {@activity.sessions_today}
        </span>
        <span class="text-xs text-gray-500">{gettext("sessions today")}</span>
      </div>
      <p class="text-[10px] text-gray-400 mt-1">
        {@activity.total_study_minutes_today} {gettext("min studied")}
      </p>
    </div>
    """
  end

  # ── Focus Metric (weakest area) ───────────────────────────────────────────

  defp focus_metric(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-4">
      <p class="text-[10px] font-bold text-gray-400 uppercase tracking-wider mb-1">
        {gettext("Next Action")}
      </p>
      <div :if={@weakest_area} class="mt-1">
        <span class="text-xs font-bold text-amber-600 bg-amber-50 px-2 py-1 rounded-full">
          {gettext("Focus:")} {@weakest_area}
        </span>
      </div>
      <p :if={!@weakest_area} class="text-sm font-bold text-gray-300 mt-1">
        {gettext("Keep it up!")}
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
          {gettext("Progress Achievement")}
        </p>
      </div>

      <%!-- Card preview area — designed to be screenshot-friendly --%>
      <div class="bg-white/15 rounded-xl p-4 backdrop-blur-sm">
        <p class="text-sm font-bold text-white/90">{@student.course_name}</p>
        <div class="flex items-center gap-3 mt-2">
          <div class="text-center">
            <p class="text-2xl font-extrabold">{@student.previous_score}%</p>
            <p class="text-[10px] text-white/60">{gettext("before")}</p>
          </div>
          <span class="text-xl text-white/80">→</span>
          <div class="text-center">
            <p class="text-2xl font-extrabold">{@student.readiness_score}%</p>
            <p class="text-[10px] text-white/60">{gettext("now")}</p>
          </div>
          <div class="ml-auto text-right">
            <p class="text-xl font-extrabold text-yellow-200">
              +{@improvement}%
            </p>
          </div>
        </div>
        <p :if={percentile_value(@student.percentile)} class="text-xs text-white/70 mt-2">
          {gettext("Top")} {100 - percentile_value(@student.percentile)}{gettext("% of students")}
        </p>
      </div>

      <div class="mt-3 flex items-center justify-between">
        <p class="text-xs text-white/70">
          {if @shared,
            do: gettext("Shared! Screenshot to save."),
            else: gettext("Your child is making great progress!")}
        </p>
        <button
          :if={!@shared}
          phx-click="share_progress"
          phx-value-id={@student.id}
          class="bg-white text-[#4CD964] text-xs font-bold px-4 py-2 rounded-full shadow-md hover:bg-green-50 transition-colors"
        >
          {gettext("Share Progress")}
        </button>
        <span
          :if={@shared}
          class="bg-white/20 text-white text-xs font-bold px-4 py-2 rounded-full"
        >
          ✓ {gettext("Shared")}
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
        {gettext("This Week")}
      </p>
      <div class="grid grid-cols-3 gap-3 text-center">
        <div>
          <p class="text-lg sm:text-xl font-extrabold text-gray-900">
            {@activity.total_study_minutes_week}
          </p>
          <p class="text-[10px] text-gray-400">{gettext("minutes")}</p>
        </div>
        <div>
          <p class={[
            "text-lg sm:text-xl font-extrabold",
            accuracy_color(@activity.average_accuracy)
          ]}>
            {format_accuracy(@activity.average_accuracy)}%
          </p>
          <p class="text-[10px] text-gray-400">{gettext("accuracy")}</p>
        </div>
        <div>
          <p class="text-lg sm:text-xl font-extrabold text-gray-900">
            {@activity.sessions_this_week}
          </p>
          <p class="text-[10px] text-gray-400">{gettext("sessions")}</p>
        </div>
      </div>
    </div>
    """
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp greeting do
    hour = DateTime.utc_now().hour

    cond do
      hour < 12 -> gettext("Good morning")
      hour < 17 -> gettext("Good afternoon")
      true -> gettext("Good evening")
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

  defp percentile_value(%{percentile: p}) when is_number(p), do: p
  defp percentile_value(_), do: nil
end
