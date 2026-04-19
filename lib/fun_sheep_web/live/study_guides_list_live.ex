defmodule FunSheepWeb.StudyGuidesListLive do
  use FunSheepWeb, :live_view

  alias FunSheep.{Assessments, Courses, Learning}
  alias FunSheep.Learning.StudyGuideGenerator

  @impl true
  def mount(%{"course_id" => course_id}, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    course = Courses.get_course!(course_id)
    guides = list_guides(user_role_id, course_id)
    schedules = Assessments.list_test_schedules_for_course(user_role_id, course_id)

    {:ok,
     assign(socket,
       page_title: "Study Guides - #{course.name}",
       course: course,
       course_id: course_id,
       guides: guides,
       schedules: schedules,
       selected_schedule_id: nil
     )}
  end

  @impl true
  def handle_event("select_schedule", %{"schedule_id" => schedule_id}, socket) do
    {:noreply, assign(socket, selected_schedule_id: schedule_id)}
  end

  @impl true
  def handle_event("generate", _params, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    schedule_id = socket.assigns.selected_schedule_id

    if schedule_id && schedule_id != "" do
      case StudyGuideGenerator.generate(user_role_id, schedule_id) do
        {:ok, guide} ->
          {:noreply,
           socket
           |> put_flash(:info, "Study guide generated.")
           |> push_navigate(to: ~p"/courses/#{socket.assigns.course_id}/study-guides/#{guide.id}")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to generate study guide.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please select a test schedule first.")}
    end
  end

  defp list_guides(nil, _course_id), do: []

  defp list_guides(user_role_id, course_id) do
    Learning.list_study_guides_for_course(user_role_id, course_id)
  end

  defp guide_progress(guide) do
    progress = get_in(guide.content, ["progress"]) || %{}
    total = Map.get(progress, "total_sections", 0)
    reviewed = Map.get(progress, "sections_reviewed", 0)
    if total > 0, do: round(reviewed / total * 100), else: 0
  end

  defp guide_section_count(guide) do
    sections = get_in(guide.content, ["sections"]) || []
    length(sections)
  end

  defp guide_days_until(guide) do
    case get_in(guide.content, ["test_date"]) do
      nil -> nil
      date_str ->
        case Date.from_iso8601(date_str) do
          {:ok, date} -> Date.diff(date, Date.utc_today())
          _ -> nil
        end
    end
  end

  defp days_badge(nil), do: ""
  defp days_badge(n) when n < 0, do: "Past"
  defp days_badge(0), do: "Today!"
  defp days_badge(1), do: "Tomorrow"
  defp days_badge(n), do: "#{n}d left"

  defp days_badge_class(nil), do: ""
  defp days_badge_class(n) when n <= 1, do: "bg-[#FF3B30] text-white"
  defp days_badge_class(n) when n <= 3, do: "bg-[#FFCC00] text-[#1C1C1E]"
  defp days_badge_class(_), do: "bg-[#E5E5EA] text-[#8E8E93]"

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
      <div class="flex items-center justify-between mb-8">
        <h1 class="text-3xl font-bold text-[#1C1C1E]">Study Guides</h1>
      </div>

      <%!-- Generate New Section --%>
      <div class="bg-white rounded-2xl shadow-md p-6 mb-6">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-3">Generate New Guide</h2>
        <p class="text-sm text-[#8E8E93] mb-3">
          Creates a personalized study plan based on your latest readiness scores.
        </p>
        <div class="flex flex-col sm:flex-row sm:items-center gap-3">
          <select
            phx-change="select_schedule"
            name="schedule_id"
            class="w-full sm:flex-1 px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors"
          >
            <option value="">Select a test schedule...</option>
            <option :for={s <- @schedules} value={s.id}>
              {s.name} - {if s.course, do: s.course.name, else: "Unknown"}
            </option>
          </select>
          <button
            phx-click="generate"
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors shrink-0"
          >
            Generate
          </button>
        </div>
      </div>

      <%!-- Guides List --%>
      <div :if={@guides == []} class="bg-white rounded-2xl shadow-md p-8 text-center">
        <.icon name="hero-book-open" class="w-12 h-12 text-[#8E8E93] mx-auto mb-4" />
        <p class="text-[#8E8E93] text-lg">No study guides yet.</p>
        <p class="text-[#8E8E93] text-sm mt-2">
          Select a test schedule above to generate your first study guide.
        </p>
      </div>

      <div class="space-y-4">
        <.link
          :for={guide <- @guides}
          navigate={~p"/courses/#{@course_id}/study-guides/#{guide.id}"}
          class="bg-white rounded-2xl shadow-md p-5 hover:shadow-lg transition-shadow block"
        >
          <div class="flex items-start justify-between gap-4">
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2">
                <h3 class="font-semibold text-[#1C1C1E] text-lg truncate">
                  {get_in(guide.content, ["title"]) || "Study Guide"}
                </h3>
                <% days = guide_days_until(guide) %>
                <span
                  :if={days != nil}
                  class={"text-xs font-medium px-2 py-0.5 rounded-full #{days_badge_class(days)}"}
                >
                  {days_badge(days)}
                </span>
              </div>
              <p class="text-sm text-[#8E8E93] mt-0.5">
                {if guide.test_schedule, do: guide.test_schedule.name, else: "Unknown Test"}
              </p>

              <%!-- Progress bar --%>
              <div class="flex items-center gap-3 mt-3">
                <div class="flex-1 bg-[#E5E5EA] rounded-full h-2">
                  <div
                    class="h-2 rounded-full bg-[#4CD964] transition-all"
                    style={"width: #{guide_progress(guide)}%"}
                  />
                </div>
                <span class="text-xs text-[#8E8E93] shrink-0">
                  {guide_progress(guide)}% reviewed
                </span>
              </div>

              <div class="flex items-center gap-4 mt-2 text-xs text-[#8E8E93]">
                <span>{guide_section_count(guide)} weak areas</span>
                <span>
                  Generated {Calendar.strftime(guide.generated_at, "%B %d, %Y")}
                </span>
              </div>
            </div>

            <div class="text-center shrink-0">
              <p class="text-2xl font-bold text-[#1C1C1E]">
                {round(get_in(guide.content, ["aggregate_score"]) || 0)}%
              </p>
              <p class="text-xs text-[#8E8E93]">readiness</p>
            </div>
          </div>
        </.link>
      </div>
    </div>
    """
  end
end
