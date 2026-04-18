defmodule StudySmartWeb.CourseSearchLive do
  use StudySmartWeb, :live_view

  alias StudySmart.Courses
  alias StudySmart.Geo

  @impl true
  def mount(_params, _session, socket) do
    schools = Geo.list_schools()
    user_role_id = socket.assigns.current_user["id"]

    my_courses =
      case Ecto.UUID.cast(user_role_id) do
        {:ok, _} -> Courses.list_courses_for_user(user_role_id)
        :error -> []
      end

    {:ok,
     assign(socket,
       page_title: "My Courses",
       search_subject: "",
       search_grade: "",
       search_school_id: "",
       schools: schools,
       my_courses: my_courses,
       results: [],
       searched: false,
       confirm_delete: nil
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

  def handle_event("confirm_delete", %{"id" => course_id}, socket) do
    {:noreply, assign(socket, confirm_delete: course_id)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, confirm_delete: nil)}
  end

  def handle_event("delete_course", %{"id" => course_id}, socket) do
    course = Courses.get_course!(course_id)

    case Courses.delete_course(course) do
      {:ok, _} ->
        my_courses = Enum.reject(socket.assigns.my_courses, &(&1.id == course_id))
        results = Enum.reject(socket.assigns.results, &(&1.id == course_id))

        {:noreply,
         socket
         |> assign(my_courses: my_courses, results: results, confirm_delete: nil)
         |> put_flash(:info, "Course deleted.")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(confirm_delete: nil)
         |> put_flash(:error, "Could not delete course.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="animate-slide-up">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-extrabold text-gray-900">My Courses 📚</h1>
          <p class="text-gray-500 text-sm mt-1">Your courses and search for new ones</p>
        </div>
        <.link
          navigate={~p"/courses/new"}
          class="bg-purple-600 hover:bg-purple-700 text-white font-bold px-5 py-2.5 rounded-full shadow-md btn-bounce text-sm"
        >
          + Add New Course
        </.link>
      </div>

      <%!-- My Courses Section --%>
      <div class="mb-8">
        <div :if={@my_courses == []} class="bg-white rounded-2xl border border-gray-100 p-8 text-center">
          <div class="text-5xl mb-3 animate-float">📖</div>
          <h3 class="font-bold text-gray-900 text-lg">No courses yet!</h3>
          <p class="text-gray-500 text-sm mt-1 mb-4">
            Add your first course to start studying
          </p>
          <.link
            navigate={~p"/courses/new"}
            class="inline-block bg-purple-600 hover:bg-purple-700 text-white font-bold px-5 py-2.5 rounded-full shadow-md btn-bounce text-sm"
          >
            + Add New Course
          </.link>
        </div>

        <div :if={@my_courses != []} class="space-y-3">
          <div
            :for={{course, idx} <- Enum.with_index(@my_courses)}
            class={"bg-white rounded-2xl border border-gray-100 p-4 card-hover animate-slide-up stagger-#{rem(idx, 6) + 1}"}
          >
            <%!-- Delete confirmation overlay --%>
            <div
              :if={@confirm_delete == course.id}
              class="flex items-center justify-between gap-3 p-3 bg-red-50 rounded-xl mb-3 border border-red-100"
            >
              <p class="text-sm text-red-700 font-medium">
                Delete <strong>{course.name}</strong>? This cannot be undone.
              </p>
              <div class="flex gap-2 shrink-0">
                <button
                  phx-click="delete_course"
                  phx-value-id={course.id}
                  class="bg-red-500 hover:bg-red-600 text-white font-bold px-4 py-1.5 rounded-full text-xs"
                >
                  Delete
                </button>
                <button
                  phx-click="cancel_delete"
                  class="bg-white hover:bg-gray-50 text-gray-600 font-bold px-4 py-1.5 rounded-full text-xs border border-gray-200"
                >
                  Cancel
                </button>
              </div>
            </div>

            <div class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-xl bg-purple-50 flex items-center justify-center text-2xl shrink-0">
                {subject_emoji(course.subject)}
              </div>
              <div class="flex-1 min-w-0">
                <h3 class="font-bold text-gray-900 text-sm">{course.name}</h3>
                <div class="flex flex-wrap gap-2 mt-1.5">
                  <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-bold bg-purple-50 text-purple-600">
                    {course.subject}
                  </span>
                  <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-bold bg-cyan-50 text-cyan-600">
                    Grade {course.grade}
                  </span>
                  <span
                    :if={course.school}
                    class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-bold bg-gray-50 text-gray-500"
                  >
                    🏫 {course.school.name}
                  </span>
                </div>
                <p :if={course.description} class="text-xs text-gray-400 mt-1.5 line-clamp-1">
                  {course.description}
                </p>
              </div>
              <div class="flex items-center gap-2 shrink-0">
                <.link
                  navigate={~p"/courses/#{course.id}"}
                  class="bg-purple-600 hover:bg-purple-700 text-white font-bold px-4 py-2 rounded-full shadow-md btn-bounce text-sm"
                >
                  Open
                </.link>
                <.link
                  navigate={~p"/courses/#{course.id}/edit"}
                  class="p-2 rounded-full hover:bg-purple-50 text-gray-400 hover:text-purple-500 transition-colors"
                  aria-label="Edit course"
                >
                  <.icon name="hero-pencil-square" class="w-4 h-4" />
                </.link>
                <button
                  phx-click="confirm_delete"
                  phx-value-id={course.id}
                  class="p-2 rounded-full hover:bg-red-50 text-gray-400 hover:text-red-500 transition-colors"
                  aria-label="Delete course"
                >
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Search Section --%>
      <div class="border-t border-gray-100 pt-6">
        <h2 class="text-lg font-extrabold text-gray-900 mb-4">Find More Courses 🔍</h2>
        <div class="bg-white rounded-2xl border border-gray-100 p-5 mb-6">
          <form phx-submit="search" class="space-y-4">
            <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
              <div>
                <label class="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-1.5">
                  Subject
                </label>
                <input
                  type="text"
                  name="subject"
                  value={@search_subject}
                  placeholder="Math, Science..."
                  class="w-full px-4 py-2.5 bg-gray-50 border border-gray-100 focus:border-purple-300 focus:bg-white rounded-xl outline-none transition-all text-sm"
                />
              </div>
              <div>
                <label class="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-1.5">
                  Grade
                </label>
                <select
                  name="grade"
                  class="w-full px-4 py-2.5 bg-gray-50 border border-gray-100 focus:border-purple-300 focus:bg-white rounded-xl outline-none transition-all text-sm"
                >
                  <option value="">All Grades</option>
                  <%= for g <- ~w(K 1 2 3 4 5 6 7 8 9 10 11 12 College) do %>
                    <option value={g} selected={@search_grade == g}>{g}</option>
                  <% end %>
                </select>
              </div>
              <div>
                <label class="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-1.5">
                  School
                </label>
                <select
                  name="school_id"
                  class="w-full px-4 py-2.5 bg-gray-50 border border-gray-100 focus:border-purple-300 focus:bg-white rounded-xl outline-none transition-all text-sm"
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
            <div class="flex gap-2">
              <button
                type="submit"
                class="bg-purple-600 hover:bg-purple-700 text-white font-bold px-5 py-2 rounded-full shadow-md btn-bounce text-sm"
              >
                Search
              </button>
              <button
                type="button"
                phx-click="clear_search"
                class="bg-gray-50 hover:bg-gray-100 text-gray-600 font-bold px-5 py-2 rounded-full border border-gray-200 text-sm transition-colors"
              >
                Clear
              </button>
            </div>
          </form>
        </div>

        <%!-- Search Results --%>
        <div :if={@searched}>
          <div
            :if={@results == []}
            class="bg-white rounded-2xl border border-gray-100 p-8 text-center"
          >
            <div class="text-4xl mb-3">🔍</div>
            <h3 class="font-bold text-gray-900">No matches found</h3>
            <p class="text-gray-500 text-sm mt-1">Try different filters</p>
          </div>

          <div :if={@results != []} class="space-y-3">
            <p class="text-xs font-bold text-gray-400 uppercase tracking-wider">
              {length(@results)} course(s) found
            </p>
            <div
              :for={{course, idx} <- Enum.with_index(@results)}
              class={"bg-white rounded-2xl border border-gray-100 p-4 flex items-center gap-4 card-hover animate-slide-up stagger-#{rem(idx, 6) + 1}"}
            >
              <div class="w-12 h-12 rounded-xl bg-purple-50 flex items-center justify-center text-2xl shrink-0">
                {subject_emoji(course.subject)}
              </div>
              <div class="flex-1 min-w-0">
                <h3 class="font-bold text-gray-900 text-sm">{course.name}</h3>
                <div class="flex flex-wrap gap-2 mt-1.5">
                  <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-bold bg-purple-50 text-purple-600">
                    {course.subject}
                  </span>
                  <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-bold bg-cyan-50 text-cyan-600">
                    Grade {course.grade}
                  </span>
                  <span
                    :if={course.school}
                    class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-bold bg-gray-50 text-gray-500"
                  >
                    🏫 {course.school.name}
                  </span>
                </div>
              </div>
              <.link
                navigate={~p"/courses/#{course.id}"}
                class="bg-purple-600 hover:bg-purple-700 text-white font-bold px-4 py-2 rounded-full shadow-md btn-bounce text-sm whitespace-nowrap shrink-0"
              >
                Open
              </.link>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp subject_emoji(subject) when is_binary(subject) do
    subject_lower = String.downcase(subject)

    cond do
      String.contains?(subject_lower, "math") -> "🔢"
      String.contains?(subject_lower, "calcul") -> "🔢"
      String.contains?(subject_lower, "algebra") -> "🔢"
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
      String.contains?(subject_lower, "econ") -> "📊"
      String.contains?(subject_lower, "korean") -> "🇰🇷"
      String.contains?(subject_lower, "spanish") -> "🇪🇸"
      String.contains?(subject_lower, "french") -> "🇫🇷"
      true -> "📘"
    end
  end

  defp subject_emoji(_), do: "📘"
end
