defmodule StudySmartWeb.StudyGuidesListLive do
  use StudySmartWeb, :live_view

  alias StudySmart.{Assessments, Learning}
  alias StudySmart.Learning.StudyGuideGenerator

  @impl true
  def mount(_params, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    guides = list_guides(user_role_id)
    schedules = Assessments.list_test_schedules_for_user(user_role_id)

    {:ok,
     assign(socket,
       page_title: "Study Guides",
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
           |> push_navigate(to: ~p"/study-guides/#{guide.id}")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to generate study guide.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please select a test schedule first.")}
    end
  end

  defp list_guides(nil), do: []

  defp list_guides(user_role_id) do
    Learning.list_study_guides_for_user(user_role_id)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="flex items-center justify-between mb-8">
        <h1 class="text-3xl font-bold text-[#1C1C1E]">Study Guides</h1>
      </div>

      <%!-- Generate New Section --%>
      <div class="bg-white rounded-2xl shadow-md p-6 mb-6">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-3">Generate New Guide</h2>
        <div class="flex items-center gap-3">
          <select
            phx-change="select_schedule"
            name="schedule_id"
            class="flex-1 px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors"
          >
            <option value="">Select a test schedule...</option>
            <option :for={s <- @schedules} value={s.id}>
              {s.name} - {if s.course, do: s.course.name, else: "Unknown"}
            </option>
          </select>
          <button
            phx-click="generate"
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
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
          navigate={~p"/study-guides/#{guide.id}"}
          class="bg-white rounded-2xl shadow-md p-6 flex items-center justify-between hover:shadow-lg transition-shadow block"
        >
          <div>
            <h3 class="font-semibold text-[#1C1C1E] text-lg">
              {get_in(guide.content, ["title"]) || "Study Guide"}
            </h3>
            <p class="text-sm text-[#8E8E93]">
              {if guide.test_schedule, do: guide.test_schedule.name, else: "Unknown Test"}
            </p>
            <p class="text-xs text-[#8E8E93] mt-1">
              Generated: {Calendar.strftime(guide.generated_at, "%B %d, %Y at %H:%M")}
            </p>
          </div>
          <div class="text-right">
            <p class="text-2xl font-bold text-[#1C1C1E]">
              {round(get_in(guide.content, ["aggregate_score"]) || 0)}%
            </p>
            <p class="text-xs text-[#8E8E93]">score at generation</p>
          </div>
        </.link>
      </div>
    </div>
    """
  end
end
