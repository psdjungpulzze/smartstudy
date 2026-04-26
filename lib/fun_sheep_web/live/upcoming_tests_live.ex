defmodule FunSheepWeb.UpcomingTestsLive do
  use FunSheepWeb, :live_view

  alias FunSheep.{Assessments, Courses}

  @impl true
  def mount(_params, _session, socket) do
    user_role_id = socket.assigns.current_user["id"]

    {tests_by_course, course_map} =
      case Ecto.UUID.cast(user_role_id) do
        {:ok, _} ->
          tests = Assessments.list_upcoming_schedules(user_role_id, 90)

          tests_with_readiness =
            Enum.map(tests, fn test ->
              readiness = Assessments.latest_readiness(user_role_id, test.id)
              %{test: test, readiness: readiness}
            end)

          grouped = Enum.group_by(tests_with_readiness, fn t -> t.test.course_id end)

          cmap =
            Enum.into(grouped, %{}, fn {course_id, _} ->
              {course_id, Courses.get_course!(course_id)}
            end)

          {grouped, cmap}

        :error ->
          {%{}, %{}}
      end

    {:ok,
     assign(socket,
       page_title: "Upcoming Tests",
       tests_by_course: tests_by_course,
       course_map: course_map
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="animate-slide-up">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-extrabold text-gray-900">Upcoming Tests</h1>
          <p class="text-gray-500 text-sm mt-1">All your scheduled tests</p>
        </div>
      </div>

      <div
        :if={@tests_by_course == %{}}
        class="bg-white rounded-2xl border border-gray-100 p-8 text-center"
      >
        <div class="text-5xl mb-3">📝</div>
        <h3 class="font-bold text-gray-900 text-lg">No upcoming tests</h3>
        <p class="text-gray-500 text-sm mt-1 mb-4">
          Schedule a test from one of your courses
        </p>
        <.link
          navigate={~p"/courses"}
          class="inline-block bg-[#4CD964] hover:bg-[#3DBF55] text-white font-bold px-5 py-2.5 rounded-full shadow-md text-sm"
        >
          Go to Courses
        </.link>
      </div>

      <div :if={@tests_by_course != %{}} class="space-y-6">
        <div :for={{course_id, tests} <- @tests_by_course}>
          <div class="flex items-center gap-3 mb-3">
            <div class="w-8 h-8 rounded-lg bg-green-50 flex items-center justify-center text-lg shrink-0">
              {subject_emoji(Map.get(@course_map, course_id).subject)}
            </div>
            <div class="flex-1 min-w-0">
              <h2 class="font-extrabold text-gray-900 text-sm truncate">
                {Map.get(@course_map, course_id).name}
              </h2>
              <p class="text-xs text-gray-400">
                {Map.get(@course_map, course_id).subject} · {FunSheep.Courses.format_grades(
                  Map.get(@course_map, course_id).grades
                )}
              </p>
            </div>
            <.link
              navigate={~p"/courses/#{course_id}/tests/new"}
              class="text-xs font-bold text-[#4CD964] hover:text-[#3DBF55] transition-colors"
            >
              + New
            </.link>
          </div>

          <div class="space-y-2">
            <div
              :for={{t, idx} <- Enum.with_index(tests)}
              class={"bg-white rounded-2xl border border-gray-100 p-4 flex items-center gap-4 card-hover animate-slide-up stagger-#{rem(idx, 6) + 1}"}
            >
              <div class={["w-1.5 h-12 rounded-full shrink-0", urgency_color(t.test.test_date)]} />
              <div class="flex-1 min-w-0">
                <p class="font-bold text-gray-900 text-sm truncate">{t.test.name}</p>
                <p class="text-xs text-gray-400 mt-0.5">
                  {Calendar.strftime(t.test.test_date, "%B %d, %Y")}
                </p>
              </div>
              <div class="text-right shrink-0">
                <p class={["text-lg font-extrabold", days_color(t.test.test_date)]}>
                  {Date.diff(t.test.test_date, Date.utc_today())}
                </p>
                <p class="text-[10px] text-gray-400">days</p>
              </div>
              <div :if={t.readiness} class="text-right shrink-0">
                <p class={["text-sm font-extrabold", readiness_color(t.readiness)]}>
                  {round(t.readiness.aggregate_score)}%
                </p>
                <p class="text-[10px] text-gray-400">ready</p>
              </div>
              <div class="flex gap-1.5 shrink-0">
                <.link
                  navigate={~p"/courses/#{course_id}/tests/#{t.test.id}/assess"}
                  class="text-xs font-bold bg-[#4CD964] text-white px-3 py-1.5 rounded-full hover:bg-[#3DBF55] transition-colors"
                >
                  Assess
                </.link>
                <.link
                  navigate={~p"/courses/#{course_id}/tests/#{t.test.id}/format-test"}
                  class="text-xs font-bold bg-gray-100 text-gray-600 px-3 py-1.5 rounded-full hover:bg-gray-200 transition-colors"
                >
                  Practice
                </.link>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp urgency_color(test_date) do
    days = Date.diff(test_date, Date.utc_today())

    cond do
      days < 0 -> "bg-gray-400"
      days <= 3 -> "bg-red-500"
      days <= 7 -> "bg-amber-500"
      true -> "bg-[#4CD964]"
    end
  end

  defp days_color(test_date) do
    days = Date.diff(test_date, Date.utc_today())

    cond do
      days < 0 -> "text-gray-400"
      days <= 3 -> "text-red-500"
      days <= 7 -> "text-amber-500"
      true -> "text-[#4CD964]"
    end
  end

  defp readiness_color(%{aggregate_score: score}) when score >= 70, do: "text-[#4CD964]"
  defp readiness_color(%{aggregate_score: score}) when score >= 40, do: "text-amber-500"
  defp readiness_color(_), do: "text-red-500"

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
