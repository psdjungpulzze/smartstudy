defmodule StudySmartWeb.CourseNewLive do
  use StudySmartWeb, :live_view

  alias StudySmart.Courses
  alias StudySmart.Courses.Course
  alias StudySmart.Geo

  @impl true
  def mount(_params, _session, socket) do
    changeset = Courses.change_course(%Course{})
    schools = Geo.list_schools()

    {:ok,
     assign(socket,
       page_title: "Create Course",
       form: to_form(changeset),
       schools: schools
     )}
  end

  @impl true
  def handle_event("validate", %{"course" => course_params}, socket) do
    changeset =
      %Course{}
      |> Courses.change_course(course_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"course" => course_params}, socket) do
    case Courses.create_course(course_params) do
      {:ok, course} ->
        {:noreply,
         socket
         |> put_flash(:info, "Course created successfully!")
         |> push_navigate(to: ~p"/courses/#{course.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <div class="mb-6">
        <.link
          navigate={~p"/courses"}
          class="text-[#8E8E93] hover:text-[#1C1C1E] text-sm inline-flex items-center transition-colors"
        >
          <.icon name="hero-arrow-left" class="w-4 h-4 mr-1" /> Back to Courses
        </.link>
        <h1 class="text-2xl font-bold text-[#1C1C1E] mt-2">Create New Course</h1>
        <p class="text-[#8E8E93] mt-1">Set up a new course with subject and grade information</p>
      </div>

      <div class="bg-white rounded-2xl shadow-md p-6">
        <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
          <.input
            field={@form[:name]}
            type="text"
            label="Course Name"
            placeholder="e.g. AP Calculus AB"
            required
          />
          <.input
            field={@form[:subject]}
            type="text"
            label="Subject"
            placeholder="e.g. Mathematics"
            required
          />
          <.input
            field={@form[:grade]}
            type="select"
            label="Grade Level"
            prompt="Select grade..."
            options={Enum.map(1..12, &{"Grade #{&1}", "#{&1}"})}
            required
          />
          <.input
            field={@form[:school_id]}
            type="select"
            label="School (optional)"
            prompt="Select school..."
            options={Enum.map(@schools, &{&1.name, &1.id})}
          />
          <.input
            field={@form[:description]}
            type="textarea"
            label="Description (optional)"
            placeholder="Brief description of the course..."
          />

          <div class="flex gap-3 pt-4">
            <button
              type="submit"
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
            >
              Create Course
            </button>
            <.link
              navigate={~p"/courses"}
              class="bg-white hover:bg-gray-50 text-gray-700 font-medium px-6 py-2 rounded-full border border-gray-200 shadow-sm transition-colors"
            >
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
