defmodule StudySmartWeb.DashboardLive do
  use StudySmartWeb, :live_view

  alias StudySmart.Courses

  @impl true
  def mount(_params, _session, socket) do
    user_role_id = socket.assigns.current_user["id"]

    course_stats =
      case Ecto.UUID.cast(user_role_id) do
        {:ok, _uuid} -> Courses.list_courses_with_stats(user_role_id)
        :error -> []
      end

    {:ok,
     assign(socket,
       page_title: "Home",
       course_stats: course_stats
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Greeting + Daily Progress --%>
      <div class="animate-slide-up">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-extrabold text-gray-900">
              {greeting()}, {@current_user["display_name"]}!
            </h1>
            <p class="text-gray-500 font-medium text-sm mt-0.5">{motivational_message()}</p>
          </div>
          <div class="text-4xl animate-float">{greeting_emoji()}</div>
        </div>

        <%!-- Stats Strip --%>
        <div class="flex items-center gap-3 mt-5 overflow-x-auto pb-1 -mx-1 px-1">
          <.pill_stat emoji="🔥" value="3" label="streak" bg="bg-orange-50" text="text-orange-600" border="border-orange-100" />
          <.pill_stat emoji="⚡" value="150" label="XP" bg="bg-amber-50" text="text-amber-600" border="border-amber-100" />
          <.pill_stat emoji="📚" value={to_string(length(@course_stats))} label="courses" bg="bg-purple-50" text="text-purple-600" border="border-purple-100" />
          <.pill_stat emoji="🏆" value="0" label="badges" bg="bg-pink-50" text="text-pink-600" border="border-pink-100" />
        </div>
      </div>

      <%!-- Daily Challenge --%>
      <div class="mt-6 bg-gradient-to-r from-purple-600 to-indigo-600 rounded-2xl p-5 text-white shadow-lg card-hover animate-slide-up">
        <div class="flex items-center gap-4">
          <div class="text-4xl animate-streak shrink-0">🎯</div>
          <div class="flex-1 min-w-0">
            <p class="text-xs font-bold text-purple-200 uppercase tracking-wider">Daily Challenge</p>
            <p class="font-bold text-lg mt-0.5">Complete a Quick Test</p>
            <p class="text-sm text-purple-200 mt-0.5">+50 XP bonus</p>
          </div>
          <.link
            navigate={~p"/quick-test"}
            class="bg-white text-purple-700 font-bold px-5 py-2.5 rounded-full shadow-md btn-bounce text-sm whitespace-nowrap shrink-0"
          >
            Go!
          </.link>
        </div>
      </div>

      <%!-- Course Section --%>
      <div class="mt-8 animate-slide-up">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-extrabold text-gray-900">My Courses</h2>
          <div class="flex gap-2">
            <.link
              navigate={~p"/courses"}
              class="text-sm font-bold text-gray-500 hover:text-gray-700 px-3 py-1.5 rounded-lg hover:bg-gray-50 transition-colors"
            >
              Browse
            </.link>
            <.link
              navigate={~p"/courses/new"}
              class="text-sm font-bold text-purple-600 hover:text-purple-700 px-3 py-1.5 rounded-lg bg-purple-50 hover:bg-purple-100 transition-colors"
            >
              + Add
            </.link>
          </div>
        </div>

        <%!-- Empty State --%>
        <div :if={@course_stats == []} class="bg-white rounded-2xl border border-gray-100 p-8 text-center card-hover">
          <div class="animate-float text-5xl mb-4">📖</div>
          <h3 class="font-bold text-gray-900 text-lg">No courses yet</h3>
          <p class="text-gray-500 text-sm mt-1 mb-5">Add your first course and start earning XP</p>
          <.link
            navigate={~p"/courses"}
            class="inline-block bg-purple-600 hover:bg-purple-700 text-white font-bold px-6 py-2.5 rounded-full shadow-md btn-bounce text-sm"
          >
            Get Started
          </.link>
        </div>

        <%!-- Course Cards - Stacked list, not grid --%>
        <div :if={@course_stats != []} class="space-y-3">
          <.link
            :for={{stat, idx} <- Enum.with_index(@course_stats)}
            navigate={~p"/courses/#{stat.course.id}"}
            class={"bg-white rounded-2xl border border-gray-100 p-4 flex items-center gap-4 card-hover block animate-slide-up stagger-#{rem(idx, 6) + 1}"}
          >
            <%!-- Subject Emoji --%>
            <div class="w-12 h-12 rounded-xl bg-purple-50 flex items-center justify-center text-2xl shrink-0">
              {subject_emoji(stat.course.subject)}
            </div>

            <%!-- Course Info --%>
            <div class="flex-1 min-w-0">
              <p class="font-bold text-gray-900 text-sm truncate">{stat.course.name}</p>
              <div class="flex items-center gap-2 mt-1">
                <span class="text-xs font-bold text-purple-600 bg-purple-50 px-2 py-0.5 rounded-full">
                  {stat.course.subject}
                </span>
                <span class="text-xs font-bold text-cyan-600 bg-cyan-50 px-2 py-0.5 rounded-full">
                  Grade {stat.course.grade}
                </span>
              </div>
              <%!-- Progress bar --%>
              <div class="mt-2 flex items-center gap-2">
                <div class="flex-1 bg-gray-100 rounded-full h-2">
                  <div class="progress-gradient h-2 rounded-full" style="width: 0%"></div>
                </div>
                <span class="text-xs font-bold text-gray-400">0%</span>
              </div>
            </div>

            <%!-- Stats --%>
            <div class="text-right shrink-0 hidden sm:block">
              <p class="text-xs text-gray-400">{stat.chapter_count} ch</p>
              <p class="text-xs text-gray-400">{stat.question_count} Q</p>
            </div>
          </.link>
        </div>
      </div>

      <%!-- Upcoming Tests --%>
      <div class="mt-8 animate-slide-up">
        <h2 class="text-lg font-extrabold text-gray-900 mb-4">Coming Up</h2>
        <div class="bg-white rounded-2xl border border-gray-100 p-6 text-center card-hover">
          <div class="text-4xl mb-2">😎</div>
          <p class="text-gray-500 font-medium text-sm">No tests coming up -- you're all clear!</p>
        </div>
      </div>
    </div>
    """
  end

  # ── Stat pill component ─────────────────────────────────────────────────────

  attr :emoji, :string, required: true
  attr :value, :string, required: true
  attr :label, :string, required: true
  attr :bg, :string, required: true
  attr :text, :string, required: true
  attr :border, :string, required: true

  defp pill_stat(assigns) do
    ~H"""
    <div class={"flex items-center gap-1.5 px-3 py-2 rounded-xl border shrink-0 #{@bg} #{@border}"}>
      <span class="text-base">{@emoji}</span>
      <span class={"text-sm font-extrabold #{@text}"}>{@value}</span>
      <span class="text-xs text-gray-400 font-medium">{@label}</span>
    </div>
    """
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp greeting do
    hour = DateTime.utc_now().hour

    cond do
      hour < 12 -> "Good morning"
      hour < 17 -> "Hey"
      true -> "Evening"
    end
  end

  defp greeting_emoji do
    hour = DateTime.utc_now().hour

    cond do
      hour < 12 -> "🌅"
      hour < 17 -> "👋"
      true -> "🌙"
    end
  end

  defp motivational_message do
    messages = [
      "Keep the streak alive!",
      "Ready to level up?",
      "Small steps, big gains.",
      "Your future self says thanks!",
      "Every question counts."
    ]

    Enum.random(messages)
  end

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
