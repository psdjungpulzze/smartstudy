defmodule FunSheepWeb.TestScheduleLive do
  use FunSheepWeb, :live_view

  alias FunSheep.{Assessments, Courses}

  @impl true
  def mount(%{"course_id" => course_id}, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    course = Courses.get_course!(course_id)
    schedules = list_schedules(user_role_id, course_id)
    readiness_map = build_readiness_map(user_role_id, schedules)
    chapters = Courses.list_chapters_by_course(course_id)
    chapter_map = Map.new(chapters, fn ch -> {ch.id, ch} end)

    {:ok,
     assign(socket,
       page_title: "Tests - #{course.name}",
       course: course,
       course_id: course_id,
       schedules: schedules,
       readiness_map: readiness_map,
       chapter_map: chapter_map,
       today: Date.utc_today()
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    schedule = Assessments.get_test_schedule!(id)
    {:ok, _} = Assessments.delete_test_schedule(schedule)

    user_role_id = socket.assigns.current_user["user_role_id"]
    course_id = socket.assigns.course_id
    {:noreply, assign(socket, schedules: list_schedules(user_role_id, course_id))}
  end

  defp list_schedules(user_role_id, course_id) do
    if user_role_id do
      Assessments.list_test_schedules_for_course(user_role_id, course_id)
    else
      []
    end
  end

  defp build_readiness_map(nil, _schedules), do: %{}

  defp build_readiness_map(user_role_id, schedules) do
    Enum.into(schedules, %{}, fn schedule ->
      readiness = Assessments.latest_readiness(user_role_id, schedule.id)
      {schedule.id, readiness}
    end)
  end

  defp readiness_display(readiness_map, schedule_id) do
    case Map.get(readiness_map, schedule_id) do
      nil -> "N/A"
      rs -> "#{round(rs.aggregate_score)}%"
    end
  end

  defp readiness_color(readiness_map, schedule_id) do
    case Map.get(readiness_map, schedule_id) do
      nil -> "text-[#8E8E93]"
      rs when rs.aggregate_score >= 70 -> "text-[#4CD964]"
      rs when rs.aggregate_score >= 40 -> "text-[#FFCC00]"
      _rs -> "text-[#FF3B30]"
    end
  end

  defp days_remaining(test_date) do
    Date.diff(test_date, Date.utc_today())
  end

  defp urgency_color(test_date) do
    days = days_remaining(test_date)

    cond do
      days < 0 -> "bg-[#8E8E93]"
      days < 3 -> "bg-[#FF3B30]"
      days <= 7 -> "bg-[#FFCC00]"
      true -> "bg-[#4CD964]"
    end
  end

  defp scope_summary(schedule, chapter_map) do
    chapter_ids = get_in(schedule.scope, ["chapter_ids"]) || []

    names =
      chapter_ids
      |> Enum.map(fn id -> chapter_map[id] end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.position)
      |> Enum.map(& &1.name)

    case names do
      [] -> nil
      _ -> Enum.join(names, ", ")
    end
  end

  defp urgency_text_color(test_date) do
    days = days_remaining(test_date)

    cond do
      days < 0 -> "text-[#8E8E93]"
      days < 3 -> "text-[#FF3B30]"
      days <= 7 -> "text-[#FFCC00]"
      true -> "text-[#4CD964]"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="mb-4">
        <.link
          navigate={~p"/courses/#{@course_id}"}
          class="text-[#8E8E93] hover:text-[#1C1C1E] text-sm inline-flex items-center transition-colors"
        >
          <.icon name="hero-arrow-left" class="w-4 h-4 mr-1" /> Back to {@course.name}
        </.link>
      </div>
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-6 sm:mb-8">
        <h1 class="text-2xl sm:text-3xl font-bold text-[#1C1C1E]">Assessments</h1>
        <.link
          navigate={~p"/courses/#{@course_id}/tests/new"}
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 sm:py-2 rounded-full shadow-md transition-colors text-center touch-target"
        >
          Schedule New Test
        </.link>
      </div>

      <div :if={@schedules == []} class="bg-white rounded-2xl shadow-md p-8 text-center">
        <.icon name="hero-clipboard-document-check" class="w-12 h-12 text-[#8E8E93] mx-auto mb-4" />
        <p class="text-[#8E8E93] text-lg">No tests scheduled yet.</p>
        <p class="text-[#8E8E93] text-sm mt-2">
          Schedule your first test to start tracking your readiness.
        </p>
      </div>

      <div class="space-y-4">
        <div
          :for={schedule <- @schedules}
          class="bg-white rounded-2xl shadow-md p-4 sm:p-6"
        >
          <%!-- Top row: test info + days/readiness --%>
          <div class="flex items-start gap-3 sm:gap-4">
            <div class={"w-1.5 sm:w-2 h-10 sm:h-12 rounded-full shrink-0 #{urgency_color(schedule.test_date)}"} />
            <div class="flex-1 min-w-0">
              <h3 class="font-semibold text-[#1C1C1E] text-base sm:text-lg truncate">
                {schedule.name}
              </h3>
              <p class="text-sm text-[#8E8E93]">
                {if schedule.course, do: schedule.course.name, else: "Unknown Course"}
              </p>
              <p class="text-sm text-[#8E8E93]">
                {Calendar.strftime(schedule.test_date, "%B %d, %Y")}
              </p>
              <p
                :if={scope_summary(schedule, @chapter_map)}
                class="text-sm text-[#8E8E93] mt-0.5 truncate"
              >
                <.icon name="hero-book-open" class="w-3.5 h-3.5 inline-block mr-1 align-text-bottom" />
                {scope_summary(schedule, @chapter_map)}
              </p>
            </div>
            <div class="flex items-center gap-4 sm:gap-6 shrink-0">
              <div class="text-right">
                <p class={"text-xl sm:text-2xl font-bold #{urgency_text_color(schedule.test_date)}"}>
                  {days_remaining(schedule.test_date)}
                </p>
                <p class="text-[10px] sm:text-xs text-[#8E8E93]">days left</p>
              </div>
              <div class="text-right hidden sm:block">
                <p class={"text-lg font-semibold #{readiness_color(@readiness_map, schedule.id)}"}>
                  {readiness_display(@readiness_map, schedule.id)}
                </p>
                <p class="text-xs text-[#8E8E93]">readiness</p>
              </div>
            </div>
          </div>

          <%!-- Mobile readiness (visible on small screens only) --%>
          <div class="flex items-center justify-between mt-2 sm:hidden px-1">
            <span class="text-xs text-[#8E8E93]">Readiness</span>
            <span class={"text-sm font-semibold #{readiness_color(@readiness_map, schedule.id)}"}>
              {readiness_display(@readiness_map, schedule.id)}
            </span>
          </div>

          <%!-- Action buttons --%>
          <div class="flex flex-wrap items-center gap-2 mt-3 sm:mt-4 pt-3 sm:pt-0 border-t sm:border-t-0 border-gray-100">
            <.link
              navigate={~p"/courses/#{@course_id}/tests/#{schedule.id}/readiness"}
              class="bg-white border border-[#4CD964] text-[#4CD964] hover:bg-[#E8F8EB] font-medium px-4 py-2.5 sm:py-2 rounded-full text-sm transition-colors flex-1 sm:flex-none text-center touch-target"
            >
              View Readiness
            </.link>
            <.link
              navigate={~p"/courses/#{@course_id}/tests/#{schedule.id}/assess"}
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-4 py-2.5 sm:py-2 rounded-full text-sm transition-colors flex-1 sm:flex-none text-center touch-target"
            >
              Assess
            </.link>
            <.link
              navigate={~p"/courses/#{@course_id}/tests/#{schedule.id}/edit"}
              class="text-[#8E8E93] hover:text-[#1C1C1E] p-2.5 rounded-lg transition-colors touch-target"
              title="Edit test"
            >
              <.icon name="hero-pencil" class="w-5 h-5" />
            </.link>
            <button
              phx-click="delete"
              phx-value-id={schedule.id}
              data-confirm="Are you sure you want to delete this test schedule?"
              class="text-[#FF3B30] hover:text-red-700 p-2.5 rounded-lg transition-colors touch-target"
            >
              <.icon name="hero-trash" class="w-5 h-5" />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
