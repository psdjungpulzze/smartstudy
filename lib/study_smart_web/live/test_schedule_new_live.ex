defmodule StudySmartWeb.TestScheduleNewLive do
  use StudySmartWeb, :live_view

  alias StudySmart.{Assessments, Courses}

  @impl true
  def mount(_params, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    courses = if user_role_id, do: Courses.list_courses_for_user(user_role_id), else: []

    changeset =
      Assessments.change_test_schedule(%Assessments.TestSchedule{}, %{})

    {:ok,
     assign(socket,
       page_title: "Schedule New Test",
       courses: courses,
       chapters: [],
       sections: [],
       selected_course_id: nil,
       selected_chapter_ids: MapSet.new(),
       selected_section_ids: MapSet.new(),
       form: to_form(changeset),
       form_name: "",
       form_test_date: ""
     )}
  end

  @impl true
  def handle_event("select_course", %{"course_id" => course_id}, socket) do
    chapters =
      if course_id != "" do
        Courses.list_chapters_by_course(course_id)
      else
        []
      end

    {:noreply,
     assign(socket,
       selected_course_id: course_id,
       chapters: chapters,
       sections: [],
       selected_chapter_ids: MapSet.new(),
       selected_section_ids: MapSet.new()
     )}
  end

  def handle_event("toggle_chapter", %{"chapter-id" => chapter_id}, socket) do
    selected = socket.assigns.selected_chapter_ids

    selected =
      if MapSet.member?(selected, chapter_id) do
        MapSet.delete(selected, chapter_id)
      else
        MapSet.put(selected, chapter_id)
      end

    {:noreply, assign(socket, selected_chapter_ids: selected)}
  end

  def handle_event("select_all_chapters", _params, socket) do
    all_ids = MapSet.new(Enum.map(socket.assigns.chapters, & &1.id))
    {:noreply, assign(socket, selected_chapter_ids: all_ids)}
  end

  def handle_event("deselect_all_chapters", _params, socket) do
    {:noreply, assign(socket, selected_chapter_ids: MapSet.new())}
  end

  def handle_event("update_form", %{"name" => name, "test_date" => test_date}, socket) do
    {:noreply, assign(socket, form_name: name, form_test_date: test_date)}
  end

  def handle_event("save", %{"name" => name, "test_date" => test_date}, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    course_id = socket.assigns.selected_course_id
    chapter_ids = MapSet.to_list(socket.assigns.selected_chapter_ids)
    section_ids = MapSet.to_list(socket.assigns.selected_section_ids)

    scope = %{"chapter_ids" => chapter_ids, "section_ids" => section_ids}

    attrs = %{
      name: name,
      test_date: test_date,
      scope: scope,
      user_role_id: user_role_id,
      course_id: course_id
    }

    case Assessments.create_test_schedule(attrs) do
      {:ok, _schedule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Test scheduled successfully!")
         |> push_navigate(to: ~p"/tests")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <div class="flex items-center gap-4 mb-8">
        <.link navigate={~p"/tests"} class="text-[#8E8E93] hover:text-[#1C1C1E] transition-colors">
          <.icon name="hero-arrow-left" class="w-6 h-6" />
        </.link>
        <h1 class="text-3xl font-bold text-[#1C1C1E]">Schedule New Test</h1>
      </div>

      <div class="bg-white rounded-2xl shadow-md p-8">
        <form phx-submit="save" phx-change="update_form" class="space-y-6">
          <div>
            <label class="block text-sm font-medium text-[#1C1C1E] mb-2">Test Name</label>
            <input
              type="text"
              name="name"
              value={@form_name}
              placeholder="e.g., Midterm Exam, Chapter 5 Quiz"
              required
              class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors"
            />
          </div>

          <div>
            <label class="block text-sm font-medium text-[#1C1C1E] mb-2">Course</label>
            <select
              name="course_id"
              phx-change="select_course"
              class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors"
            >
              <option value="">Select a course...</option>
              <option
                :for={course <- @courses}
                value={course.id}
                selected={course.id == @selected_course_id}
              >
                {course.name}
              </option>
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium text-[#1C1C1E] mb-2">Test Date</label>
            <input
              type="date"
              name="test_date"
              value={@form_test_date}
              min={Date.to_iso8601(Date.utc_today())}
              required
              class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors"
            />
          </div>

          <div :if={@chapters != []}>
            <div class="flex items-center justify-between mb-2">
              <label class="block text-sm font-medium text-[#1C1C1E]">
                Test Scope (Select Chapters)
              </label>
              <div class="flex gap-2">
                <button
                  type="button"
                  phx-click="select_all_chapters"
                  class="text-xs text-[#4CD964] hover:text-[#3DBF55] font-medium"
                >
                  Select All
                </button>
                <span class="text-[#E5E5EA]">|</span>
                <button
                  type="button"
                  phx-click="deselect_all_chapters"
                  class="text-xs text-[#8E8E93] hover:text-[#1C1C1E] font-medium"
                >
                  Deselect All
                </button>
              </div>
            </div>
            <div class="space-y-2 max-h-64 overflow-y-auto bg-[#F5F5F7] rounded-xl p-4">
              <label
                :for={chapter <- @chapters}
                class="flex items-center gap-3 p-2 rounded-lg hover:bg-white cursor-pointer transition-colors"
              >
                <input
                  type="checkbox"
                  checked={MapSet.member?(@selected_chapter_ids, chapter.id)}
                  phx-click="toggle_chapter"
                  phx-value-chapter-id={chapter.id}
                  class="w-5 h-5 rounded accent-[#4CD964]"
                />
                <span class="text-[#1C1C1E]">{chapter.name}</span>
              </label>
            </div>
            <p class="text-xs text-[#8E8E93] mt-1">
              {MapSet.size(@selected_chapter_ids)} of {length(@chapters)} chapters selected
            </p>
          </div>

          <div class="flex items-center justify-end gap-4 pt-4">
            <.link
              navigate={~p"/tests"}
              class="px-6 py-2 border border-[#E5E5EA] text-[#1C1C1E] font-medium rounded-full hover:bg-[#F5F5F7] transition-colors"
            >
              Cancel
            </.link>
            <button
              type="submit"
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
            >
              Schedule Test
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
