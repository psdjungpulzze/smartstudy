defmodule FunSheepWeb.StudentOnboardingLive do
  @moduledoc """
  5-step student onboarding wizard.

  Step 1: Display name + grade
  Step 2: School search (optional/skippable)
  Step 3: Course catalog with one-click enrollment
  Step 4: Follow classmates
  Step 5: Done screen
  """

  use FunSheepWeb, :live_view

  alias FunSheep.{Accounts, Courses, Enrollments, Geo, Social}

  @grade_options ~w(K 1 2 3 4 5 6 7 8 9 10 11 12 College Adult)

  @impl true
  def mount(_params, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]

    user_role =
      case Ecto.UUID.cast(user_role_id) do
        {:ok, _} -> Accounts.get_user_role!(user_role_id)
        :error -> nil
      end

    {:ok,
     assign(socket,
       page_title: "Get Started",
       step: 1,
       user_role: user_role,
       display_name: (user_role && user_role.display_name) || "",
       grade: (user_role && user_role.grade) || nil,
       school: (user_role && user_role.school_id && Geo.get_school(user_role.school_id)) || nil,
       school_search: "",
       school_results: [],
       available_courses: [],
       selected_course_ids: MapSet.new(),
       enrolled_courses: [],
       error: nil,
       grade_options: @grade_options,
       invite_email: "",
       invite_sent: false,
       other_school_courses: [],
       show_other_courses: false,
       onboarding_peers: [],
       followed_in_onboarding: MapSet.new()
     )}
  end

  @impl true
  def handle_params(%{"step" => "done"}, _uri, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    user_role = Accounts.get_user_role!(user_role_id)

    unless Accounts.onboarding_complete?(user_role) do
      Accounts.complete_onboarding(user_role)
    end

    {:noreply, assign(socket, step: 5)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_display_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, display_name: name)}
  end

  def handle_event("select_grade", %{"grade" => grade}, socket) do
    {:noreply, assign(socket, grade: grade)}
  end

  def handle_event("step1_next", _params, socket) do
    if socket.assigns.grade == nil do
      {:noreply, assign(socket, error: "Please select your grade to continue.")}
    else
      user_role_id = socket.assigns.current_user["user_role_id"]

      Accounts.update_user_role(Accounts.get_user_role!(user_role_id), %{
        display_name: socket.assigns.display_name,
        grade: socket.assigns.grade
      })

      {:noreply, assign(socket, step: 2, error: nil)}
    end
  end

  def handle_event("search_school", %{"query" => query}, socket) do
    results = Geo.search_schools(query, limit: 10)
    {:noreply, assign(socket, school_search: query, school_results: results)}
  end

  def handle_event("select_school", %{"school_id" => school_id}, socket) do
    school = Geo.get_school(school_id)

    {:noreply,
     assign(socket,
       school: school,
       school_results: [],
       school_search: (school && school.name) || ""
     )}
  end

  def handle_event("clear_school", _params, socket) do
    {:noreply, assign(socket, school: nil, school_search: "", school_results: [])}
  end

  def handle_event("step2_next", _params, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]

    if socket.assigns.school do
      Accounts.update_user_role(Accounts.get_user_role!(user_role_id), %{
        school_id: socket.assigns.school.id
      })
    end

    courses = load_step3_courses(socket)
    other_courses = if courses == [], do: load_other_courses(socket), else: []

    {:noreply,
     assign(socket, step: 3, available_courses: courses, other_school_courses: other_courses)}
  end

  def handle_event("step2_skip", _params, socket) do
    courses = load_step3_courses(socket)
    other_courses = if courses == [], do: load_other_courses(socket), else: []

    {:noreply,
     assign(socket, step: 3, available_courses: courses, other_school_courses: other_courses)}
  end

  def handle_event("toggle_course", %{"course_id" => course_id}, socket) do
    selected = socket.assigns.selected_course_ids

    new_selected =
      if MapSet.member?(selected, course_id) do
        MapSet.delete(selected, course_id)
      else
        MapSet.put(selected, course_id)
      end

    {:noreply, assign(socket, selected_course_ids: new_selected)}
  end

  def handle_event("step3_continue", _params, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    course_ids = MapSet.to_list(socket.assigns.selected_course_ids)

    {:ok, enrolled} =
      if course_ids != [] do
        Enrollments.bulk_enroll(user_role_id, course_ids, "onboarding")
      else
        {:ok, []}
      end

    user_role = Accounts.get_user_role!(user_role_id)
    Accounts.complete_onboarding(user_role)

    peers = Social.school_peers(user_role_id, limit: 8)
    {:noreply, assign(socket, step: 4, enrolled_courses: enrolled, onboarding_peers: peers)}
  end

  def handle_event("onboarding_follow", %{"id" => target_id}, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    Social.follow(user_role_id, target_id, "suggested_school")
    followed = MapSet.put(socket.assigns.followed_in_onboarding, target_id)
    {:noreply, assign(socket, followed_in_onboarding: followed)}
  end

  def handle_event("step4_done", _params, socket) do
    {:noreply, assign(socket, step: 5)}
  end

  def handle_event("invite_teacher_email", %{"email" => email}, socket) do
    {:noreply, assign(socket, invite_email: email)}
  end

  def handle_event("send_teacher_invite", _params, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    email = socket.assigns.invite_email

    case Accounts.invite_guardian_by_student(user_role_id, email, :teacher) do
      {:ok, _} ->
        user_role = Accounts.get_user_role!(user_role_id)
        Accounts.complete_onboarding(user_role)
        {:noreply, assign(socket, invite_sent: true, step: 4)}

      {:error, _} ->
        {:noreply,
         assign(socket, error: "Could not send invite. Please check the email address.")}
    end
  end

  def handle_event("toggle_other_courses", _params, socket) do
    {:noreply, assign(socket, show_other_courses: !socket.assigns.show_other_courses)}
  end

  defp load_step3_courses(%{assigns: %{school: nil, grade: grade}})
       when not is_nil(grade) do
    Courses.list_courses_by_grade(grade)
  end

  defp load_step3_courses(%{assigns: %{school: school, grade: grade}})
       when not is_nil(school) and not is_nil(grade) do
    Courses.list_courses_for_student(school.id, grade)
  end

  defp load_step3_courses(_), do: []

  defp load_other_courses(%{assigns: %{grade: grade}}) when not is_nil(grade) do
    Courses.list_courses_by_grade(grade)
  end

  defp load_other_courses(_), do: []

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F5F7] dark:bg-[#1C1C1E] flex flex-col items-center justify-start py-8 px-4">
      <div class="w-full max-w-lg">
        <%!-- Progress indicator --%>
        <div class="flex items-center justify-center gap-2 mb-8">
          <%= for i <- 1..5 do %>
            <div class={[
              "h-2 rounded-full transition-all duration-300",
              if(i <= @step, do: "bg-[#4CD964] w-8", else: "bg-gray-200 dark:bg-gray-700 w-4")
            ]} />
          <% end %>
          <span class="text-xs text-gray-500 ml-2">Step {@step} of 5</span>
        </div>

        <%= case @step do %>
          <% 1 -> %>
            {render_step1(assigns)}
          <% 2 -> %>
            {render_step2(assigns)}
          <% 3 -> %>
            {render_step3(assigns)}
          <% 4 -> %>
            {render_step4(assigns)}
          <% 5 -> %>
            {render_step5(assigns)}
        <% end %>
      </div>
    </div>
    """
  end

  defp render_step1(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-8">
      <h1 class="text-2xl font-semibold text-gray-900 dark:text-white mb-2">
        Let's get you set up 👋
      </h1>
      <p class="text-gray-500 dark:text-gray-400 mb-6">Tell us a bit about yourself.</p>

      <div class="space-y-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Display name
          </label>
          <input
            type="text"
            value={@display_name}
            phx-change="update_display_name"
            phx-debounce="300"
            name="value"
            placeholder="How should we call you?"
            class="w-full px-4 py-3 bg-[#F5F5F7] dark:bg-[#3A3A3C] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors text-gray-900 dark:text-white"
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Grade
          </label>
          <div class="grid grid-cols-4 gap-2">
            <%= for g <- @grade_options do %>
              <button
                type="button"
                phx-click="select_grade"
                phx-value-grade={g}
                class={[
                  "py-2 rounded-full text-sm font-medium transition-colors border",
                  if(@grade == g,
                    do: "bg-[#4CD964] text-white border-[#4CD964]",
                    else:
                      "bg-white dark:bg-[#3A3A3C] text-gray-700 dark:text-gray-300 border-gray-200 dark:border-gray-600 hover:border-[#4CD964]"
                  )
                ]}
              >
                {g}
              </button>
            <% end %>
          </div>
        </div>
      </div>

      <%= if @error do %>
        <p class="mt-3 text-sm text-[#FF3B30]">{@error}</p>
      <% end %>

      <button
        type="button"
        phx-click="step1_next"
        class="mt-6 w-full bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium py-3 rounded-full shadow-md transition-colors"
      >
        Next →
      </button>
    </div>
    """
  end

  defp render_step2(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-8">
      <h1 class="text-2xl font-semibold text-gray-900 dark:text-white mb-2">Find your school</h1>
      <p class="text-gray-500 dark:text-gray-400 mb-6">
        We'll show courses from your school and grade.
      </p>

      <%= if @school do %>
        <div class="flex items-center justify-between p-4 bg-[#E8F8EB] dark:bg-green-900/30 rounded-2xl mb-4">
          <div>
            <p class="font-medium text-gray-900 dark:text-white">{@school.name}</p>
            <p class="text-sm text-gray-500">{@school.city}</p>
          </div>
          <button
            type="button"
            phx-click="clear_school"
            class="text-sm text-gray-400 hover:text-gray-600 px-3 py-1 rounded-full border border-gray-200"
          >
            Change
          </button>
        </div>
      <% else %>
        <div class="relative mb-4">
          <input
            type="text"
            value={@school_search}
            phx-keyup="search_school"
            phx-debounce="300"
            name="query"
            placeholder="Type your school name..."
            class="w-full px-4 py-3 bg-[#F5F5F7] dark:bg-[#3A3A3C] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors text-gray-900 dark:text-white"
          />
          <%= if length(@school_results) > 0 do %>
            <div class="absolute top-full left-0 right-0 mt-1 bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-lg border border-gray-100 dark:border-gray-700 z-10 overflow-hidden">
              <%= for school <- @school_results do %>
                <button
                  type="button"
                  phx-click="select_school"
                  phx-value-school_id={school.id}
                  class="w-full text-left px-4 py-3 hover:bg-[#F5F5F7] dark:hover:bg-[#3A3A3C] transition-colors"
                >
                  <p class="font-medium text-gray-900 dark:text-white">{school.name}</p>
                  <p class="text-xs text-gray-500">{school.city}</p>
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <div class="flex flex-col gap-3">
        <button
          type="button"
          phx-click="step2_next"
          class="w-full bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium py-3 rounded-full shadow-md transition-colors"
        >
          {if @school, do: "Continue →", else: "Search & Continue →"}
        </button>
        <button
          type="button"
          phx-click="step2_skip"
          class="w-full text-gray-400 text-sm hover:text-gray-600 py-2"
        >
          I'll add my school later →
        </button>
      </div>
    </div>
    """
  end

  defp render_step3(assigns) do
    ~H"""
    <div>
      <%= if @available_courses == [] and @other_school_courses == [] do %>
        <%!-- Empty State --%>
        <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-8 text-center">
          <h2 class="text-xl font-semibold text-gray-900 dark:text-white mb-2">
            <%= if @school do %>
              You're the first from {@school.name} on FunSheep! 🎉
            <% else %>
              You're one of the first students on FunSheep!
            <% end %>
          </h2>
          <p class="text-gray-500 mb-6">No courses have been added yet — you can change that.</p>
          <div class="grid grid-cols-2 gap-4 mb-6">
            <a
              href={
                "/courses/new?onboarding=true#{if @school, do: "&school_id=#{@school.id}", else: ""}#{if @grade, do: "&grade=#{@grade}", else: ""}"
              }
              class="bg-white dark:bg-[#3A3A3C] border border-gray-200 dark:border-gray-600 rounded-2xl p-4 text-left hover:border-[#4CD964] transition-colors block"
            >
              <div class="text-2xl mb-2">📖</div>
              <h3 class="font-semibold text-sm text-gray-900 dark:text-white mb-1">
                Create a course
              </h3>
              <p class="text-xs text-gray-500">Upload your textbook or add a subject manually.</p>
              <span class="mt-3 inline-block px-3 py-1 bg-[#4CD964] text-white text-xs rounded-full font-medium">
                Create Course →
              </span>
            </a>
            <div class="bg-white dark:bg-[#3A3A3C] border border-gray-200 dark:border-gray-600 rounded-2xl p-4">
              <div class="text-2xl mb-2">✉️</div>
              <h3 class="font-semibold text-sm text-gray-900 dark:text-white mb-1">
                Invite a teacher
              </h3>
              <p class="text-xs text-gray-500 mb-2">
                Your teacher can add all the courses for your class.
              </p>
              <input
                type="email"
                value={@invite_email}
                phx-change="invite_teacher_email"
                name="email"
                placeholder="teacher@school.edu"
                class="w-full px-3 py-2 text-xs bg-[#F5F5F7] dark:bg-[#2C2C2E] border border-gray-200 rounded-full outline-none focus:border-[#4CD964] mb-2"
              />
              <%= if @invite_sent do %>
                <p class="text-xs text-[#4CD964] font-medium">✓ Invite sent!</p>
              <% else %>
                <button
                  type="button"
                  phx-click="send_teacher_invite"
                  class="w-full px-3 py-1 bg-[#4CD964] text-white text-xs rounded-full font-medium hover:bg-[#3DBF55]"
                >
                  Invite Teacher →
                </button>
              <% end %>
            </div>
          </div>

          <button
            type="button"
            phx-click="step3_continue"
            class="text-gray-400 text-sm hover:text-gray-600"
          >
            Go to Dashboard →
          </button>
        </div>
      <% else %>
        <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6">
          <h2 class="text-xl font-semibold text-gray-900 dark:text-white mb-1">
            Pick your courses
          </h2>
          <p class="text-gray-500 dark:text-gray-400 text-sm mb-4">
            Add courses to your list. You can always add more later.
          </p>

          <%= if @error do %>
            <p class="text-sm text-[#FF3B30] mb-3">{@error}</p>
          <% end %>

          <div class="space-y-2 max-h-96 overflow-y-auto mb-4">
            <%= for course <- @available_courses do %>
              <% selected = MapSet.member?(@selected_course_ids, course.id) %>
              <div
                class={[
                  "flex items-center justify-between p-3 rounded-2xl border transition-colors cursor-pointer",
                  if(selected,
                    do: "bg-[#E8F8EB] border-[#4CD964]",
                    else: "border-gray-100 dark:border-gray-700 hover:border-gray-200"
                  )
                ]}
                phx-click="toggle_course"
                phx-value-course_id={course.id}
              >
                <div class="min-w-0">
                  <p class="font-medium text-sm text-gray-900 dark:text-white truncate">
                    {course.name}
                  </p>
                  <p class="text-xs text-gray-500">
                    {course.subject} · {FunSheep.Courses.format_grades(course.grades)}
                  </p>
                </div>
                <div class={[
                  "shrink-0 ml-3 w-6 h-6 rounded-full flex items-center justify-center border-2 transition-colors",
                  if(selected,
                    do: "bg-[#4CD964] border-[#4CD964]",
                    else: "border-gray-300"
                  )
                ]}>
                  <%= if selected do %>
                    <svg
                      class="w-3 h-3 text-white"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                      stroke-width="3"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="M5 13l4 4L19 7"
                      />
                    </svg>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>

          <button
            type="button"
            phx-click="step3_continue"
            class="w-full bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium py-3 rounded-full shadow-md transition-colors"
          >
            Continue ({MapSet.size(@selected_course_ids)} selected) →
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_step4(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6">
      <h2 class="text-xl font-semibold text-gray-900 dark:text-white mb-1">
        Follow your classmates 🐑
      </h2>
      <p class="text-gray-500 dark:text-gray-400 text-sm mb-4">
        See how they're doing and cheer each other on.
      </p>

      <%= if @onboarding_peers == [] do %>
        <div class="text-center py-8">
          <p class="text-gray-400 text-sm mb-1">No classmates found yet.</p>
          <p class="text-xs text-gray-400">Make sure your school is set so we can find them.</p>
        </div>
      <% else %>
        <div class="space-y-2 mb-4">
          <%= for peer <- @onboarding_peers do %>
            <div class="flex items-center gap-3 p-3 bg-[#F5F5F7] dark:bg-[#3A3A3C] rounded-2xl">
              <div class="w-9 h-9 rounded-full bg-gray-200 dark:bg-gray-600 flex items-center justify-center text-sm font-bold text-gray-600 dark:text-gray-200 shrink-0">
                {String.first(peer.display_name || "?")}
              </div>
              <div class="flex-1 min-w-0">
                <p class="text-sm font-bold text-gray-900 dark:text-white truncate">
                  {peer.display_name}
                </p>
                <p class="text-xs text-gray-400">Grade {peer.grade || "?"}</p>
              </div>
              <%= if MapSet.member?(@followed_in_onboarding, peer.id) do %>
                <span class="text-xs text-[#4CD964] font-bold">Following ✓</span>
              <% else %>
                <button
                  type="button"
                  phx-click="onboarding_follow"
                  phx-value-id={peer.id}
                  class="text-xs px-3 py-1.5 rounded-full bg-[#4CD964] text-white font-bold hover:bg-[#3DBF55] transition-colors shrink-0"
                >
                  + Follow
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <div class="flex flex-col gap-3">
        <button
          type="button"
          phx-click="step4_done"
          class="w-full bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium py-3 rounded-full shadow-md transition-colors"
        >
          {if MapSet.size(@followed_in_onboarding) > 0, do: "Continue →", else: "Skip for now →"}
        </button>
        <.link
          navigate={~p"/social/find"}
          class="text-sm text-center text-gray-400 hover:text-gray-600"
        >
          Search all classmates →
        </.link>
      </div>
    </div>
    """
  end

  defp render_step5(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-8 text-center">
      <div class="text-5xl mb-4">🎉</div>
      <h1 class="text-2xl font-semibold text-gray-900 dark:text-white mb-2">
        You're all set, {@display_name || "there"}!
      </h1>
      <p class="text-gray-500 dark:text-gray-400 mb-6">You're ready to start practicing.</p>

      <%= if length(@enrolled_courses) > 0 do %>
        <div class="text-left mb-6">
          <p class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Courses added:</p>
          <div class="space-y-1">
            <%= for sc <- @enrolled_courses do %>
              <div class="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400">
                <span class="text-[#4CD964]">✓</span>
                <span>{(sc.course && sc.course.name) || "Course"}</span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <div class="flex flex-col gap-3">
        <a
          href="/dashboard"
          class="w-full bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium py-3 rounded-full shadow-md transition-colors text-center"
        >
          Start Practicing →
        </a>
        <a href="/dashboard" class="text-sm text-gray-400 hover:text-gray-600">Go to Dashboard</a>
      </div>
    </div>
    """
  end
end
