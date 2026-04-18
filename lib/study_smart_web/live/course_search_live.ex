defmodule StudySmartWeb.CourseSearchLive do
  use StudySmartWeb, :live_view

  alias StudySmart.Courses
  alias StudySmart.Geo

  @impl true
  def mount(_params, _session, socket) do
    schools = Geo.list_schools()

    {:ok,
     assign(socket,
       page_title: "Browse Courses",
       search_subject: "",
       search_grade: "",
       search_school_id: "",
       schools: schools,
       results: [],
       searched: false
     )}
  end

  @impl true
  def handle_event("search", params, socket) do
    filters = %{
      "subject" => params["subject"] || "",
      "grade" => params["grade"] || "",
      "school_id" => params["school_id"] || ""
    }

    results = Courses.search_courses(filters)

    {:noreply,
     assign(socket,
       results: results,
       searched: true,
       search_subject: filters["subject"],
       search_grade: filters["grade"],
       search_school_id: filters["school_id"]
     )}
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    {:noreply,
     assign(socket,
       results: [],
       searched: false,
       search_subject: "",
       search_grade: "",
       search_school_id: ""
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold text-[#1C1C1E]">Browse Courses</h1>
          <p class="text-[#8E8E93] mt-1">Search for existing courses or create a new one</p>
        </div>
        <.link
          navigate={~p"/courses/new"}
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
        >
          <.icon name="hero-plus" class="w-4 h-4 inline mr-1" /> Create New Course
        </.link>
      </div>

      <%!-- Search Form --%>
      <div class="bg-white rounded-2xl shadow-md p-6 mb-6">
        <form phx-submit="search" class="space-y-4">
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <label class="label mb-1 text-sm font-medium text-[#1C1C1E]">Subject or Name</label>
              <input
                type="text"
                name="subject"
                value={@search_subject}
                placeholder="e.g. Mathematics, Science..."
                class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors"
              />
            </div>
            <div>
              <label class="label mb-1 text-sm font-medium text-[#1C1C1E]">Grade</label>
              <select
                name="grade"
                class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors"
              >
                <option value="">All Grades</option>
                <%= for g <- ~w(1 2 3 4 5 6 7 8 9 10 11 12) do %>
                  <option value={g} selected={@search_grade == g}>Grade {g}</option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="label mb-1 text-sm font-medium text-[#1C1C1E]">School</label>
              <select
                name="school_id"
                class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors"
              >
                <option value="">All Schools</option>
                <%= for school <- @schools do %>
                  <option value={school.id} selected={@search_school_id == school.id}>
                    {school.name}
                  </option>
                <% end %>
              </select>
            </div>
          </div>
          <div class="flex gap-3">
            <button
              type="submit"
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
            >
              <.icon name="hero-magnifying-glass" class="w-4 h-4 inline mr-1" /> Search
            </button>
            <button
              type="button"
              phx-click="clear_search"
              class="bg-white hover:bg-gray-50 text-gray-700 font-medium px-6 py-2 rounded-full border border-gray-200 shadow-sm transition-colors"
            >
              Clear
            </button>
          </div>
        </form>
      </div>

      <%!-- Results --%>
      <div :if={@searched}>
        <div :if={@results == []} class="bg-white rounded-2xl shadow-md p-8 text-center">
          <.icon name="hero-magnifying-glass" class="w-12 h-12 text-[#8E8E93] mx-auto mb-3" />
          <h3 class="text-lg font-semibold text-[#1C1C1E] mb-2">No courses found</h3>
          <p class="text-[#8E8E93] mb-4">Try adjusting your search or create a new course.</p>
          <.link
            navigate={~p"/courses/new"}
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors inline-block"
          >
            Create New Course
          </.link>
        </div>

        <div :if={@results != []} class="space-y-4">
          <p class="text-sm text-[#8E8E93]">
            Found {length(@results)} course(s)
          </p>
          <div :for={course <- @results} class="bg-white rounded-2xl shadow-md p-6">
            <div class="flex items-center justify-between">
              <div>
                <h3 class="text-lg font-semibold text-[#1C1C1E]">{course.name}</h3>
                <div class="flex gap-3 mt-2">
                  <span class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-[#E8F8EB] text-[#3DBF55]">
                    {course.subject}
                  </span>
                  <span class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-blue-50 text-blue-600">
                    Grade {course.grade}
                  </span>
                  <span
                    :if={course.school}
                    class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-gray-100 text-gray-600"
                  >
                    <.icon name="hero-building-library" class="w-3 h-3 mr-1" /> {course.school.name}
                  </span>
                </div>
                <p :if={course.description} class="text-sm text-[#8E8E93] mt-2">
                  {course.description}
                </p>
              </div>
              <.link
                navigate={~p"/courses/#{course.id}"}
                class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors whitespace-nowrap"
              >
                Use This Course
              </.link>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
