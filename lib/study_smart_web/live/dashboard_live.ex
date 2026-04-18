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
       page_title: "Student Dashboard",
       course_stats: course_stats
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold text-[#1C1C1E]">Student Dashboard</h1>
      <p class="text-[#8E8E93] mt-2">Welcome back, {@current_user["display_name"]}!</p>

      <%!-- Summary Cards --%>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mt-8">
        <.dashboard_card
          title="My Courses"
          count={to_string(length(@course_stats))}
          description="Enrolled courses"
          icon="hero-book-open"
        />
        <.dashboard_card
          title="Assessments"
          count="0"
          description="Pending assessments"
          icon="hero-clipboard-document-check"
        />
        <.dashboard_card
          title="Study Guides"
          count="0"
          description="Available guides"
          icon="hero-document-text"
        />
      </div>

      <%!-- My Courses Section --%>
      <div class="mt-10">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-semibold text-[#1C1C1E]">My Courses</h2>
          <div class="flex gap-3">
            <.link
              navigate={~p"/courses"}
              class="bg-white hover:bg-gray-50 text-gray-700 font-medium px-4 py-2 rounded-full border border-gray-200 shadow-sm transition-colors text-sm"
            >
              <.icon name="hero-magnifying-glass" class="w-4 h-4 inline mr-1" /> Browse Courses
            </.link>
            <.link
              navigate={~p"/courses/new"}
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-4 py-2 rounded-full shadow-md transition-colors text-sm"
            >
              <.icon name="hero-plus" class="w-4 h-4 inline mr-1" /> Create Course
            </.link>
          </div>
        </div>

        <div :if={@course_stats == []} class="bg-white rounded-2xl shadow-md p-8 text-center">
          <.icon name="hero-book-open" class="w-12 h-12 text-[#8E8E93] mx-auto mb-3" />
          <h3 class="text-lg font-semibold text-[#1C1C1E] mb-2">No courses yet</h3>
          <p class="text-[#8E8E93] mb-4">
            Get started by browsing existing courses or creating a new one.
          </p>
          <.link
            navigate={~p"/courses"}
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors inline-block"
          >
            Browse Courses
          </.link>
        </div>

        <div :if={@course_stats != []} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <.link
            :for={stat <- @course_stats}
            navigate={~p"/courses/#{stat.course.id}"}
            class="bg-white rounded-2xl shadow-md p-6 hover:shadow-lg transition-shadow block"
          >
            <h3 class="font-semibold text-[#1C1C1E] mb-2">{stat.course.name}</h3>
            <div class="flex gap-2 mb-3">
              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-[#E8F8EB] text-[#3DBF55]">
                {stat.course.subject}
              </span>
              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-blue-50 text-blue-600">
                Grade {stat.course.grade}
              </span>
            </div>
            <div class="flex gap-4 text-sm text-[#8E8E93]">
              <span>
                <.icon name="hero-book-open" class="w-4 h-4 inline mr-1" />
                {stat.chapter_count} chapters
              </span>
              <span>
                <.icon name="hero-question-mark-circle" class="w-4 h-4 inline mr-1" />
                {stat.question_count} questions
              </span>
            </div>
          </.link>
        </div>
      </div>

      <%!-- Upcoming Tests Placeholder --%>
      <div class="mt-10">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-4">Upcoming Tests</h2>
        <div class="bg-white rounded-2xl shadow-md p-8 text-center">
          <.icon name="hero-calendar" class="w-12 h-12 text-[#8E8E93] mx-auto mb-3" />
          <p class="text-[#8E8E93]">No upcoming tests scheduled.</p>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :count, :string, required: true
  attr :description, :string, required: true
  attr :icon, :string, required: true

  defp dashboard_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="font-semibold text-[#1C1C1E]">{@title}</h3>
        <.icon name={@icon} class="w-5 h-5 text-[#8E8E93]" />
      </div>
      <p class="text-3xl font-bold text-[#4CD964]">{@count}</p>
      <p class="text-sm text-[#8E8E93] mt-1">{@description}</p>
    </div>
    """
  end
end
