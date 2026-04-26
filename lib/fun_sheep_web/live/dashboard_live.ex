defmodule FunSheepWeb.DashboardLive do
  use FunSheepWeb, :live_view

  import FunSheepWeb.SheepMascot, only: [sheep: 1, sheep_icon: 1]

  import FunSheepWeb.ShareButton

  alias FunSheep.{
    Accounts,
    Courses,
    Assessments,
    Enrollments,
    FixedTests,
    Gamification,
    Integrations,
    MemorySpan,
    Social
  }

  alias FunSheep.Engagement.{SpacedRepetition, StudySessions}

  @impl true
  def mount(_params, _session, socket) do
    user_role_id = socket.assigns.current_user["id"]

    if connected?(socket) do
      Phoenix.PubSub.subscribe(FunSheep.PubSub, "student_progress:#{user_role_id}")
      Phoenix.PubSub.subscribe(FunSheep.PubSub, "social:feed:#{user_role_id}")
    end

    {upcoming_tests, gamification, course_count, review_stats, daily_summary, integrations,
     pinned_id, custom_assignments, onboarding_complete,
     enrolled_courses} =
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
          int = Integrations.list_for_user(user_role_id)
          pinned = Assessments.pinned_test_id(user_role_id)

          tests_with_readiness_and_spans =
            Enum.map(tests_with_readiness, fn entry ->
              span = MemorySpan.get_course_span(user_role_id, entry.test.course_id)
              Map.put(entry, :memory_span, span)
            end)

          custom_assignments = FixedTests.list_assignments_for_student(user_role_id)

          user_role = Accounts.get_user_role!(user_role_id)
          onboarding_done = Accounts.onboarding_complete?(user_role)
          enrolled = Enrollments.list_for_student(user_role_id)

          {tests_with_readiness_and_spans, gam, count, review, daily, int, pinned,
           custom_assignments, onboarding_done, enrolled}

        :error ->
          {[], default_gamification(), 0, default_review_stats(), default_daily_summary(), [],
           nil, [], true, []}
      end

    social_suggestions =
      case Ecto.UUID.cast(user_role_id) do
        {:ok, _} -> Social.suggested_follows(user_role_id, 3)
        :error -> []
      end

    following_count =
      case Ecto.UUID.cast(user_role_id) do
        {:ok, _} -> Social.following_count(user_role_id)
        :error -> 0
      end

    # Build memory_spans map: course_id → span (for quick lookup in templates)
    memory_spans =
      upcoming_tests
      |> Enum.map(fn entry -> {entry.test.course_id, Map.get(entry, :memory_span)} end)
      |> Map.new()

    # Primary = pinned test (if still upcoming) or nearest-deadline fallback.
    # "Stale pins" (test has passed / deleted) silently degrade to nearest-deadline.
    {primary_test, other_tests} = split_primary_and_other(upcoming_tests, pinned_id)

    socket =
      socket
      |> assign(
        page_title: "Learn",
        primary_test: primary_test,
        other_tests: other_tests,
        pinned_test_id: pinned_id,
        gamification: gamification,
        course_count: course_count,
        review_stats: review_stats,
        daily_summary: daily_summary,
        integrations: integrations,
        memory_spans: memory_spans,
        custom_assignments: custom_assignments,
        onboarding_complete: onboarding_complete,
        enrolled_courses: enrolled_courses,
        social_suggestions: social_suggestions,
        following_count: following_count,
        social_feed: []
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
  def handle_event("pin_test", %{"schedule-id" => schedule_id}, socket) do
    user_role_id = socket.assigns.current_user["id"]

    case Assessments.pin_test(user_role_id, schedule_id) do
      {:ok, _} ->
        {:noreply, socket |> refresh_primary() |> put_flash(:info, "Pinned as your focus test.")}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "That test doesn't belong to you.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't pin that test.")}
    end
  end

  @impl true
  def handle_event("unpin_test", _params, socket) do
    user_role_id = socket.assigns.current_user["id"]

    case Assessments.unpin_test(user_role_id) do
      {:ok, _} ->
        {:noreply, refresh_primary(socket)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:readiness_updated, socket) do
    user_role_id = socket.assigns.current_user["id"]

    updated_tests =
      (List.wrap(socket.assigns.primary_test) ++ socket.assigns.other_tests)
      |> Enum.map(fn entry ->
        readiness = Assessments.latest_readiness(user_role_id, entry.test.id)
        %{entry | readiness: readiness}
      end)

    pinned_id = socket.assigns.pinned_test_id
    {primary, other} = split_primary_and_other(updated_tests, pinned_id)

    memory_spans =
      updated_tests
      |> Enum.map(fn entry ->
        {entry.test.course_id, MemorySpan.get_course_span(user_role_id, entry.test.course_id)}
      end)
      |> Map.new()

    {:noreply,
     assign(socket, primary_test: primary, other_tests: other, memory_spans: memory_spans)}
  end

  def handle_info({:friend_achievement, friend_id, achievement_type}, socket) do
    alias FunSheep.Gamification.Achievement
    info = Achievement.display_info(achievement_type)

    entry = %{friend_id: friend_id, achievement_type: achievement_type, info: info}
    feed = [entry | socket.assigns.social_feed] |> Enum.take(5)
    {:noreply, assign(socket, social_feed: feed)}
  end

  # Ignore other PubSub messages we're not interested in.
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp refresh_primary(socket) do
    upcoming = socket.assigns.other_tests ++ List.wrap(socket.assigns.primary_test)
    pinned_id = Assessments.pinned_test_id(socket.assigns.current_user["id"])
    {primary, other} = split_primary_and_other(upcoming, pinned_id)

    assign(socket, primary_test: primary, other_tests: other, pinned_test_id: pinned_id)
  end

  # Given an upcoming-tests list (wrapped `%{test: ts, readiness: _, attempts_count: _}`
  # per mount) and an optional pinned test_schedule_id, returns `{primary, other}`.
  # If the pinned test is still in the upcoming list, it's promoted to primary;
  # otherwise the nearest-deadline entry (head of the date-sorted list) is primary.
  defp split_primary_and_other(upcoming, pinned_id) when is_list(upcoming) do
    pinned_entry =
      if pinned_id, do: Enum.find(upcoming, fn %{test: ts} -> ts.id == pinned_id end), else: nil

    case pinned_entry do
      nil ->
        {List.first(upcoming), Enum.drop(upcoming, 1)}

      entry ->
        {entry, Enum.reject(upcoming, fn e -> e.test.id == entry.test.id end)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4 sm:space-y-6">
      <%!-- ── Onboarding CTA (new students) ── --%>
      <div :if={!@onboarding_complete} class="animate-slide-up">
        <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-5 flex items-center justify-between gap-4">
          <div class="min-w-0">
            <p class="font-semibold text-gray-900 dark:text-white text-sm">
              See courses at your school — takes 2 minutes
            </p>
            <p class="text-xs text-gray-500 mt-0.5">Pick your subjects and start practising today.</p>
          </div>
          <a
            href="/onboarding/student"
            class="shrink-0 bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-4 py-2 rounded-full shadow-md transition-colors text-sm"
          >
            Get Started →
          </a>
        </div>
      </div>

      <%!-- ── Onboarding done but no enrolled courses ── --%>
      <div :if={@onboarding_complete and @enrolled_courses == []} class="animate-slide-up">
        <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-5 flex items-center justify-between gap-4">
          <div class="min-w-0">
            <p class="font-semibold text-gray-900 dark:text-white text-sm">
              Add courses to get started
            </p>
            <p class="text-xs text-gray-500 mt-0.5">Browse available courses or create your own.</p>
          </div>
          <div class="flex gap-2 shrink-0">
            <a
              href="/courses"
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-3 py-2 rounded-full shadow-md transition-colors text-sm"
            >
              Browse courses at my school
            </a>
            <a
              href="/courses/new"
              class="border border-gray-200 dark:border-gray-600 text-gray-700 dark:text-gray-300 font-medium px-3 py-2 rounded-full transition-colors text-sm hover:border-[#4CD964]"
            >
              + Create a course
            </a>
          </div>
        </div>
      </div>

      <%!-- ── My Courses (enrolled) ── --%>
      <div :if={@enrolled_courses != []} class="animate-slide-up">
        <h2 class="text-sm font-extrabold text-gray-400 uppercase tracking-wider mb-3">
          My Courses
        </h2>
        <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
          <a
            :for={sc <- @enrolled_courses}
            href={if sc.course, do: "/courses/#{sc.course.id}", else: "#"}
            class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-sm p-4 hover:shadow-md transition-shadow border border-transparent hover:border-[#4CD964]"
          >
            <p class="font-semibold text-sm text-gray-900 dark:text-white truncate">
              {if sc.course, do: sc.course.name, else: "Course"}
            </p>
            <p class="text-xs text-gray-500 mt-0.5">
              {if sc.course,
                do: "#{sc.course.subject} · #{FunSheep.Courses.format_grades(sc.course.grades)}",
                else: ""}
            </p>
          </a>
        </div>
      </div>

      <%!-- ── Greeting + Sheep ── --%>
      <div class="flex items-center justify-between gap-3 animate-slide-up">
        <div class="min-w-0">
          <h1 class="text-xl sm:text-2xl font-extrabold text-gray-900 break-words">
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

      <%!-- ── Empty State: No Tests (above the fold) ── --%>
      <div :if={!@primary_test} class="animate-slide-up">
        <.empty_state course_count={@course_count} gamification={@gamification} />
      </div>

      <%!-- ── Flow A — usage meter + Ask card + waiting state (§4) ── --%>
      <div class="animate-slide-up">
        <.live_component
          module={FunSheepWeb.PracticeRequestLive.AskComponent}
          id="practice-request-ask"
          student_id={@current_user["id"]}
        />
      </div>

      <%!-- ── Primary Test: The Focus ── --%>
      <div :if={@primary_test} class="animate-slide-up">
        <.focus_card
          test={@primary_test}
          pinned?={@pinned_test_id == @primary_test.test.id}
        />
      </div>

      <%!-- ── Memory Span Card ── --%>
      <div :if={@primary_test} class="animate-slide-up">
        <.memory_span_card
          course_id={@primary_test.test.course_id}
          span={Map.get(@memory_spans, @primary_test.test.course_id)}
          course_name={if @primary_test.test.course, do: @primary_test.test.course.name, else: ""}
        />
      </div>

      <%!-- ── Connected apps ── --%>
      <div class="animate-slide-up">
        <.connected_apps_card integrations={@integrations} />
      </div>

      <%!-- ── Other Upcoming Tests ── --%>
      <div :if={@other_tests != []} class="animate-slide-up">
        <h2 class="text-sm font-extrabold text-gray-400 uppercase tracking-wider mb-3">
          Other Tests
        </h2>
        <div class="space-y-2">
          <.test_row :for={t <- @other_tests} test={t} pinned_id={@pinned_test_id} />
        </div>
      </div>

      <%!-- ── Custom (fixed) test assignments ── --%>
      <div :if={@custom_assignments != []} class="animate-slide-up">
        <h2 class="text-sm font-extrabold text-gray-400 uppercase tracking-wider mb-3">
          Custom Tests
        </h2>
        <div class="space-y-2">
          <.custom_test_row :for={a <- @custom_assignments} assignment={a} />
        </div>
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

      <%!-- ── Find Classmates Widget ── --%>
      <.find_classmates_widget suggestions={@social_suggestions} following_count={@following_count} />

      <%!-- ── Friends Activity Feed ── --%>
      <.social_feed_widget :if={@social_feed != []} feed={@social_feed} />
    </div>
    """
  end

  # ── Focus Card: Most Urgent Test ─────────────────────────────────────────

  attr :test, :map, required: true
  attr :pinned?, :boolean, default: false

  defp focus_card(assigns) do
    days_left = Date.diff(assigns.test.test.test_date, Date.utc_today())
    readiness_score = assigns.test.readiness

    readiness =
      if readiness_score, do: round(readiness_score.aggregate_score), else: 0

    coverage_pct = if readiness_score, do: readiness_score.coverage_pct, else: 100.0

    full_test_readiness =
      if readiness_score, do: round(readiness_score.full_test_readiness), else: 0

    empty_count = if readiness_score, do: length(readiness_score.empty_section_ids), else: 0
    has_coverage_gap? = coverage_pct < 100.0

    urgency = urgency_level(days_left, full_test_readiness)
    course_id = assigns.test.test.course_id
    schedule_id = assigns.test.test.id
    attempts_count = Map.get(assigns.test, :attempts_count, 0)

    card_state = card_readiness_state(readiness_score, attempts_count)

    assessment_done? =
      FunSheep.Assessments.ReadinessCalculator.assessment_complete?(readiness_score)

    aggregate = if readiness_score, do: readiness_score.aggregate_score, else: 0.0

    all_mastered? =
      assessment_done? and
        FunSheep.Assessments.ReadinessCalculator.all_skills_mastered?(readiness_score)

    has_format = assigns.test.test.format_template_id != nil

    steps = [
      %{
        label: "Assessment",
        desc: "Find your weak spots",
        icon: "🧪",
        done: assessment_done?,
        path: ~p"/courses/#{course_id}/tests/#{schedule_id}/assess"
      },
      %{
        label: "Practice",
        desc: "Drill weak skills until you're ready",
        icon: "🎯",
        done: assessment_done? && aggregate >= 80,
        path: ~p"/courses/#{course_id}/practice"
      }
    ]

    format_step = %{
      label: "Format Practice",
      desc: "Simulate the real test",
      icon: "📝",
      done: all_mastered?,
      path:
        if(has_format,
          do: ~p"/courses/#{course_id}/tests/#{schedule_id}/format-test",
          else: ~p"/courses/#{course_id}/tests/#{schedule_id}/format"
        )
    }

    next_idx = Enum.find_index(steps, fn s -> !s.done end) || length(steps)

    assigns =
      assigns
      |> assign(:days_left, days_left)
      |> assign(:readiness, readiness)
      |> assign(:urgency, urgency)
      |> assign(:course_id, course_id)
      |> assign(:schedule_id, schedule_id)
      |> assign(:attempts_count, attempts_count)
      |> assign(:steps, steps)
      |> assign(:next_idx, next_idx)
      |> assign(:format_step, format_step)
      |> assign(:all_mastered?, all_mastered?)
      |> assign(:coverage_pct, coverage_pct)
      |> assign(:full_test_readiness, full_test_readiness)
      |> assign(:empty_count, empty_count)
      |> assign(:has_coverage_gap?, has_coverage_gap?)
      |> assign(:card_state, card_state)

    ~H"""
    <div class={[
      "rounded-2xl p-4 sm:p-5 shadow-lg relative overflow-hidden",
      urgency_gradient(@urgency)
    ]}>
      <div class="absolute right-0 bottom-0 opacity-10 hidden sm:block">
        <svg width="140" height="100" viewBox="0 0 140 100">
          <polygon points="70,5 140,100 0,100" fill="white" />
          <polygon points="105,30 140,100 70,100" fill="white" opacity="0.5" />
        </svg>
      </div>

      <div class="relative z-10">
        <%!-- Course name + test name + days left --%>
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-1.5 flex-wrap">
              <p class="text-xs font-bold text-white/70 uppercase tracking-wider truncate">
                {if @test.test.course, do: @test.test.course.name, else: "Test Prep"}
              </p>
              <span
                :if={@pinned?}
                class="inline-flex items-center gap-1 text-[10px] font-extrabold bg-white/25 text-white px-2 py-0.5 rounded-full uppercase tracking-wider"
              >
                <.icon name="hero-star-solid" class="w-3 h-3" /> Focus
              </span>
            </div>
            <h3 class="text-lg sm:text-xl font-extrabold text-white mt-0.5 line-clamp-2">
              {@test.test.name}
            </h3>
          </div>
          <div class={"text-right shrink-0 #{days_urgency_class(@days_left)}"}>
            <p class="text-2xl sm:text-3xl font-extrabold text-white">{@days_left}</p>
            <p class="text-[10px] sm:text-xs font-bold text-white/70">days left</p>
          </div>
        </div>

        <%!-- Readiness bar with walking sheep mascot --%>
        <div class="mt-3 sm:mt-4">
          <div class="flex items-center justify-between mb-1.5">
            <span class="text-xs sm:text-sm font-bold text-white/90">
              {if @has_coverage_gap?, do: "Readiness (available concepts)", else: "Readiness"}
            </span>
            <span class="text-xs sm:text-sm font-extrabold text-white">{@readiness}%</span>
          </div>
          <div
            id={"focus-readiness-bar-#{@schedule_id}"}
            phx-hook="SheepProgressBar"
            data-readiness={@readiness}
            class="relative w-full bg-white/20 rounded-full h-2.5 sm:h-3 overflow-visible"
          >
            <div
              class="bg-white h-2.5 sm:h-3 rounded-full transition-all duration-1000"
              style={"width: #{@readiness}%"}
            >
            </div>
            <div
              data-sheep
              class="absolute top-1/2 -translate-y-1/2 pointer-events-none hidden sm:block"
              style="will-change: transform; position: absolute;"
            >
              <.sheep_icon size="sm" state={readiness_to_state(@readiness)} />
            </div>
          </div>
          <div class="flex justify-between mt-1">
            <span class="text-[10px] text-white/50">0%</span>
            <span class="text-[10px] text-white/50">100%</span>
          </div>

          <%!-- Coverage gap warning — informational only, kept subtle --%>
          <p :if={@has_coverage_gap?} class="mt-1.5 text-[10px] text-white/45 leading-snug">
            ⚠︎ {@empty_count} {if @empty_count == 1, do: "topic has", else: "topics have"} no questions yet · est. readiness {@full_test_readiness}%
          </p>

          <%!-- State-aware readiness label --%>
          <%= case @card_state do %>
            <% :untested -> %>
              <p class="text-[11px] sm:text-xs font-medium text-white/90 mt-1.5">
                Not yet tested — take the assessment to see where you stand
              </p>
            <% :in_progress -> %>
              <% scores = if @test.readiness, do: @test.readiness.skill_scores, else: %{} %>
              <% tested_count = Enum.count(scores, fn {_, v} -> v.status != :insufficient_data end) %>
              <% total_count = map_size(scores) %>
              <p class="text-[11px] sm:text-xs font-medium text-white/80 mt-1.5">
                {tested_count} of {total_count} concepts assessed
                &middot; {@attempts_count} {if @attempts_count == 1,
                  do: "question answered",
                  else: "questions answered"}
              </p>
            <% :complete -> %>
              <% scores = if @test.readiness, do: @test.readiness.skill_scores, else: %{} %>
              <% weak_count = Enum.count(scores, fn {_, v} -> v.status == :weak end) %>
              <% needs_work_count = Enum.count(scores, fn {_, v} -> v.status == :probing end) %>
              <% total_needing_work = weak_count + needs_work_count %>
              <div class="flex items-center gap-2 mt-1.5 flex-wrap">
                <p class="text-[11px] sm:text-xs font-medium text-white/80">
                  {@attempts_count} {if @attempts_count == 1,
                    do: "question answered",
                    else: "questions answered"}
                </p>
                <span
                  :if={total_needing_work > 0}
                  class="text-[10px] bg-white/20 text-white px-2 py-0.5 rounded-full font-semibold"
                >
                  {total_needing_work} {if total_needing_work == 1,
                    do: "concept needs work",
                    else: "concepts need work"}
                </span>
              </div>
          <% end %>
        </div>

        <%!-- Assessment + Practice steps --%>
        <div class="mt-3 sm:mt-4 border-t border-white/20 pt-3 space-y-2">
          <div :for={{step, idx} <- Enum.with_index(@steps)}>
            <.link
              navigate={step.path}
              class={[
                "flex items-center gap-2.5 group",
                if(idx == @next_idx && !step.done, do: "pointer-events-auto", else: "")
              ]}
            >
              <div class={[
                "rounded-full flex items-center justify-center text-sm shrink-0 transition-all",
                cond do
                  step.done -> "w-8 h-8 bg-white/25"
                  idx == @next_idx -> "w-10 h-10 bg-white shadow-lg"
                  true -> "w-8 h-8 bg-white/8"
                end
              ]}>
                <span :if={step.done} class="text-white text-xs font-bold">✓</span>
                <span :if={!step.done} class={if(idx == @next_idx, do: "text-base", else: "")}>
                  {step.icon}
                </span>
              </div>
              <div class={[
                "flex-1 flex items-center justify-between rounded-xl px-3 transition-all",
                cond do
                  idx == @next_idx && !step.done ->
                    "bg-white py-3 shadow-xl group-hover:shadow-2xl group-hover:scale-[1.01]"

                  step.done ->
                    "bg-white/10 py-2"

                  true ->
                    "bg-white/8 py-2 opacity-30"
                end
              ]}>
                <div class="min-w-0">
                  <p class={[
                    "font-bold leading-tight",
                    cond do
                      idx == @next_idx && !step.done -> "text-gray-900 text-base"
                      step.done -> "text-sm text-white/70"
                      true -> "text-sm text-white/40"
                    end
                  ]}>
                    {step.label}
                  </p>
                  <p class={[
                    "text-xs mt-0.5",
                    if(idx == @next_idx && !step.done,
                      do: "text-gray-500 block",
                      else: "text-white/50 hidden sm:block"
                    )
                  ]}>
                    {step.desc}
                  </p>
                </div>
                <span
                  :if={idx == @next_idx && !step.done}
                  class="bg-[#4CD964] text-white text-sm font-extrabold px-4 py-1.5 rounded-full shrink-0 ml-3 shadow-md"
                >
                  START
                </span>
                <span :if={step.done} class="text-white/50 text-xs ml-2">✓</span>
                <.icon
                  :if={!step.done && idx != @next_idx}
                  name="hero-lock-closed"
                  class="w-3.5 h-3.5 text-white/20 shrink-0 ml-2"
                />
              </div>
            </.link>
          </div>
        </div>

        <%!-- Format Practice — smaller secondary row --%>
        <.link
          navigate={@format_step.path}
          class="mt-2 flex items-center gap-2 px-1 py-1.5 group rounded-lg hover:bg-white/10 transition-colors"
        >
          <span class="text-sm opacity-70">{@format_step.icon}</span>
          <span class={[
            "text-xs font-medium",
            if(@format_step.done, do: "text-white/50 line-through", else: "text-white/70")
          ]}>
            {@format_step.label}
          </span>
          <span class="text-xs text-white/35 hidden sm:block">· {@format_step.desc}</span>
          <.icon
            name="hero-chevron-right"
            class="w-3.5 h-3.5 text-white/35 ml-auto group-hover:text-white/60 transition-colors"
          />
        </.link>

        <%!-- Urgency message + action buttons --%>
        <div class="flex items-center justify-between mt-3 pt-2 border-t border-white/20">
          <p class="text-xs font-medium text-white/80">
            {urgency_message(@urgency, @days_left, @readiness)}
          </p>
          <div class="flex items-center gap-2">
            <button
              type="button"
              phx-click={if @pinned?, do: "unpin_test", else: "pin_test"}
              phx-value-schedule-id={@schedule_id}
              class="bg-white/20 border border-white/30 text-white hover:bg-white/30 rounded-full p-1.5 sm:p-2 cursor-pointer transition-colors"
              aria-label={if @pinned?, do: "Unpin as focus test", else: "Pin as focus test"}
              title={
                if @pinned?,
                  do: "Pinned as your focus — click to unpin",
                  else: "Pin as your focus test"
              }
            >
              <.icon
                name={if @pinned?, do: "hero-star-solid", else: "hero-star"}
                class="w-4 h-4"
              />
            </button>
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

  # ── Test Row: Compact row for secondary tests ────────────────────────────

  attr :test, :map, required: true
  attr :pinned_id, :string, default: nil

  defp test_row(assigns) do
    days = Date.diff(assigns.test.test.test_date, Date.utc_today())

    readiness =
      if assigns.test.readiness, do: round(assigns.test.readiness.aggregate_score), else: nil

    course_id = assigns.test.test.course_id
    schedule_id = assigns.test.test.id
    attempts_count = Map.get(assigns.test, :attempts_count, 0)
    pinned? = assigns.pinned_id == schedule_id

    assigns =
      assigns
      |> assign(:days, days)
      |> assign(:readiness_pct, readiness)
      |> assign(:course_id, course_id)
      |> assign(:schedule_id, schedule_id)
      |> assign(:attempts_count, attempts_count)
      |> assign(:pinned?, pinned?)

    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-3 sm:p-4 flex items-center gap-2.5 sm:gap-3 card-hover touch-target">
      <.link
        navigate={~p"/courses/#{@course_id}/tests/#{@schedule_id}/assess"}
        class="flex-1 flex items-center gap-2.5 sm:gap-3 min-w-0"
      >
        <div class={[
          "w-1.5 h-10 rounded-full shrink-0",
          test_urgency_color(@test.test.test_date)
        ]} />
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
      <button
        type="button"
        phx-click={if @pinned?, do: "unpin_test", else: "pin_test"}
        phx-value-schedule-id={@schedule_id}
        class={[
          "shrink-0 rounded-full p-1.5 sm:p-2 transition-colors cursor-pointer",
          if(@pinned?,
            do: "text-[#4CD964] hover:bg-green-50",
            else: "text-gray-300 hover:text-gray-500 hover:bg-gray-50"
          )
        ]}
        aria-label={if @pinned?, do: "Unpin as focus test", else: "Pin as focus test"}
        title={if @pinned?, do: "Pinned as your focus — click to unpin", else: "Pin as focus test"}
      >
        <.icon name={if @pinned?, do: "hero-star-solid", else: "hero-star"} class="w-4 h-4" />
      </button>
    </div>
    """
  end

  # ── Connected apps ───────────────────────────────────────────────────────

  defp connected_apps_card(%{integrations: []} = assigns) do
    ~H"""
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
            Connect your school app
          </h3>
          <p class="text-gray-500 text-xs">
            Auto-import courses &amp; tests from Google Classroom or Canvas.
          </p>
        </div>
        <span class="text-[#4CD964] text-xs font-medium">Connect →</span>
      </div>
    </.link>
    """
  end

  defp connected_apps_card(assigns) do
    assigns = assign(assigns, :active, Enum.count(assigns.integrations, &(&1.status == :active)))

    ~H"""
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
            Connected apps
          </h3>
          <p class="text-gray-500 text-xs">
            {@active} of {length(@integrations)} connected. Tap to manage.
          </p>
        </div>
        <span class="text-[#4CD964] text-xs font-medium">Manage →</span>
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
            do: "Let's get you set up!",
            else: "Let's pick what you're studying for!"
        }
      />

      <h3 class="font-extrabold text-gray-900 text-lg mt-4">
        {if @course_count == 0, do: "Welcome to Fun Sheep!", else: "No upcoming tests"}
      </h3>
      <p class="text-gray-500 text-sm mt-1 mb-5 max-w-sm mx-auto">
        Tell us about a test you're studying for and we'll help you get ready. Or connect Google Classroom or Canvas to auto-import upcoming tests.
      </p>

      <div class="flex flex-col sm:flex-row gap-2 justify-center items-stretch sm:items-center max-w-md mx-auto">
        <.link
          navigate={
            if @course_count == 0,
              do: ~p"/courses/new?flow=test",
              else: ~p"/courses"
          }
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-bold px-6 py-3 sm:py-2.5 rounded-full shadow-md text-sm transition-colors touch-target inline-flex items-center justify-center gap-2"
        >
          <.icon name="hero-plus" class="w-4 h-4" /> Add a test
        </.link>
        <.link
          navigate={~p"/integrations"}
          class="bg-white hover:bg-gray-50 text-gray-700 font-bold px-6 py-3 sm:py-2.5 rounded-full border border-gray-200 text-sm transition-colors touch-target inline-flex items-center justify-center gap-2"
        >
          <.icon name="hero-link" class="w-4 h-4" /> Connect School LMS
        </.link>
      </div>
    </div>
    """
  end

  # ── Daily Goal ───────────────────────────────────────────────────────────

  defp daily_goal(assigns) do
    ~H"""
    <div
      id="daily-goal-confetti"
      phx-hook="ConfettiBurst"
      class="relative bg-gradient-to-r from-[#4CD964] to-[#3DBF55] rounded-2xl p-3.5 sm:p-4 text-white shadow-lg overflow-hidden"
    >
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
          <p
            id="daily-xp-counter"
            phx-hook="CountUp"
            data-target={@gamification.xp_today}
            class="text-xl sm:text-2xl font-extrabold"
          >
            {@gamification.xp_today}
          </p>
          <p class="text-[10px] sm:text-xs text-green-100">FP today</p>
        </div>
      </div>
    </div>
    """
  end

  # ── Custom Test Row ──────────────────────────────────────────────────────

  defp custom_test_row(assigns) do
    bank = assigns.assignment.bank
    due = assigns.assignment.due_at

    due_label =
      cond do
        is_nil(due) -> nil
        Date.diff(DateTime.to_date(due), Date.utc_today()) < 0 -> "Overdue"
        Date.diff(DateTime.to_date(due), Date.utc_today()) == 0 -> "Due today"
        true -> "Due #{Calendar.strftime(due, "%b %d")}"
      end

    assigns = assign(assigns, bank: bank, due_label: due_label)

    ~H"""
    <.link
      navigate={~p"/custom-tests/#{@bank.id}/start"}
      class="bg-white rounded-2xl border border-gray-100 p-3 sm:p-4 flex items-center gap-3 card-hover block"
    >
      <div class="w-9 h-9 rounded-xl bg-indigo-100 flex items-center justify-center shrink-0">
        <span class="text-indigo-600 text-lg">📋</span>
      </div>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <span class="text-xs font-medium bg-indigo-100 text-indigo-700 px-1.5 py-0.5 rounded-full">
            Custom
          </span>
          <p class="font-semibold text-[#1C1C1E] text-sm truncate">{@bank.title}</p>
        </div>
        <%= if @due_label do %>
          <p class={[
            "text-xs mt-0.5",
            if(@due_label == "Overdue", do: "text-[#FF3B30]", else: "text-[#8E8E93]")
          ]}>
            {@due_label}
          </p>
        <% end %>
      </div>
      <span class="text-[#8E8E93] text-sm">→</span>
    </.link>
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

  # ── Memory Span Card ─────────────────────────────────────────────────────

  attr :course_id, :string, required: true
  attr :course_name, :string, required: true
  attr :span, :any, default: nil

  defp memory_span_card(assigns) do
    formatted = FunSheep.MemorySpan.format_span(assigns.span && assigns.span.span_hours)
    color = FunSheep.MemorySpan.span_color(assigns.span && assigns.span.span_hours)
    trend = assigns.span && assigns.span.trend
    previous_hours = assigns.span && assigns.span.previous_span_hours
    span_hours = assigns.span && assigns.span.span_hours

    trend_arrow =
      case trend do
        "improving" -> "↑"
        "declining" -> "↓"
        "stable" -> "→"
        _ -> nil
      end

    trend_days =
      if is_integer(span_hours) and is_integer(previous_hours) do
        diff = div(abs(span_hours - previous_hours), 24)
        if diff > 0, do: "+#{diff} days", else: nil
      end

    {_emoji_label, description} = FunSheep.MemorySpan.span_label(span_hours)

    assigns =
      assigns
      |> assign(:formatted, formatted)
      |> assign(:color, color)
      |> assign(:trend, trend)
      |> assign(:trend_arrow, trend_arrow)
      |> assign(:trend_days, trend_days)
      |> assign(:description, description)
      |> assign(:span_hours, span_hours)

    ~H"""
    <div class="rounded-2xl bg-white shadow-sm border border-[#E5E5EA] p-6">
      <div class="flex items-center gap-2 mb-3">
        <div class="w-9 h-9 rounded-xl bg-gray-100 flex items-center justify-center text-lg shrink-0">
          🧠
        </div>
        <div>
          <h3 class="font-bold text-gray-900 text-sm">Memory Span</h3>
          <p class="text-xs text-gray-400">{@course_name}</p>
        </div>
      </div>

      <div :if={is_nil(@span_hours)} class="text-sm text-gray-500 mb-3">
        Keep practicing to unlock your memory span!
      </div>

      <div :if={@span_hours} class="flex items-center gap-2 mb-2">
        <span class={[
          "text-xl font-extrabold",
          memory_span_text_color(@color)
        ]}>
          {@formatted}
        </span>
        <span
          :if={@trend_arrow}
          class={[
            "text-sm font-bold",
            memory_span_trend_color(@trend)
          ]}
        >
          {@trend_arrow}
          <span :if={@trend_days} class="text-xs font-medium">{@trend_days}</span>
        </span>
        <span class={[
          "text-xs font-semibold px-2 py-0.5 rounded-full ml-auto",
          memory_span_badge_class(@color)
        ]}>
          {memory_span_badge_label(@color)}
        </span>
      </div>

      <p :if={@span_hours} class="text-xs text-gray-500 mb-3 leading-relaxed">
        {@description}
      </p>

      <.link
        navigate={~p"/courses/#{@course_id}/memory-span"}
        class="text-xs font-semibold text-[#4CD964] hover:text-[#3DBF55] transition-colors inline-flex items-center gap-1"
      >
        See breakdown by topic <.icon name="hero-arrow-right" class="w-3.5 h-3.5" />
      </.link>
    </div>
    """
  end

  defp memory_span_text_color("green"), do: "text-[#4CD964]"
  defp memory_span_text_color("yellow"), do: "text-amber-500"
  defp memory_span_text_color("red"), do: "text-red-500"
  defp memory_span_text_color(_), do: "text-gray-400"

  # Takes the trend value ("improving" | "declining" | "stable" | nil)
  defp memory_span_trend_color("improving"), do: "text-[#4CD964]"
  defp memory_span_trend_color("declining"), do: "text-red-500"
  defp memory_span_trend_color(_), do: "text-gray-400"

  # The badge and text helpers below take the span color ("green" | "yellow" | "red" | "gray")
  defp memory_span_badge_class("green"), do: "bg-green-100 text-[#4CD964]"
  defp memory_span_badge_class("yellow"), do: "bg-amber-100 text-amber-600"
  defp memory_span_badge_class("red"), do: "bg-red-100 text-red-600"
  defp memory_span_badge_class(_), do: "bg-gray-100 text-gray-500"

  defp memory_span_badge_label("green"), do: "Strong"
  defp memory_span_badge_label("yellow"), do: "Moderate"
  defp memory_span_badge_label("red"), do: "At risk"
  defp memory_span_badge_label(_), do: "No data"

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

  # Maps readiness percentage to a sheep_icon state string.
  defp readiness_to_state(r) when r >= 80, do: "run"
  defp readiness_to_state(_), do: "walk"

  # Maps days_left to urgency animation class for the days counter.
  defp days_urgency_class(days) when days in 1..2, do: "heartbeat-fast text-red-400"
  defp days_urgency_class(days) when days in 3..6, do: "heartbeat-pulse text-amber-400"
  defp days_urgency_class(_), do: ""

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

  # ── Find Classmates Widget ────────────────────────────────────────────────

  attr :suggestions, :list, required: true
  attr :following_count, :integer, required: true

  defp find_classmates_widget(assigns) do
    ~H"""
    <div :if={@suggestions != [] or @following_count == 0} class="animate-slide-up">
      <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md overflow-hidden">
        <div class="flex items-center justify-between px-4 pt-4 pb-2">
          <div>
            <h2 class="font-extrabold text-gray-900 dark:text-white text-sm">Find Classmates</h2>
            <p class="text-xs text-gray-400 mt-0.5">
              Following {@following_count} {if @following_count == 1, do: "student", else: "students"}
            </p>
          </div>
          <.link navigate={~p"/social/find"} class="text-xs text-[#4CD964] font-bold hover:underline">
            See All →
          </.link>
        </div>

        <div :if={@suggestions != []} class="divide-y divide-gray-50 dark:divide-gray-700">
          <div :for={s <- @suggestions} class="flex items-center gap-3 px-4 py-2.5">
            <.link navigate={~p"/social/profile/#{s.user_role.id}"} class="shrink-0">
              <div class="w-8 h-8 rounded-full bg-gray-100 dark:bg-gray-700 flex items-center justify-center text-xs font-bold text-gray-600 dark:text-gray-200 hover:opacity-80 transition-opacity">
                {String.first(s.user_role.display_name || "?")}
              </div>
            </.link>
            <.link
              navigate={~p"/social/profile/#{s.user_role.id}"}
              class="flex-1 min-w-0 hover:underline"
            >
              <p class="text-sm font-bold text-gray-900 dark:text-white truncate">
                {s.user_role.display_name}
              </p>
              <p class="text-xs text-gray-400">{suggestion_reason(s.reason)}</p>
            </.link>
            <.link
              navigate={~p"/social/find"}
              class="shrink-0 text-xs px-3 py-1 rounded-full bg-[#4CD964] text-white font-bold hover:bg-[#3DBF55] transition-colors"
            >
              + Follow
            </.link>
          </div>
        </div>

        <div :if={@suggestions == [] and @following_count == 0} class="px-4 pb-4 pt-2 text-center">
          <p class="text-xs text-gray-400">No classmates found yet.</p>
        </div>

        <div class="bg-gray-50 dark:bg-gray-800 px-4 py-2.5">
          <.link
            navigate={~p"/social/find"}
            class="w-full flex items-center justify-center gap-2 text-sm font-bold text-gray-700 dark:text-gray-200 hover:text-[#4CD964] transition-colors"
          >
            <svg
              class="w-4 h-4"
              fill="none"
              stroke="currentColor"
              stroke-width="1.5"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z"
              />
            </svg>
            Search All Classmates
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp suggestion_reason(:school), do: "🏫 Same school"
  defp suggestion_reason(:fof), do: "👥 Friend of a friend"
  defp suggestion_reason(:course), do: "📚 Shared course"
  defp suggestion_reason(_), do: "Suggested"

  # ── Social Feed Widget ────────────────────────────────────────────────────

  attr :feed, :list, required: true

  defp social_feed_widget(assigns) do
    ~H"""
    <div class="animate-slide-up">
      <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md overflow-hidden">
        <div class="px-4 pt-4 pb-2">
          <h2 class="font-extrabold text-gray-900 dark:text-white text-sm">Friends Activity</h2>
        </div>
        <div class="divide-y divide-gray-50 dark:divide-gray-700">
          <div :for={entry <- @feed} class="flex items-center gap-3 px-4 py-2.5">
            <span class="text-2xl">{entry.info.emoji}</span>
            <div class="flex-1 min-w-0">
              <p class="text-xs text-gray-600 dark:text-gray-300">
                A friend just earned <span class="font-semibold">{entry.info.name}</span>
              </p>
              <p class="text-[10px] text-gray-400">{entry.info.description}</p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # State A: nothing answered yet
  defp card_readiness_state(_readiness_score, 0), do: :untested
  defp card_readiness_state(nil, _), do: :untested

  defp card_readiness_state(%{skill_scores: scores}, _attempts_count) do
    total = map_size(scores)
    tested = Enum.count(scores, fn {_, v} -> v.status != :insufficient_data end)

    cond do
      total == 0 -> :untested
      tested == 0 -> :untested
      tested < total -> :in_progress
      true -> :complete
    end
  end
end
