defmodule FunSheepWeb.TestScheduleLive do
  use FunSheepWeb, :live_view

  alias FunSheep.Assessments

  @impl true
  def mount(_params, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    schedules = list_schedules(user_role_id)
    readiness_map = build_readiness_map(user_role_id, schedules)

    {:ok,
     assign(socket,
       page_title: "My Tests",
       schedules: schedules,
       readiness_map: readiness_map,
       today: Date.utc_today()
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    schedule = Assessments.get_test_schedule!(id)
    {:ok, _} = Assessments.delete_test_schedule(schedule)

    user_role_id = socket.assigns.current_user["user_role_id"]
    {:noreply, assign(socket, schedules: list_schedules(user_role_id))}
  end

  defp list_schedules(user_role_id) do
    if user_role_id do
      Assessments.list_test_schedules_for_user(user_role_id)
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
      <div class="flex items-center justify-between mb-8">
        <h1 class="text-3xl font-bold text-[#1C1C1E]">My Tests</h1>
        <.link
          navigate={~p"/tests/new"}
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
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
          class="bg-white rounded-2xl shadow-md p-6 flex items-center justify-between"
        >
          <div class="flex items-center gap-4">
            <div class={"w-2 h-12 rounded-full #{urgency_color(schedule.test_date)}"} />
            <div>
              <h3 class="font-semibold text-[#1C1C1E] text-lg">{schedule.name}</h3>
              <p class="text-sm text-[#8E8E93]">
                {if schedule.course, do: schedule.course.name, else: "Unknown Course"}
              </p>
              <p class="text-sm text-[#8E8E93]">
                {Calendar.strftime(schedule.test_date, "%B %d, %Y")}
              </p>
            </div>
          </div>

          <div class="flex items-center gap-6">
            <div class="text-right">
              <p class={"text-2xl font-bold #{urgency_text_color(schedule.test_date)}"}>
                {days_remaining(schedule.test_date)}
              </p>
              <p class="text-xs text-[#8E8E93]">days left</p>
            </div>

            <div class="text-right">
              <p class={"text-lg font-semibold #{readiness_color(@readiness_map, schedule.id)}"}>
                {readiness_display(@readiness_map, schedule.id)}
              </p>
              <p class="text-xs text-[#8E8E93]">readiness</p>
            </div>

            <div class="flex items-center gap-2">
              <.link
                navigate={~p"/tests/#{schedule.id}/readiness"}
                class="bg-white border border-[#4CD964] text-[#4CD964] hover:bg-[#E8F8EB] font-medium px-4 py-2 rounded-full text-sm transition-colors"
              >
                View Readiness
              </.link>
              <.link
                navigate={~p"/tests/#{schedule.id}/assess"}
                class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-4 py-2 rounded-full text-sm transition-colors"
              >
                Assess
              </.link>
              <button
                phx-click="delete"
                phx-value-id={schedule.id}
                data-confirm="Are you sure you want to delete this test schedule?"
                class="text-[#FF3B30] hover:text-red-700 p-2 rounded-lg transition-colors"
              >
                <.icon name="hero-trash" class="w-5 h-5" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
