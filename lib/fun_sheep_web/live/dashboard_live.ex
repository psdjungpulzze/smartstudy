defmodule FunSheepWeb.DashboardLive do
  use FunSheepWeb, :live_view

  import FunSheepWeb.SheepMascot

  import FunSheepWeb.ShareButton

  alias FunSheep.{Courses, Assessments, Gamification}
  alias FunSheep.Engagement.{SpacedRepetition, StudySessions}

  @impl true
  def mount(_params, _session, socket) do
    user_role_id = socket.assigns.current_user["id"]

    {upcoming_tests, gamification, course_count, review_stats, daily_summary} =
      case Ecto.UUID.cast(user_role_id) do
        {:ok, _uuid} ->
          tests = Assessments.list_upcoming_schedules(user_role_id, 90)

          tests_with_readiness =
            Enum.map(tests, fn test ->
              readiness = Assessments.latest_readiness(user_role_id, test.id)
              attempts_count = Assessments.attempts_count_for_schedule(user_role_id, test)
              %{test: test, readiness: readiness, attempts_count: attempts_count}
            end)

          gam = Gamification.dashboard_summary(user_role_id)
          count = length(Courses.list_courses_for_user(user_role_id))
          review = SpacedRepetition.review_stats(user_role_id)
          daily = StudySessions.daily_summary(user_role_id)
          {tests_with_readiness, gam, count, review, daily}

        :error ->
          {[], default_gamification(), 0, default_review_stats(), default_daily_summary()}
      end

    # Most urgent test = first (already sorted by date ascending)
    primary_test = List.first(upcoming_tests)
    other_tests = Enum.drop(upcoming_tests, 1)

    socket =
      socket
      |> assign(
        page_title: "Learn",
        primary_test: primary_test,
        other_tests: other_tests,
        gamification: gamification,
        course_count: course_count,
        review_stats: review_stats,
        daily_summary: daily_summary
      )
      |> FunSheepWeb.LiveHelpers.assign_tutorial(
        key: "dashboard",
        title: "Welcome to FunSheep!",
        subtitle: "Here's a quick tour of your home base.",
        steps: [
          %{
            emoji: "📚",
            title: "Courses",
            body: "Browse or create courses tailored to what you're studying."
          },
          %{
            emoji: "⚡",
            title: "Practice",
            body: "Quick-fire flashcards that adapt to what you've mastered."
          },
          %{
            emoji: "📅",
            title: "Tests",
            body: "Track upcoming tests and see your readiness score."
          },
          %{
            emoji: "🔥",
            title: "Streak",
            body:
              "Days in a row you've studied. Answer at least one question each day to keep it alive — miss a day and it resets. Tap the 🔥 badge any time for details."
          },
          %{
            emoji: "⚡",
            title: "Fleece Points (FP)",
            body:
              "Earned for every question, assessment, and daily challenge. More FP level you up. Tap the ⚡ badge any time to see where your FP came from and how to earn more."
          }
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event(
        "navigate_to_assess",
        %{"course-id" => course_id, "schedule-id" => schedule_id},
        socket
      ) do
    {:noreply, push_navigate(socket, to: ~p"/courses/#{course_id}/tests/#{schedule_id}/assess")}
  end

  @impl true
  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("share_completed", %{"method" => method}, socket) do
    message = if method == "clipboard", do: "Link copied!", else: "Shared!"
    {:noreply, put_flash(socket, :info, message)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4 sm:space-y-6">
      <%!-- ── Greeting + Sheep ── --%>
      <div class="flex items-center justify-between gap-3 animate-slide-up">
        <div class="min-w-0">
          <h1 class="text-xl sm:text-2xl font-extrabold text-gray-900 truncate">
            {greeting()}, {@current_user["display_name"]}!
          </h1>
          <p class="text-gray-500 font-medium text-sm mt-0.5">
            {sheep_message(@gamification.sheep_state)}
          </p>
        </div>
        <.sheep
          state={@gamification.sheep_state}
          size="md"
          wool_level={@gamification.streak.wool_level}
        />
      </div>

      <%!-- ── Primary Test: The Focus ── --%>
      <div :if={@primary_test} class="animate-slide-up">
        <.focus_card test={@primary_test} />
      </div>

      <%!-- ── Study Path (journey nodes) ── --%>
      <div :if={@primary_test} class="animate-slide-up">
        <.study_path test={@primary_test} />
      </div>

      <%!-- ── Other Upcoming Tests ── --%>
      <div :if={@other_tests != []} class="animate-slide-up">
        <h2 class="text-sm font-extrabold text-gray-400 uppercase tracking-wider mb-3">
          Other Tests
        </h2>
        <div class="space-y-2">
          <.test_row :for={t <- @other_tests} test={t} />
        </div>
      </div>

      <%!-- ── Empty State: No Tests ── --%>
      <div :if={!@primary_test} class="animate-slide-up">
        <.empty_state course_count={@course_count} gamification={@gamification} />
      </div>

      <%!-- ── Just This: Quick Review (anxiety reducer) ── --%>
      <div :if={@review_stats.due_now > 0} class="animate-slide-up">
        <.just_this_card review_stats={@review_stats} primary_test={@primary_test} />
      </div>

      <%!-- ── Daily Shear Challenge CTA ── --%>
      <div :if={@primary_test} class="animate-slide-up">
        <.daily_shear_cta test={@primary_test} />
      </div>

      <%!-- ── Time-Gated Bonus Tracker ── --%>
      <div :if={@primary_test} class="animate-slide-up">
        <.time_bonus_tracker daily_summary={@daily_summary} />
      </div>

      <%!-- ── Daily Goal ── --%>
      <div :if={@primary_test} class="animate-slide-up">
        <.daily_goal gamification={@gamification} />
      </div>
    </div>
    """
  end

  # ── Focus Card: Most Urgent Test ─────────────────────────────────────────

  defp focus_card(assigns) do
    days_left = Date.diff(assigns.test.test.test_date, Date.utc_today())

    readiness =
      if assigns.test.readiness, do: round(assigns.test.readiness.aggregate_score), else: 0

    urgency = urgency_level(days_left, readiness)
    course_id = assigns.test.test.course_id
    schedule_id = assigns.test.test.id
    attempts_count = Map.get(assigns.test, :attempts_count, 0)

    assigns =
      assigns
      |> assign(:days_left, days_left)
      |> assign(:readiness, readiness)
      |> assign(:urgency, urgency)
      |> assign(:course_id, course_id)
      |> assign(:schedule_id, schedule_id)
      |> assign(:attempts_count, attempts_count)

    ~H"""
    <div
      phx-click="navigate_to_assess"
      phx-value-course-id={@course_id}
      phx-value-schedule-id={@schedule_id}
      class={[
        "rounded-2xl p-4 sm:p-5 shadow-lg relative overflow-hidden cursor-pointer transition-all hover:shadow-xl hover:scale-[1.01]",
        urgency_gradient(@urgency)
      ]}
    >
      <div class="absolute right-0 bottom-0 opacity-10 hidden sm:block">
        <svg width="140" height="100" viewBox="0 0 140 100">
          <polygon points="70,5 140,100 0,100" fill="white" />
          <polygon points="105,30 140,100 70,100" fill="white" opacity="0.5" />
        </svg>
      </div>

      <div class="relative z-10">
        <%!-- Mobile: days-left badge inline; Desktop: side-by-side --%>
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0 flex-1">
            <p class="text-xs font-bold text-white/70 uppercase tracking-wider truncate">
              {if @test.test.course, do: @test.test.course.name, else: "Test Prep"}
            </p>
            <h3 class="text-lg sm:text-xl font-extrabold text-white mt-0.5 line-clamp-2">
              {@test.test.name}
            </h3>
          </div>
          <div class="text-right shrink-0">
            <p class="text-2xl sm:text-3xl font-extrabold text-white">{@days_left}</p>
            <p class="text-[10px] sm:text-xs font-bold text-white/70">days left</p>
          </div>
        </div>

        <%!-- Readiness bar --%>
        <div class="mt-3 sm:mt-4">
          <div class="flex items-center justify-between mb-1.5">
            <span class="text-xs sm:text-sm font-bold text-white/90">Readiness</span>
            <span class="text-xs sm:text-sm font-extrabold text-white">{@readiness}%</span>
          </div>
          <div class="w-full bg-white/20 rounded-full h-2.5 sm:h-3">
            <div
              class="bg-white h-2.5 sm:h-3 rounded-full transition-all duration-1000 relative"
              style={"width: #{@readiness}%"}
            >
              <div class="absolute -top-3 -right-3 w-6 h-6 hidden sm:block">
                <.sheep_inline state={:studying} />
              </div>
            </div>
          </div>
          <div class="flex justify-between mt-1">
            <span class="text-[10px] text-white/50">0%</span>
            <span class="text-[10px] text-white/50">Golden Fleece 100%</span>
          </div>
          <p class="text-[11px] sm:text-xs font-medium text-white/80 mt-1.5">
            {@attempts_count} {if @attempts_count == 1,
              do: "question answered",
              else: "questions answered"}
          </p>
        </div>

        <div class="flex items-center justify-between mt-2 sm:mt-3">
          <p class="text-xs font-medium text-white/80">
            {urgency_message(@urgency, @days_left, @readiness)}
          </p>
          <%!-- Stop propagation so these buttons don't trigger the card's phx-click --%>
          <div class="flex items-center gap-2" phx-click="noop" phx-value-stop="true">
            <.link
              navigate={~p"/courses/#{@course_id}/tests/#{@schedule_id}/edit"}
              class="bg-white/20 border border-white/30 text-white hover:bg-white/30 rounded-full p-1.5 sm:p-2 cursor-pointer transition-colors"
              aria-label="Edit test"
              title="Edit test"
            >
              <.icon name="hero-pencil-square" class="w-4 h-4" />
            </.link>
            <.share_button
              title={"#{@test.test.name} - Fun Sheep"}
              text={"I'm #{@readiness}% ready for #{@test.test.name}! Preparing on Fun Sheep."}
              url={share_url(~p"/courses/#{@test.test.course_id}/tests/#{@test.test.id}/readiness")}
              style={:compact}
              label="Share"
              class="bg-white/20 border-white/30 text-white hover:bg-white/30 hover:text-white"
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Study Path: Duolingo-style journey nodes ─────────────────────────────

  defp study_path(assigns) do
    readiness = if assigns.test.readiness, do: assigns.test.readiness.aggregate_score, else: nil
    has_readiness = readiness != nil
    all_mastered? =
      has_readiness and
        FunSheep.Assessments.ReadinessCalculator.all_skills_mastered?(assigns.test.readiness)
    has_format = assigns.test.test.format_template_id != nil
    course_id = assigns.test.test.course_id
    schedule_id = assigns.test.test.id

    steps = [
      %{
        label: "Assessment",
        desc: "Find your weak spots",
        icon: "🧪",
        done: has_readiness,
        path: ~p"/courses/#{course_id}/tests/#{schedule_id}/assess"
      },
      %{
        label: "Practice Weak Topics",
        desc: "Focus on what needs work",
        icon: "🎯",
        done: has_readiness && readiness >= 40,
        path: ~p"/courses/#{course_id}/practice"
      },
      %{
        label: "Study Guide",
        desc: "Review key concepts",
        icon: "📖",
        done: has_readiness && readiness >= 60,
        path: ~p"/courses/#{course_id}/study-guides"
      },
      %{
        label: "Format Practice",
        desc: "Match the real test format",
        icon: "📝",
        done: has_readiness && readiness >= 80,
        path:
          if(has_format,
            do: ~p"/courses/#{course_id}/tests/#{schedule_id}/format-test",
            else: ~p"/courses/#{course_id}/tests/#{schedule_id}/format"
          )
      },
      %{
        label: "Master Every Skill",
        desc: "Keep drilling weak skills until you're 100% ready",
        icon: "🏁",
        done: all_mastered?,
        path: ~p"/courses/#{course_id}/practice"
      }
    ]

    # Find the next incomplete step
    next_idx = Enum.find_index(steps, fn s -> !s.done end) || length(steps)

    assigns =
      assigns
      |> assign(:steps, steps)
      |> assign(:next_idx, next_idx)

    ~H"""
    <div>
      <h2 class="text-sm font-extrabold text-gray-400 uppercase tracking-wider mb-3 sm:mb-4">
        Your Study Path
      </h2>

      <div class="relative">
        <%!-- Vertical line --%>
        <div class="absolute left-5 sm:left-6 top-0 bottom-0 w-0.5 bg-gray-200"></div>

        <div class="space-y-1">
          <div :for={{step, idx} <- Enum.with_index(@steps)} class="relative">
            <%!-- Node circle + step card --%>
            <.link
              navigate={step.path}
              class="flex items-center gap-3 sm:gap-4 touch-target"
            >
              <div class={[
                "w-10 h-10 sm:w-12 sm:h-12 rounded-full flex items-center justify-center text-lg sm:text-xl shrink-0 relative z-10 border-2",
                cond do
                  step.done ->
                    "bg-[#4CD964] border-[#4CD964]"

                  idx == @next_idx ->
                    "bg-white border-[#4CD964] ring-4 ring-green-100 animate-pulse-subtle"

                  true ->
                    "bg-gray-100 border-gray-200"
                end
              ]}>
                <span :if={step.done} class="text-white text-base sm:text-lg">✓</span>
                <span :if={!step.done}>{step.icon}</span>
              </div>

              <div class={[
                "flex-1 rounded-2xl p-3 sm:p-4 transition-all min-w-0",
                cond do
                  idx == @next_idx -> "bg-white border-2 border-[#4CD964] shadow-md card-hover"
                  step.done -> "bg-white border border-gray-100"
                  true -> "bg-gray-50 border border-gray-100 opacity-60"
                end
              ]}>
                <div class="flex items-center justify-between gap-2">
                  <div class="min-w-0">
                    <p class={[
                      "font-bold text-sm",
                      if(idx == @next_idx, do: "text-gray-900", else: "text-gray-600")
                    ]}>
                      {step.label}
                    </p>
                    <p class="text-xs text-gray-400 mt-0.5 hidden sm:block">{step.desc}</p>
                  </div>
                  <div
                    :if={idx == @next_idx}
                    class="bg-[#4CD964] text-white text-xs font-bold px-3 sm:px-4 py-1.5 sm:py-2 rounded-full shadow-md shrink-0"
                  >
                    START
                  </div>
                  <.icon
                    :if={idx != @next_idx && !step.done}
                    name="hero-lock-closed"
                    class="w-4 h-4 text-gray-300 shrink-0"
                  />
                </div>
              </div>
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Test Row: Compact row for secondary tests ────────────────────────────

  defp test_row(assigns) do
    days = Date.diff(assigns.test.test.test_date, Date.utc_today())

    readiness =
      if assigns.test.readiness, do: round(assigns.test.readiness.aggregate_score), else: nil

    course_id = assigns.test.test.course_id
    schedule_id = assigns.test.test.id
    attempts_count = Map.get(assigns.test, :attempts_count, 0)

    assigns =
      assigns
      |> assign(:days, days)
      |> assign(:readiness_pct, readiness)
      |> assign(:course_id, course_id)
      |> assign(:schedule_id, schedule_id)
      |> assign(:attempts_count, attempts_count)

    ~H"""
    <.link
      navigate={~p"/courses/#{@course_id}/tests/#{@schedule_id}/assess"}
      class="bg-white rounded-2xl border border-gray-100 p-3 sm:p-4 flex items-center gap-2.5 sm:gap-3 card-hover block touch-target"
    >
      <div class={["w-1.5 h-10 rounded-full shrink-0", test_urgency_color(@test.test.test_date)]} />
      <div class="w-9 h-9 sm:w-10 sm:h-10 rounded-xl bg-green-50 flex items-center justify-center text-base sm:text-lg shrink-0">
        {subject_emoji(if @test.test.course, do: @test.test.course.subject, else: nil)}
      </div>
      <div class="flex-1 min-w-0">
        <p class="font-bold text-gray-900 text-sm truncate">{@test.test.name}</p>
        <p class="text-xs text-gray-400 truncate">
          {if @test.test.course, do: @test.test.course.name, else: ""} · {Calendar.strftime(
            @test.test.test_date,
            "%b %d"
          )} · {@attempts_count} answered
        </p>
      </div>
      <div class="text-right shrink-0">
        <p class={["text-sm font-extrabold", days_text_color(@days)]}>{@days}d</p>
      </div>
      <div :if={@readiness_pct} class="text-right shrink-0">
        <p class={["text-sm font-extrabold", readiness_pct_color(@readiness_pct)]}>
          {@readiness_pct}%
        </p>
      </div>
    </.link>
    """
  end

  # ── Empty State ──────────────────────────────────────────────────────────

  defp empty_state(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-6 sm:p-8 text-center">
      <.sheep
        state={@gamification.sheep_state}
        size="xl"
        wool_level={@gamification.streak.wool_level}
        message={
          if @course_count == 0,
            do: "Let's add your first course!",
            else: "Schedule a test to start your journey!"
        }
      />

      <h3 class="font-extrabold text-gray-900 text-lg mt-4">
        {if @course_count == 0, do: "Welcome to Fun Sheep!", else: "No upcoming tests"}
      </h3>
      <p class="text-gray-500 text-sm mt-1 mb-5 max-w-sm mx-auto">
        {if @course_count == 0,
          do: "Add a course and schedule your first test. I'll guide you to 100% readiness!",
          else: "Schedule a test from one of your courses and I'll build your study path."}
      </p>

      <.link
        navigate={if @course_count == 0, do: ~p"/courses", else: ~p"/courses"}
        class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-bold px-6 py-3 sm:py-2.5 rounded-full shadow-md text-sm transition-colors touch-target inline-flex items-center justify-center"
      >
        {if @course_count == 0, do: "Add a Course", else: "Go to Courses"}
      </.link>
    </div>
    """
  end

  # ── Daily Goal ───────────────────────────────────────────────────────────

  defp daily_goal(assigns) do
    ~H"""
    <div class="bg-gradient-to-r from-[#4CD964] to-[#3DBF55] rounded-2xl p-3.5 sm:p-4 text-white shadow-lg">
      <div class="flex items-center gap-3 sm:gap-4">
        <div class="text-2xl sm:text-3xl shrink-0">🎯</div>
        <div class="flex-1 min-w-0">
          <p class="text-[10px] sm:text-xs font-bold text-green-100 uppercase tracking-wider">
            Daily Goal
          </p>
          <p class="font-bold text-sm sm:text-base mt-0.5">
            {daily_goal_text(@gamification.xp_today)}
          </p>
          <p class="text-xs sm:text-sm text-green-100 mt-0.5">+50 Fleece Points</p>
        </div>
        <div class="text-right shrink-0">
          <p class="text-xl sm:text-2xl font-extrabold">{@gamification.xp_today}</p>
          <p class="text-[10px] sm:text-xs text-green-100">FP today</p>
        </div>
      </div>
    </div>
    """
  end

  # ── Just This: Anxiety-Reducing Micro-Task ───────────────────────────────

  defp just_this_card(assigns) do
    course_id =
      if assigns.primary_test,
        do: assigns.primary_test.test.course_id,
        else: nil

    assigns = assign(assigns, :course_id, course_id)

    ~H"""
    <div class="bg-white rounded-2xl border-2 border-[#4CD964] p-4 sm:p-5 shadow-md">
      <div class="flex items-center gap-3">
        <div class="w-10 h-10 rounded-full bg-green-50 flex items-center justify-center text-xl shrink-0">
          🧠
        </div>
        <div class="flex-1 min-w-0">
          <p class="font-bold text-gray-900 text-sm">
            Feeling overwhelmed? Just do this.
          </p>
          <p class="text-xs text-gray-500 mt-0.5">
            {@review_stats.due_now} review cards ready · ~3 minutes
          </p>
        </div>
        <.link
          :if={@course_id}
          navigate={~p"/courses/#{@course_id}/review"}
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white text-xs font-bold px-4 py-2 rounded-full shadow-md shrink-0 transition-colors"
        >
          Just This
        </.link>
      </div>
      <div class="mt-3 flex items-center gap-4 text-xs text-gray-400">
        <span>🎯 {@review_stats.mastered} mastered</span>
        <span>📚 {@review_stats.learning} learning</span>
        <span>📦 {@review_stats.total_cards} total</span>
      </div>
    </div>
    """
  end

  # ── Daily Shear Challenge CTA ──────────────────────────────────────────

  defp daily_shear_cta(assigns) do
    course_id = assigns.test.test.course_id

    assigns = assign(assigns, :course_id, course_id)

    ~H"""
    <.link
      navigate={~p"/courses/#{@course_id}/daily-shear"}
      class="block bg-gradient-to-r from-purple-500 to-indigo-500 rounded-2xl p-4 sm:p-5 text-white shadow-lg card-hover"
    >
      <div class="flex items-center gap-3">
        <div class="text-2xl sm:text-3xl shrink-0">✂️</div>
        <div class="flex-1 min-w-0">
          <p class="text-[10px] sm:text-xs font-bold text-purple-100 uppercase tracking-wider">
            Daily Shear
          </p>
          <p class="font-bold text-sm sm:text-base mt-0.5">
            Today's 5-question challenge
          </p>
          <p class="text-xs text-purple-200 mt-0.5">
            Same questions for everyone · Compare with your flock!
          </p>
        </div>
        <div class="bg-white/20 rounded-full px-3 py-1.5 text-xs font-bold shrink-0">
          GO
        </div>
      </div>
    </.link>
    """
  end

  # ── Time-Gated Bonus Tracker ───────────────────────────────────────────

  defp time_bonus_tracker(assigns) do
    windows = [
      %{
        id: "morning",
        label: "Morning",
        time: "6am-12pm",
        multiplier: "2x",
        emoji: "🌅",
        done: "morning" in assigns.daily_summary.windows_completed
      },
      %{
        id: "afternoon",
        label: "Afternoon",
        time: "12-5pm",
        multiplier: "1.5x",
        emoji: "☀️",
        done: "afternoon" in assigns.daily_summary.windows_completed
      },
      %{
        id: "evening",
        label: "Evening",
        time: "5-10pm",
        multiplier: "1x",
        emoji: "🌙",
        done: "evening" in assigns.daily_summary.windows_completed
      }
    ]

    completed_count = Enum.count(windows, & &1.done)
    all_done = completed_count >= 3

    assigns =
      assigns
      |> assign(:windows, windows)
      |> assign(:completed_count, completed_count)
      |> assign(:all_done, all_done)

    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-4 sm:p-5">
      <div class="flex items-center justify-between mb-3">
        <div>
          <p class="text-sm font-bold text-gray-900">Study Windows</p>
          <p class="text-xs text-gray-400">
            Study in different time slots for bonus FP
          </p>
        </div>
        <div :if={@all_done} class="bg-[#4CD964] text-white text-xs font-bold px-3 py-1 rounded-full">
          +25 FP Bonus!
        </div>
      </div>

      <div class="grid grid-cols-3 gap-2">
        <div
          :for={w <- @windows}
          class={[
            "rounded-xl p-3 text-center border transition-all",
            if(w.done,
              do: "bg-green-50 border-[#4CD964]",
              else: "bg-gray-50 border-gray-100"
            )
          ]}
        >
          <div class="text-lg">{w.emoji}</div>
          <p class={[
            "text-xs font-bold mt-1",
            if(w.done, do: "text-[#4CD964]", else: "text-gray-500")
          ]}>
            {w.label}
          </p>
          <p class="text-[10px] text-gray-400">{w.time}</p>
          <div class={[
            "mt-1 text-[10px] font-bold rounded-full px-2 py-0.5 inline-block",
            if(w.done,
              do: "bg-[#4CD964] text-white",
              else: "bg-gray-200 text-gray-500"
            )
          ]}>
            {if w.done, do: "✓ Done", else: w.multiplier}
          </div>
        </div>
      </div>

      <div class="mt-3 h-1.5 bg-gray-100 rounded-full overflow-hidden">
        <div
          class="h-full bg-[#4CD964] rounded-full transition-all duration-500"
          style={"width: #{@completed_count / 3 * 100}%"}
        />
      </div>
    </div>
    """
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp default_review_stats do
    %{total_cards: 0, due_now: 0, mastered: 0, learning: 0, next_due_at: nil}
  end

  defp default_daily_summary do
    %{
      session_count: 0,
      total_questions: 0,
      total_correct: 0,
      total_xp: 0,
      windows_completed: [],
      windows_remaining: ["morning", "afternoon", "evening"],
      all_windows_bonus_earned: false,
      total_duration_minutes: 0
    }
  end

  defp default_gamification do
    %{
      streak: %{current_streak: 0, longest_streak: 0, wool_level: 0, last_activity_date: nil},
      total_xp: 0,
      xp_today: 0,
      achievement_count: 0,
      sheep_state: :encouraging
    }
  end

  defp greeting do
    hour = DateTime.utc_now().hour

    cond do
      hour < 12 -> "Good morning"
      hour < 17 -> "Hey"
      true -> "Evening"
    end
  end

  defp sheep_message(:studying), do: "Let's keep studying!"
  defp sheep_message(:encouraging), do: "Ready to get started?"
  defp sheep_message(:celebrating), do: "Amazing progress!"
  defp sheep_message(:worried), do: "Test is coming up... let's practice!"
  defp sheep_message(:sleeping), do: "I missed you! Let's get back on track."
  defp sheep_message(:sheared), do: "Brrr! My wool... let's rebuild that streak!"
  defp sheep_message(:fluffy), do: "Look how fluffy I am! Keep it up!"
  defp sheep_message(:golden_fleece), do: "Golden fleece achieved!"
  defp sheep_message(_), do: "Let's do this!"

  defp daily_goal_text(xp) when xp >= 50, do: "Goal reached! Keep going!"
  defp daily_goal_text(_), do: "Complete a practice session"

  defp urgency_level(days_left, readiness) do
    cond do
      days_left <= 0 -> :past
      # Critical: very close and not ready
      days_left <= 3 && readiness < 70 -> :critical
      days_left <= 7 && readiness < 50 -> :critical
      # Urgent: close or very low readiness
      days_left <= 7 -> :urgent
      readiness < 20 -> :urgent
      # Moderate: medium time or medium readiness
      days_left <= 14 -> :moderate
      readiness < 50 -> :moderate
      # Relaxed: plenty of time AND good readiness
      true -> :relaxed
    end
  end

  defp urgency_gradient(:critical), do: "bg-gradient-to-r from-red-500 to-orange-500"
  defp urgency_gradient(:urgent), do: "bg-gradient-to-r from-orange-500 to-amber-500"
  defp urgency_gradient(:moderate), do: "bg-gradient-to-r from-amber-500 to-yellow-500"
  defp urgency_gradient(:relaxed), do: "bg-gradient-to-r from-[#4CD964] to-emerald-500"
  defp urgency_gradient(:past), do: "bg-gradient-to-r from-gray-400 to-gray-500"

  defp urgency_message(:critical, days, readiness),
    do: "Only #{days} days left and #{readiness}% ready — practice now!"

  defp urgency_message(:urgent, days, _readiness),
    do: "#{days} days to go. Focus on your weakest areas."

  defp urgency_message(:moderate, days, readiness),
    do:
      "#{days} days left. #{if readiness > 70, do: "Good pace!", else: "Keep practicing daily."}"

  defp urgency_message(:relaxed, days, readiness),
    do:
      "#{days} days to prepare. #{if readiness > 50, do: "Solid start!", else: "Start with an assessment."}"

  defp urgency_message(:past, _days, _readiness),
    do: "This test date has passed."

  defp test_urgency_color(test_date) do
    days = Date.diff(test_date, Date.utc_today())

    cond do
      days < 0 -> "bg-gray-400"
      days <= 3 -> "bg-red-500"
      days <= 7 -> "bg-amber-500"
      true -> "bg-[#4CD964]"
    end
  end

  defp days_text_color(days) when days < 0, do: "text-gray-400"
  defp days_text_color(days) when days <= 3, do: "text-red-500"
  defp days_text_color(days) when days <= 7, do: "text-amber-500"
  defp days_text_color(_), do: "text-[#4CD964]"

  defp readiness_pct_color(score) when score >= 70, do: "text-[#4CD964]"
  defp readiness_pct_color(score) when score >= 40, do: "text-amber-500"
  defp readiness_pct_color(_), do: "text-red-500"

  defp subject_emoji(nil), do: "📘"

  defp subject_emoji(subject) when is_binary(subject) do
    subject_lower = String.downcase(subject)

    cond do
      String.contains?(subject_lower, "math") -> "🔢"
      String.contains?(subject_lower, "science") -> "🔬"
      String.contains?(subject_lower, "bio") -> "🧬"
      String.contains?(subject_lower, "chem") -> "⚗️"
      String.contains?(subject_lower, "phys") -> "⚛️"
      String.contains?(subject_lower, "hist") -> "🏛️"
      String.contains?(subject_lower, "english") -> "📝"
      String.contains?(subject_lower, "art") -> "🎨"
      String.contains?(subject_lower, "music") -> "🎵"
      String.contains?(subject_lower, "geo") -> "🌍"
      String.contains?(subject_lower, "comp") -> "💻"
      true -> "📘"
    end
  end

  defp subject_emoji(_), do: "📘"
end
