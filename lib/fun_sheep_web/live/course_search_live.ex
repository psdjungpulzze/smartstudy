defmodule FunSheepWeb.CourseSearchLive do
  use FunSheepWeb, :live_view

  import FunSheepWeb.TextbookBanner

  alias FunSheep.{Accounts, Courses, Assessments, Enrollments}
  alias FunSheep.Geo

  @impl true
  def mount(_params, _session, socket) do
    user_role_id = socket.assigns.current_user["id"]

    {my_courses, enrolled_course_ids, nearby_courses, user_grade, user_school_id, tests_by_course} =
      with {:ok, _} <- Ecto.UUID.cast(user_role_id),
           %{} = user_role <- Accounts.get_user_role(user_role_id) do
        mine = Courses.list_user_courses(user_role_id)
        enrolled_ids = Enrollments.enrolled_course_ids(user_role_id)
        nearby = Courses.list_nearby_courses(user_role.school_id, user_role.grade, user_role_id)
        tests = Assessments.list_upcoming_grouped_by_course(user_role_id)
        {mine, enrolled_ids, nearby, user_role.grade, user_role.school_id, tests}
      else
        _ -> {[], MapSet.new(), [], nil, nil, %{}}
      end

    textbook_statuses = Map.new(my_courses, &{&1.id, Courses.textbook_status(&1)})

    socket =
      socket
      |> assign(
        page_title: "My Courses",
        search_subject: "",
        search_grade: "",
        search_school_id: "",
        schools: [],
        my_courses: my_courses,
        enrolled_course_ids: enrolled_course_ids,
        nearby_courses: nearby_courses,
        textbook_statuses: textbook_statuses,
        user_grade: user_grade,
        user_school_id: user_school_id,
        tests_by_course: tests_by_course,
        expanded_courses: MapSet.new(),
        results: [],
        searched: false,
        show_search: false,
        confirm_delete: nil
      )
      |> FunSheepWeb.LiveHelpers.assign_tutorial(
        key: "course_search",
        title: "Your courses live here",
        subtitle: "Browse, search, and create courses.",
        steps: [
          %{
            emoji: "📖",
            title: "My courses",
            body: "Everything you've already added shows up at the top."
          },
          %{
            emoji: "🔍",
            title: "Search",
            body: "Find courses by subject, grade, or school."
          },
          %{
            emoji: "✨",
            title: "Create new",
            body: "Don't see it? Create a course from your own materials."
          }
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_course", %{"id" => course_id}, socket) do
    expanded = socket.assigns.expanded_courses

    expanded =
      if MapSet.member?(expanded, course_id) do
        MapSet.delete(expanded, course_id)
      else
        MapSet.put(expanded, course_id)
      end

    {:noreply, assign(socket, expanded_courses: expanded)}
  end

  def handle_event("search", params, socket) do
    filters = %{
      "subject" => params["subject"] || "",
      "grade" => params["grade"] || "",
      "school_id" => params["school_id"] || ""
    }

    results = Courses.search_courses(filters, socket.assigns.current_user["id"])

    {:noreply,
     assign(socket,
       results: results,
       searched: true,
       search_subject: filters["subject"],
       search_grade: filters["grade"],
       search_school_id: filters["school_id"]
     )}
  end

  def handle_event("toggle_search", _params, socket) do
    socket =
      if socket.assigns.show_search do
        assign(socket, show_search: false)
      else
        schools =
          if socket.assigns.schools == [], do: Geo.list_schools(), else: socket.assigns.schools

        assign(socket, show_search: true, schools: schools)
      end

    {:noreply, socket}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply,
     assign(socket,
       results: [],
       searched: false,
       show_search: false,
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

  def handle_event("select_course", %{"id" => course_id}, socket) do
    user_role_id = socket.assigns.current_user["id"]

    case Enrollments.enroll(user_role_id, course_id) do
      {:ok, _} ->
        course = Courses.get_course!(course_id) |> FunSheep.Repo.preload(:school)
        my_courses = [course | socket.assigns.my_courses]
        enrolled_course_ids = MapSet.put(socket.assigns.enrolled_course_ids, course_id)
        nearby_courses = Enum.reject(socket.assigns.nearby_courses, &(&1.id == course_id))
        results = Enum.reject(socket.assigns.results, &(&1.id == course_id))

        {:noreply,
         socket
         |> assign(
           my_courses: my_courses,
           enrolled_course_ids: enrolled_course_ids,
           nearby_courses: nearby_courses,
           results: results
         )
         |> put_flash(:info, "Course added to My Courses!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add course.")}
    end
  end

  def handle_event("archive_course", %{"id" => course_id}, socket) do
    user_role_id = socket.assigns.current_user["id"]

    case Enrollments.archive(user_role_id, course_id) do
      {:ok, _} ->
        my_courses = Enum.reject(socket.assigns.my_courses, &(&1.id == course_id))
        enrolled_course_ids = MapSet.delete(socket.assigns.enrolled_course_ids, course_id)

        {:noreply,
         socket
         |> assign(my_courses: my_courses, enrolled_course_ids: enrolled_course_ids)
         |> put_flash(:info, "Course archived.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not archive course.")}
    end
  end

  def handle_event("delete_enrollment", %{"id" => course_id}, socket) do
    user_role_id = socket.assigns.current_user["id"]

    case Enrollments.soft_delete(user_role_id, course_id) do
      {:ok, _} ->
        my_courses = Enum.reject(socket.assigns.my_courses, &(&1.id == course_id))
        enrolled_course_ids = MapSet.delete(socket.assigns.enrolled_course_ids, course_id)

        {:noreply,
         socket
         |> assign(my_courses: my_courses, enrolled_course_ids: enrolled_course_ids)
         |> put_flash(:info, "Course removed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove course.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="animate-slide-up">
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-5 sm:mb-6">
        <div>
          <h1 class="text-xl sm:text-2xl font-extrabold text-gray-900">My Courses 📚</h1>
          <p class="text-gray-500 text-sm mt-0.5 sm:mt-1">Your courses and upcoming tests</p>
        </div>
        <.link
          navigate={~p"/courses/new"}
          class="bg-purple-600 hover:bg-purple-700 text-white font-bold px-5 py-3 sm:py-2.5 rounded-full shadow-md btn-bounce text-sm touch-target inline-flex items-center justify-center self-stretch sm:self-auto"
        >
          + Add New Course
        </.link>
      </div>

      <%!-- My Courses with Expandable Tests --%>
      <div class="mb-8">
        <div
          :if={@my_courses == []}
          class="bg-white rounded-2xl border border-gray-100 p-8 text-center"
        >
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
          <.expandable_course_row
            :for={{course, idx} <- Enum.with_index(@my_courses)}
            course={course}
            idx={idx}
            expanded={MapSet.member?(@expanded_courses, course.id)}
            tests={Map.get(@tests_by_course, course.id, [])}
            confirm_delete={@confirm_delete}
            textbook_status={Map.get(@textbook_statuses, course.id)}
            is_enrolled={MapSet.member?(@enrolled_course_ids, course.id)}
          />
        </div>
      </div>

      <%!-- Find More Courses Section --%>
      <div class="border-t border-gray-100 pt-6">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-extrabold text-gray-900">Find More Courses 🔍</h2>
          <button
            phx-click="toggle_search"
            class="text-sm font-bold text-gray-500 hover:text-gray-700 px-3 py-1.5 rounded-lg hover:bg-gray-50 transition-colors flex items-center gap-1.5"
          >
            <.icon name="hero-magnifying-glass" class="w-4 h-4" /> Search
          </button>
        </div>

        <%!-- Search Panel (collapsible) --%>
        <div
          :if={@show_search}
          class="bg-white rounded-2xl border border-gray-100 p-4 sm:p-5 mb-5 sm:mb-6 animate-slide-up"
        >
          <form phx-submit="search" class="space-y-3 sm:space-y-4">
            <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
              <div>
                <label class="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-1.5">
                  Subject
                </label>
                <input
                  type="text"
                  name="subject"
                  value={@search_subject}
                  placeholder="Math, Science..."
                  class="w-full px-4 py-3 sm:py-2.5 bg-gray-50 border border-gray-100 focus:border-purple-300 focus:bg-white rounded-xl outline-none transition-all text-base sm:text-sm"
                />
              </div>
              <div>
                <label class="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-1.5">
                  Grade
                </label>
                <select
                  name="grade"
                  class="w-full px-4 py-3 sm:py-2.5 bg-gray-50 border border-gray-100 focus:border-purple-300 focus:bg-white rounded-xl outline-none transition-all text-base sm:text-sm"
                >
                  <option value="">All Grades</option>
                  <%= for g <- ~w(K 1 2 3 4 5 6 7 8 9 10 11 12 College) do %>
                    <option value={g} selected={@search_grade == g}>{g}</option>
                  <% end %>
                </select>
              </div>
              <div class="sm:col-span-2 md:col-span-1">
                <label class="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-1.5">
                  School
                </label>
                <select
                  name="school_id"
                  class="w-full px-4 py-3 sm:py-2.5 bg-gray-50 border border-gray-100 focus:border-purple-300 focus:bg-white rounded-xl outline-none transition-all text-base sm:text-sm"
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
                class="bg-purple-600 hover:bg-purple-700 text-white font-bold px-5 py-3 sm:py-2 rounded-full shadow-md btn-bounce text-sm flex-1 sm:flex-none touch-target"
              >
                Search
              </button>
              <button
                type="button"
                phx-click="clear_search"
                class="bg-gray-50 hover:bg-gray-100 text-gray-600 font-bold px-5 py-3 sm:py-2 rounded-full border border-gray-200 text-sm transition-colors flex-1 sm:flex-none touch-target"
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
            <.course_card :for={{course, idx} <- Enum.with_index(@results)} course={course} idx={idx} />
          </div>
        </div>

        <%!-- Nearby Courses (auto-loaded) --%>
        <div :if={!@searched}>
          <div
            :if={@nearby_courses == []}
            class="bg-white rounded-2xl border border-gray-100 p-8 text-center"
          >
            <div class="text-4xl mb-3">📚</div>
            <h3 class="font-bold text-gray-900">No nearby courses yet</h3>
            <p class="text-gray-500 text-sm mt-1">
              No courses found for your school and grade level. Try searching with different criteria.
            </p>
          </div>

          <div :if={@nearby_courses != []} class="space-y-3">
            <p class="text-xs font-bold text-gray-400 uppercase tracking-wider">
              {length(@nearby_courses)} course(s) near your grade level
            </p>
            <.course_card
              :for={{course, idx} <- Enum.with_index(@nearby_courses)}
              course={course}
              idx={idx}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Expandable Course Row ────────────────────────────────────────────────

  attr :course, :any, required: true
  attr :idx, :integer, required: true
  attr :expanded, :boolean, required: true
  attr :tests, :list, default: []
  attr :confirm_delete, :string, default: nil
  attr :textbook_status, :map, default: nil
  attr :is_enrolled, :boolean, default: false

  defp expandable_course_row(assigns) do
    test_count = length(assigns.tests)
    assigns = assign(assigns, test_count: test_count)

    ~H"""
    <div class={"bg-white rounded-2xl border border-gray-100 overflow-hidden animate-slide-up stagger-#{rem(@idx, 6) + 1}"}>
      <%!-- Delete confirmation overlay --%>
      <div
        :if={@confirm_delete == @course.id}
        class="flex flex-col sm:flex-row sm:items-center justify-between gap-2 sm:gap-3 p-3 bg-red-50 border-b border-red-100"
      >
        <p class="text-sm text-red-700 font-medium">
          Delete <strong class="truncate">{@course.name}</strong>? This cannot be undone.
        </p>
        <div class="flex gap-2 shrink-0">
          <button
            phx-click="delete_course"
            phx-value-id={@course.id}
            class="bg-red-500 hover:bg-red-600 text-white font-bold px-4 py-2 sm:py-1.5 rounded-full text-xs flex-1 sm:flex-none touch-target"
          >
            Delete
          </button>
          <button
            phx-click="cancel_delete"
            class="bg-white hover:bg-gray-50 text-gray-600 font-bold px-4 py-2 sm:py-1.5 rounded-full text-xs border border-gray-200 flex-1 sm:flex-none touch-target"
          >
            Cancel
          </button>
        </div>
      </div>

      <%!-- Course header row (clickable to expand) --%>
      <button
        type="button"
        phx-click="toggle_course"
        phx-value-id={@course.id}
        class="w-full p-3 sm:p-4 flex items-center gap-3 sm:gap-4 hover:bg-gray-50 transition-colors text-left touch-target"
      >
        <div class="w-10 h-10 sm:w-12 sm:h-12 rounded-xl bg-purple-50 flex items-center justify-center text-xl sm:text-2xl shrink-0">
          {subject_emoji(@course.subject)}
        </div>
        <div class="flex-1 min-w-0">
          <h3 class="font-bold text-gray-900 text-sm truncate">{@course.name}</h3>
          <div class="flex flex-wrap gap-1.5 sm:gap-2 mt-1">
            <span class="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] sm:text-xs font-bold bg-purple-50 text-purple-600">
              {@course.subject}
            </span>
            <span class="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] sm:text-xs font-bold bg-cyan-50 text-cyan-600">
              {FunSheep.Courses.format_grades(@course.grades)}
            </span>
            <span
              :if={@course.school}
              class="hidden sm:inline-flex items-center px-2 py-0.5 rounded-full text-xs font-bold bg-gray-50 text-gray-500"
            >
              🏫 {@course.school.name}
            </span>
            <span
              :if={@test_count > 0}
              class="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] sm:text-xs font-bold bg-amber-50 text-amber-600"
            >
              {@test_count} test{if @test_count != 1, do: "s"}
            </span>
            <.compact_badge :if={@textbook_status} status={@textbook_status} />
          </div>
        </div>
        <div class="flex items-center shrink-0">
          <.icon
            name={if @expanded, do: "hero-chevron-down", else: "hero-chevron-right"}
            class="w-5 h-5 text-gray-400 transition-transform"
          />
        </div>
      </button>

      <%!-- Expanded: tests + actions --%>
      <div
        :if={@expanded}
        class="border-t border-gray-100 bg-gray-50 px-3 sm:px-4 py-3 animate-slide-up"
      >
        <%!-- Textbook banner (only when not complete) --%>
        <.full_banner
          :if={@textbook_status && @textbook_status.status != :complete}
          status={@textbook_status}
          course_id={@course.id}
          cta_navigate={~p"/courses/#{@course.id}?upload=1"}
          class="!mb-3"
        />

        <%!-- Upcoming tests --%>
        <div :if={@tests != []} class="space-y-2 mb-3">
          <.test_row :for={entry <- @tests} entry={entry} course_id={@course.id} />
        </div>

        <div :if={@tests == []} class="text-sm text-gray-500 py-2 text-center">
          No upcoming tests scheduled
        </div>

        <%!-- Action buttons - stack on mobile --%>
        <div class="flex flex-wrap items-center gap-2 pt-2 border-t border-gray-200">
          <.link
            navigate={~p"/courses/#{@course.id}"}
            class="bg-white hover:bg-gray-100 text-gray-700 font-bold px-4 py-2.5 sm:py-2 rounded-full border border-gray-200 text-xs touch-target flex-1 sm:flex-none text-center"
          >
            Open Course
          </.link>
          <%!-- Creator actions --%>
          <div :if={!@is_enrolled} class="flex items-center gap-2 flex-wrap flex-1 sm:flex-none">
            <.link
              navigate={~p"/courses/#{@course.id}/tests/new"}
              class="bg-purple-600 hover:bg-purple-700 text-white font-bold px-4 py-2.5 sm:py-2 rounded-full shadow-md text-xs touch-target flex-1 sm:flex-none text-center"
            >
              + Schedule Test
            </.link>
            <div class="flex items-center gap-1 ml-auto">
              <.link
                navigate={~p"/courses/#{@course.id}/edit"}
                class="p-2.5 rounded-full hover:bg-purple-50 text-gray-400 hover:text-purple-500 transition-colors touch-target"
                aria-label="Edit course"
              >
                <.icon name="hero-pencil-square" class="w-4 h-4" />
              </.link>
              <button
                phx-click="confirm_delete"
                phx-value-id={@course.id}
                class="p-2.5 rounded-full hover:bg-red-50 text-gray-400 hover:text-red-500 transition-colors touch-target"
                aria-label="Delete course"
              >
                <.icon name="hero-trash" class="w-4 h-4" />
              </button>
            </div>
          </div>
          <%!-- Enrolled student actions --%>
          <div :if={@is_enrolled} class="flex items-center gap-2 ml-auto">
            <button
              phx-click="archive_course"
              phx-value-id={@course.id}
              class="text-xs font-bold text-gray-500 hover:text-amber-600 px-3 py-2 sm:py-1.5 rounded-full border border-gray-200 hover:border-amber-200 hover:bg-amber-50 transition-colors touch-target"
            >
              Archive
            </button>
            <button
              phx-click="delete_enrollment"
              phx-value-id={@course.id}
              data-confirm="Remove this course from your account? This cannot be undone."
              class="text-xs font-bold text-gray-400 hover:text-red-500 px-3 py-2 sm:py-1.5 rounded-full border border-gray-200 hover:border-red-200 hover:bg-red-50 transition-colors touch-target"
            >
              Delete
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Test Row within expanded course ─────────────────────────────────────

  attr :entry, :map, required: true
  attr :course_id, :string, required: true

  defp test_row(assigns) do
    schedule = assigns.entry.schedule
    readiness = assigns.entry.readiness
    days_left = Date.diff(schedule.test_date, Date.utc_today())

    readiness_pct =
      if readiness, do: round(readiness.aggregate_score), else: nil

    assigns =
      assign(assigns,
        schedule: schedule,
        days_left: days_left,
        readiness_pct: readiness_pct,
        urgency_color: urgency_color(days_left),
        readiness_color: readiness_color(readiness_pct)
      )

    ~H"""
    <.link
      navigate={~p"/courses/#{@course_id}/tests/#{@schedule.id}/readiness"}
      class="flex items-center gap-2.5 sm:gap-3 p-3 bg-white rounded-xl border border-gray-100 hover:border-purple-200 transition-colors touch-target"
    >
      <%!-- Urgency indicator --%>
      <div class={"w-1 h-10 rounded-full shrink-0 #{@urgency_color}"} />

      <%!-- Test info --%>
      <div class="flex-1 min-w-0">
        <p class="font-bold text-gray-900 text-sm truncate">{@schedule.name}</p>
        <p class="text-xs text-gray-500">
          {Calendar.strftime(@schedule.test_date, "%b %d, %Y")}
        </p>
      </div>

      <%!-- Days left --%>
      <div class="text-right shrink-0">
        <p class={"text-lg font-extrabold #{@urgency_color |> String.replace("bg-", "text-")}"}>
          {@days_left}d
        </p>
      </div>

      <%!-- Readiness --%>
      <div :if={@readiness_pct} class="text-right shrink-0 w-14">
        <p class={"text-sm font-bold #{@readiness_color}"}>{@readiness_pct}%</p>
        <p class="text-xs text-gray-400">ready</p>
      </div>
      <div :if={!@readiness_pct} class="text-right shrink-0 w-14">
        <p class="text-xs text-gray-400">Not assessed</p>
      </div>
    </.link>
    """
  end

  # ── Course Card (for search results / nearby) ───────────────────────────

  attr :course, :any, required: true
  attr :idx, :integer, required: true

  defp course_card(assigns) do
    ~H"""
    <div class={"bg-white rounded-2xl border border-gray-100 p-3 sm:p-4 flex items-center gap-3 sm:gap-4 card-hover animate-slide-up stagger-#{rem(@idx, 6) + 1}"}>
      <div class="w-10 h-10 sm:w-12 sm:h-12 rounded-xl bg-purple-50 flex items-center justify-center text-xl sm:text-2xl shrink-0">
        {subject_emoji(@course.subject)}
      </div>
      <div class="flex-1 min-w-0">
        <h3 class="font-bold text-gray-900 text-sm truncate">{@course.name}</h3>
        <div class="flex flex-wrap gap-1.5 sm:gap-2 mt-1">
          <span class="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] sm:text-xs font-bold bg-purple-50 text-purple-600">
            {@course.subject}
          </span>
          <span class="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] sm:text-xs font-bold bg-cyan-50 text-cyan-600">
            Grade {@course.grade}
          </span>
          <span
            :if={@course.school}
            class="hidden sm:inline-flex items-center px-2 py-0.5 rounded-full text-xs font-bold bg-gray-50 text-gray-500"
          >
            🏫 {@course.school.name}
          </span>
        </div>
      </div>
      <div class="flex items-center gap-2 shrink-0">
        <.link
          navigate={~p"/courses/#{@course.id}"}
          class="text-xs font-bold text-gray-600 hover:text-purple-600 px-3 py-2 sm:py-1.5 rounded-full border border-gray-200 hover:border-purple-200 hover:bg-purple-50 transition-colors whitespace-nowrap touch-target"
        >
          Preview
        </.link>
        <button
          phx-click="select_course"
          phx-value-id={@course.id}
          class="bg-purple-600 hover:bg-purple-700 text-white font-bold px-4 py-2.5 sm:py-2 rounded-full shadow-md btn-bounce text-xs whitespace-nowrap touch-target"
        >
          Select
        </button>
      </div>
    </div>
    """
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp urgency_color(days) when days <= 2, do: "bg-red-500"
  defp urgency_color(days) when days <= 7, do: "bg-orange-400"
  defp urgency_color(days) when days <= 14, do: "bg-amber-400"
  defp urgency_color(_), do: "bg-green-400"

  defp readiness_color(nil), do: "text-gray-400"
  defp readiness_color(pct) when pct >= 70, do: "text-green-600"
  defp readiness_color(pct) when pct >= 40, do: "text-amber-600"
  defp readiness_color(_), do: "text-red-500"

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
