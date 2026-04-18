defmodule StudySmartWeb.CourseNewLive do
  use StudySmartWeb, :live_view

  alias StudySmart.Accounts
  alias StudySmart.Courses
  alias StudySmart.Geo
  alias StudySmart.Learning
  alias StudySmart.Content

  @grade_options [
    "K",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
    "10",
    "11",
    "12",
    "College"
  ]

  @gender_options [
    "Male",
    "Female",
    "Other",
    "Prefer not to say"
  ]

  @impl true
  def mount(_params, _session, socket) do
    countries = Geo.list_countries()
    user = socket.assigns.current_user
    user_role = load_user_role(user)

    socket =
      socket
      |> assign(
        # Step 1 fields
        countries: countries,
        states: [],
        districts: [],
        schools: [],
        grade_options: @grade_options,
        gender_options: @gender_options,
        selected_country_id: nil,
        selected_state_id: nil,
        selected_district_id: nil,
        selected_school_id: nil,
        course_name: "",
        subject: "",
        selected_grade: user_role && user_role.grade,
        selected_gender: user_role && user_role.gender,
        nationality: (user_role && user_role.nationality) || "",
        description: "",
        step: 1,
        max_step: 1,
        step1_errors: %{},
        # Step 2 fields
        hobbies: [],
        selected_hobby_ids: MapSet.new(),
        hobby_interests: %{},
        # Step 3 fields
        uploaded_files: [],
        existing_materials: [],
        # folder_name_by_filename: %{"ch1.pdf" => "Textbook", ...}
        folder_map: %{},
        # State
        user_role: user_role,
        editing_course: nil,
        saving: false
      )
      |> prefill_geo_from_user_role(user_role)
      |> prefill_hobbies_from_user_role(user_role)
      |> allow_upload(:materials,
        accept: ~w(.pdf .jpg .jpeg .png .doc .docx .ppt .pptx .xls .xlsx .txt .csv),
        max_entries: 1000,
        max_file_size: 1_000_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => course_id}, _url, socket) do
    course = Courses.get_course_with_chapters!(course_id)
    existing_materials = Content.list_materials_by_course(course_id)

    socket =
      socket
      |> assign(
        page_title: "Edit Course",
        editing_course: course,
        course_name: course.name,
        subject: course.subject,
        selected_grade: course.grade,
        description: course.description || "",
        existing_materials: existing_materials
      )
      |> prefill_school_from_course(course)

    {:noreply, socket}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, page_title: "Add New Course")}
  end

  defp prefill_school_from_course(socket, %{school_id: nil}), do: socket

  defp prefill_school_from_course(socket, course) do
    try do
      school = Geo.get_school!(course.school_id)
      district = Geo.get_district!(school.district_id)
      state = Geo.get_state!(district.state_id)
      country = Geo.get_country!(state.country_id)

      assign(socket,
        selected_country_id: country.id,
        selected_state_id: state.id,
        selected_district_id: district.id,
        selected_school_id: school.id,
        states: Geo.list_states_by_country(country.id),
        districts: Geo.list_districts_by_state(state.id),
        schools: Geo.list_schools_by_district(district.id)
      )
    rescue
      _ -> socket
    end
  end

  defp load_user_role(user) do
    interactor_id = user["interactor_user_id"]

    if interactor_id do
      Accounts.get_user_role_by_interactor_id(interactor_id)
    else
      # Dev user - try by ID
      case Ecto.UUID.cast(user["id"]) do
        {:ok, _} ->
          try do
            Accounts.get_user_role!(user["id"])
          rescue
            Ecto.NoResultsError -> nil
          end

        _ ->
          nil
      end
    end
  end

  defp prefill_geo_from_user_role(socket, nil), do: socket

  defp prefill_geo_from_user_role(socket, user_role) do
    if user_role.school_id do
      try do
        school = Geo.get_school!(user_role.school_id)
        district = Geo.get_district!(school.district_id)
        state = Geo.get_state!(district.state_id)
        country = Geo.get_country!(state.country_id)

        states = Geo.list_states_by_country(country.id)
        districts = Geo.list_districts_by_state(state.id)
        schools = Geo.list_schools_by_district(district.id)

        assign(socket,
          selected_country_id: country.id,
          selected_state_id: state.id,
          selected_district_id: district.id,
          selected_school_id: school.id,
          states: states,
          districts: districts,
          schools: schools
        )
      rescue
        _ -> socket
      end
    else
      socket
    end
  end

  defp prefill_hobbies_from_user_role(socket, nil), do: socket

  defp prefill_hobbies_from_user_role(socket, user_role) do
    student_hobbies = Learning.list_hobbies_for_user(user_role.id)

    selected_ids =
      student_hobbies
      |> Enum.map(& &1.hobby_id)
      |> MapSet.new()

    interests =
      student_hobbies
      |> Enum.reduce(%{}, fn sh, acc ->
        case sh.specific_interests do
          %{"text" => text} when text != "" -> Map.put(acc, sh.hobby_id, text)
          _ -> acc
        end
      end)

    assign(socket, selected_hobby_ids: selected_ids, hobby_interests: interests)
  end

  # ── Events ─────────────────────────────────────────────────────────────────

  @impl true
  # Handle form-level changes for text inputs, grade, gender, nationality
  def handle_event("step1_change", params, socket) do
    socket =
      socket
      |> maybe_assign(params, "course_name", :course_name)
      |> maybe_assign(params, "subject", :subject)
      |> maybe_assign(params, "description", :description)
      |> maybe_assign(params, "selected_grade", :selected_grade)
      |> maybe_assign(params, "selected_gender", :selected_gender)
      |> maybe_assign(params, "nationality", :nationality)

    {:noreply, socket}
  end

  def handle_event("select_country", %{"country_id" => country_id}, socket) do
    states = if country_id != "", do: Geo.list_states_by_country(country_id), else: []

    {:noreply,
     assign(socket,
       selected_country_id: country_id,
       states: states,
       districts: [],
       schools: [],
       selected_state_id: nil,
       selected_district_id: nil,
       selected_school_id: nil
     )}
  end

  def handle_event("select_state", %{"state_id" => state_id}, socket) do
    districts = if state_id != "", do: Geo.list_districts_by_state(state_id), else: []

    {:noreply,
     assign(socket,
       selected_state_id: state_id,
       districts: districts,
       schools: [],
       selected_district_id: nil,
       selected_school_id: nil
     )}
  end

  def handle_event("select_district", %{"district_id" => district_id}, socket) do
    schools = if district_id != "", do: Geo.list_schools_by_district(district_id), else: []

    {:noreply,
     assign(socket,
       selected_district_id: district_id,
       schools: schools,
       selected_school_id: nil
     )}
  end

  def handle_event("select_school", %{"school_id" => school_id}, socket) do
    {:noreply, assign(socket, selected_school_id: school_id)}
  end

  def handle_event("next_step", _params, %{assigns: %{step: 1}} = socket) do
    errors = validate_step1(socket.assigns)

    if map_size(errors) == 0 do
      hobbies = Learning.list_hobbies()
      new_max = max(socket.assigns.max_step, 2)
      {:noreply, assign(socket, step: 2, max_step: new_max, hobbies: hobbies, step1_errors: %{})}
    else
      {:noreply, assign(socket, step1_errors: errors)}
    end
  end

  def handle_event("next_step", _params, %{assigns: %{step: 2}} = socket) do
    new_max = max(socket.assigns.max_step, 3)
    {:noreply, assign(socket, step: 3, max_step: new_max)}
  end

  def handle_event("prev_step", _params, %{assigns: %{step: step}} = socket) when step > 1 do
    {:noreply, assign(socket, step: step - 1)}
  end

  def handle_event("go_to_step", %{"step" => step_str}, socket) do
    target = String.to_integer(step_str)

    if target >= 1 and target <= socket.assigns.max_step do
      socket =
        if target == 2 and socket.assigns.hobbies == [] do
          assign(socket, hobbies: Learning.list_hobbies())
        else
          socket
        end

      {:noreply, assign(socket, step: target)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_hobby", %{"hobby-id" => hobby_id}, socket) do
    selected = socket.assigns.selected_hobby_ids

    selected =
      if MapSet.member?(selected, hobby_id) do
        MapSet.delete(selected, hobby_id)
      else
        MapSet.put(selected, hobby_id)
      end

    {:noreply, assign(socket, selected_hobby_ids: selected)}
  end

  def handle_event("update_hobby_interest", %{"hobby-id" => hobby_id, "value" => value}, socket) do
    interests = Map.put(socket.assigns.hobby_interests, hobby_id, value)
    {:noreply, assign(socket, hobby_interests: interests)}
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("folder_metadata", %{"folders" => folders}, socket) when is_map(folders) do
    # Merge new folder mappings (filename → folder_name) into existing map
    updated = Map.merge(socket.assigns.folder_map, folders)
    {:noreply, assign(socket, folder_map: updated)}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :materials, ref)}
  end

  def handle_event("clear_all_uploads", _params, socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.materials.entries, socket, fn entry, acc ->
        cancel_upload(acc, :materials, entry.ref)
      end)

    {:noreply, socket}
  end

  def handle_event("delete_material", %{"id" => material_id}, socket) do
    material = Content.get_uploaded_material!(material_id)
    Content.delete_uploaded_material(material)

    existing = Enum.reject(socket.assigns.existing_materials, &(&1.id == material_id))
    {:noreply, assign(socket, existing_materials: existing)}
  end

  def handle_event("complete", _params, socket) do
    {:noreply, assign(socket, saving: true) |> do_complete()}
  end

  # ── Completion Logic ──────────────────────────────────────────────────────

  defp do_complete(socket) do
    assigns = socket.assigns
    user = assigns.current_user

    # 1. Update user profile (demographics)
    profile_attrs = %{
      grade: assigns.selected_grade,
      gender: assigns.selected_gender,
      nationality: assigns.nationality,
      school_id: non_empty(assigns.selected_school_id)
    }

    interactor_id = user["interactor_user_id"]

    user_role_result =
      if interactor_id do
        Accounts.upsert_user_profile(interactor_id, profile_attrs)
      else
        case assigns.user_role do
          nil -> {:error, :no_user_role}
          ur -> Accounts.update_user_role(ur, profile_attrs)
        end
      end

    user_role =
      case user_role_result do
        {:ok, ur} -> ur
        _ -> assigns.user_role
      end

    # 2. Create or update the course
    course_attrs = %{
      "name" => assigns.course_name,
      "subject" => assigns.subject,
      "grade" => assigns.selected_grade,
      "description" => assigns.description,
      "school_id" => non_empty(assigns.selected_school_id),
      "created_by_id" => user_role && user_role.id
    }

    course_result =
      case assigns.editing_course do
        nil -> Courses.create_course(course_attrs)
        existing -> Courses.update_course(existing, course_attrs)
      end

    case course_result do
      {:ok, course} ->
        # 3. Save hobbies
        if user_role do
          save_hobbies(user_role.id, assigns.selected_hobby_ids, assigns.hobby_interests)
        end

        # 4. Save uploaded materials
        if user_role do
          save_uploads(socket, user_role.id, course.id)
        end

        flash_msg =
          if assigns.editing_course, do: "Course updated!", else: "Course added successfully!"

        socket
        |> put_flash(:info, flash_msg)
        |> push_navigate(to: ~p"/courses/#{course.id}")

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = format_changeset_errors(changeset)

        socket
        |> assign(saving: false, step: 1, step1_errors: errors)
        |> put_flash(:error, "Please fix the errors and try again.")
    end
  end

  defp save_hobbies(user_role_id, selected_ids, interests) do
    # Remove old hobbies for this user
    existing = Learning.list_hobbies_for_user(user_role_id)

    for sh <- existing do
      unless MapSet.member?(selected_ids, sh.hobby_id) do
        Learning.delete_student_hobby(sh)
      end
    end

    existing_hobby_ids = MapSet.new(existing, & &1.hobby_id)

    # Add new hobbies
    for hobby_id <- selected_ids do
      unless MapSet.member?(existing_hobby_ids, hobby_id) do
        Learning.create_student_hobby(%{
          user_role_id: user_role_id,
          hobby_id: hobby_id,
          specific_interests: %{"text" => Map.get(interests, hobby_id, "")}
        })
      end
    end
  end

  defp save_uploads(socket, user_role_id, course_id) do
    folder_map = socket.assigns.folder_map

    consume_uploaded_entries(socket, :materials, fn %{path: path}, entry ->
      folder_name = Map.get(folder_map, entry.client_name)

      # Store in folder-based subdirectory for organization
      sub_dir =
        if folder_name,
          do: Path.join(["uploads", course_id, folder_name]),
          else: Path.join(["uploads", course_id])

      uploads_dir = Application.app_dir(:study_smart, "priv/static")
      dest_dir = Path.join(uploads_dir, sub_dir)
      File.mkdir_p!(dest_dir)
      dest = Path.join(dest_dir, entry.client_name)
      File.cp!(path, dest)

      Content.create_uploaded_material(%{
        file_name: entry.client_name,
        file_path: "/#{sub_dir}/#{entry.client_name}",
        file_type: entry.client_type,
        file_size: entry.client_size,
        folder_name: folder_name,
        user_role_id: user_role_id,
        course_id: course_id
      })

      {:ok, dest}
    end)
  end

  defp maybe_assign(socket, params, param_key, assign_key) do
    case Map.get(params, param_key) do
      nil -> socket
      value -> assign(socket, [{assign_key, value}])
    end
  end

  defp non_empty(""), do: nil
  defp non_empty(nil), do: nil
  defp non_empty(val), do: val

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.into(%{}, fn {field, msgs} -> {field, Enum.join(msgs, ", ")} end)
  end

  defp validate_step1(assigns) do
    errors = %{}

    errors =
      if assigns.course_name == "" do
        Map.put(errors, :course_name, "Course name is required")
      else
        errors
      end

    errors =
      if assigns.subject == "" do
        Map.put(errors, :subject, "Subject is required")
      else
        errors
      end

    errors =
      if is_nil(assigns.selected_grade) or assigns.selected_grade == "" do
        Map.put(errors, :grade, "Grade level is required")
      else
        errors
      end

    errors
  end

  # ── Render ─────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="animate-slide-up">
      <div class="mb-6">
        <.link
          navigate={~p"/courses"}
          class="text-gray-400 hover:text-gray-600 text-sm inline-flex items-center transition-colors font-medium"
        >
          <.icon name="hero-arrow-left" class="w-4 h-4 mr-1" /> Back
        </.link>
        <h1 class="text-2xl font-extrabold text-gray-900 mt-2">
          {if @editing_course, do: "Edit Course ✏️", else: "New Course 🐑"}
        </h1>
        <p class="text-gray-500 text-sm mt-1">3 quick steps and you're set!</p>
      </div>

      <%!-- Step Indicator --%>
      <.step_indicator step={@step} max_step={@max_step} />

      <%!-- Step Content --%>
      <div class="bg-white rounded-2xl border border-gray-100 p-6 sm:p-8 mt-6">
        <%= case @step do %>
          <% 1 -> %>
            <.step1_course_info
              countries={@countries}
              states={@states}
              districts={@districts}
              schools={@schools}
              grade_options={@grade_options}
              gender_options={@gender_options}
              selected_country_id={@selected_country_id}
              selected_state_id={@selected_state_id}
              selected_district_id={@selected_district_id}
              selected_school_id={@selected_school_id}
              course_name={@course_name}
              subject={@subject}
              selected_grade={@selected_grade}
              selected_gender={@selected_gender}
              nationality={@nationality}
              description={@description}
              errors={@step1_errors}
            />
          <% 2 -> %>
            <.step2_hobbies
              hobbies={@hobbies}
              selected_hobby_ids={@selected_hobby_ids}
              hobby_interests={@hobby_interests}
            />
          <% 3 -> %>
            <.step3_upload
              uploads={@uploads}
              saving={@saving}
              editing={@editing_course != nil}
              existing_materials={@existing_materials}
              folder_map={@folder_map}
            />
        <% end %>
      </div>
    </div>
    """
  end

  # ── Step Indicator ─────────────────────────────────────────────────────────

  attr :step, :integer, required: true
  attr :max_step, :integer, required: true

  defp step_indicator(assigns) do
    ~H"""
    <div class="flex items-center justify-center gap-0">
      <.step_dot number={1} label="Info" active={@step >= 1} current={@step == 1} clickable={true} />
      <div class={"w-16 h-0.5 #{if @step > 1, do: "bg-purple-600", else: "bg-gray-200"}"} />
      <.step_dot
        number={2}
        label="Hobbies"
        active={@step >= 2}
        current={@step == 2}
        clickable={@max_step >= 2}
      />
      <div class={"w-16 h-0.5 #{if @step > 2, do: "bg-purple-600", else: "bg-gray-200"}"} />
      <.step_dot
        number={3}
        label="Files"
        active={@step >= 3}
        current={@step == 3}
        clickable={@max_step >= 3}
      />
    </div>
    """
  end

  attr :number, :integer, required: true
  attr :label, :string, required: true
  attr :active, :boolean, required: true
  attr :current, :boolean, required: true
  attr :clickable, :boolean, default: false

  defp step_dot(assigns) do
    ~H"""
    <button
      type="button"
      class="flex flex-col items-center gap-1 group"
      disabled={!@clickable}
      phx-click={if @clickable && !@current, do: "go_to_step"}
      phx-value-step={@number}
    >
      <div class={[
        "w-8 h-8 rounded-full flex items-center justify-center text-sm font-semibold transition-colors",
        @current && "bg-purple-600 text-white",
        @active && !@current && "bg-purple-100 text-purple-600",
        @clickable && !@current && "group-hover:ring-2 group-hover:ring-purple-300",
        !@active && "bg-gray-50 text-gray-500"
      ]}>
        <%= if @active && !@current do %>
          <svg
            class="w-4 h-4"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="2"
            stroke="currentColor"
          >
            <path stroke-linecap="round" stroke-linejoin="round" d="m4.5 12.75 6 6 9-13.5" />
          </svg>
        <% else %>
          {@number}
        <% end %>
      </div>
      <span class={"text-xs font-medium #{if @active, do: "text-purple-600", else: "text-gray-500"}"}>
        {@label}
      </span>
    </button>
    """
  end

  # ── Step 1: Course Info + Demographics ─────────────────────────────────────

  attr :countries, :list, required: true
  attr :states, :list, required: true
  attr :districts, :list, required: true
  attr :schools, :list, required: true
  attr :grade_options, :list, required: true
  attr :gender_options, :list, required: true
  attr :selected_country_id, :string, default: nil
  attr :selected_state_id, :string, default: nil
  attr :selected_district_id, :string, default: nil
  attr :selected_school_id, :string, default: nil
  attr :course_name, :string, default: ""
  attr :subject, :string, default: ""
  attr :selected_grade, :string, default: nil
  attr :selected_gender, :string, default: nil
  attr :nationality, :string, default: ""
  attr :description, :string, default: ""
  attr :errors, :map, default: %{}

  defp step1_course_info(assigns) do
    ~H"""
    <form id="step1-form" phx-change="step1_change" phx-submit="next_step">
      <h2 class="text-xl font-extrabold text-gray-900 mb-6">Tell us about your course 📝</h2>

      <div class="space-y-4">
        <%!-- Course Name --%>
        <div>
          <label class="block text-sm font-medium text-gray-900 mb-1">Course Name *</label>
          <input
            type="text"
            value={@course_name}
            name="course_name"
            placeholder="e.g., AP Calculus AB"
            class={"w-full px-4 py-3 bg-gray-50 text-gray-900 border rounded-full outline-none transition-colors #{if @errors[:course_name], do: "border-red-400", else: "border-gray-200 focus:border-purple-400"}"}
          />
          <p :if={@errors[:course_name]} class="text-sm text-red-500 mt-1">
            {@errors[:course_name]}
          </p>
        </div>

        <%!-- Subject --%>
        <div>
          <label class="block text-sm font-medium text-gray-900 mb-1">Subject *</label>
          <input
            type="text"
            value={@subject}
            name="subject"
            placeholder="e.g., Mathematics, Biology, History"
            class={"w-full px-4 py-3 bg-gray-50 text-gray-900 border rounded-full outline-none transition-colors #{if @errors[:subject], do: "border-red-400", else: "border-gray-200 focus:border-purple-400"}"}
          />
          <p :if={@errors[:subject]} class="text-sm text-red-500 mt-1">{@errors[:subject]}</p>
        </div>

        <%!-- Description --%>
        <div>
          <label class="block text-sm font-medium text-gray-900 mb-1">Description</label>
          <textarea
            name="description"
            placeholder="Brief description of the course..."
            rows="2"
            class="w-full px-4 py-3 bg-gray-50 text-gray-900 border border-gray-200 focus:border-purple-400 rounded-xl outline-none transition-colors resize-none"
          >{@description}</textarea>
        </div>

        <hr class="border-gray-200 my-6" />
        <h3 class="text-lg font-bold text-gray-900 mb-4">About You 🐑</h3>

        <%!-- Country --%>
        <div>
          <label class="block text-sm font-medium text-gray-900 mb-1">Country</label>
          <select
            phx-change="select_country"
            name="country_id"
            class="w-full px-4 py-3 bg-gray-50 text-gray-900 border border-gray-200 focus:border-purple-400 rounded-full outline-none transition-colors appearance-none"
          >
            <option value="">Select a country</option>
            <option
              :for={country <- @countries}
              value={country.id}
              selected={to_string(country.id) == to_string(@selected_country_id)}
            >
              {country.name}
            </option>
          </select>
        </div>

        <%!-- State --%>
        <div>
          <label class="block text-sm font-medium text-gray-900 mb-1">State / Province</label>
          <select
            phx-change="select_state"
            name="state_id"
            disabled={@states == []}
            class="w-full px-4 py-3 bg-gray-50 text-gray-900 border border-gray-200 focus:border-purple-400 rounded-full outline-none transition-colors appearance-none disabled:opacity-50"
          >
            <option value="">Select a state</option>
            <option
              :for={state <- @states}
              value={state.id}
              selected={to_string(state.id) == to_string(@selected_state_id)}
            >
              {state.name}
            </option>
          </select>
        </div>

        <%!-- District --%>
        <div>
          <label class="block text-sm font-medium text-gray-900 mb-1">District</label>
          <select
            phx-change="select_district"
            name="district_id"
            disabled={@districts == []}
            class="w-full px-4 py-3 bg-gray-50 text-gray-900 border border-gray-200 focus:border-purple-400 rounded-full outline-none transition-colors appearance-none disabled:opacity-50"
          >
            <option value="">Select a district</option>
            <option
              :for={district <- @districts}
              value={district.id}
              selected={to_string(district.id) == to_string(@selected_district_id)}
            >
              {district.name}
            </option>
          </select>
        </div>

        <%!-- School --%>
        <div>
          <label class="block text-sm font-medium text-gray-900 mb-1">School</label>
          <select
            phx-change="select_school"
            name="school_id"
            disabled={@schools == []}
            class="w-full px-4 py-3 bg-gray-50 text-gray-900 border border-gray-200 focus:border-purple-400 rounded-full outline-none transition-colors appearance-none disabled:opacity-50"
          >
            <option value="">Select a school</option>
            <option
              :for={school <- @schools}
              value={school.id}
              selected={to_string(school.id) == to_string(@selected_school_id)}
            >
              {school.name}
            </option>
          </select>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <%!-- Grade Level --%>
          <div>
            <label class="block text-sm font-medium text-gray-900 mb-1">Grade Level *</label>
            <select
              name="selected_grade"
              class={"w-full px-4 py-3 bg-gray-50 text-gray-900 border rounded-full outline-none transition-colors appearance-none #{if @errors[:grade], do: "border-red-400", else: "border-gray-200 focus:border-purple-400"}"}
            >
              <option value="">Select grade</option>
              <option
                :for={grade <- @grade_options}
                value={grade}
                selected={grade == @selected_grade}
              >
                {grade}
              </option>
            </select>
            <p :if={@errors[:grade]} class="text-sm text-red-500 mt-1">{@errors[:grade]}</p>
          </div>

          <%!-- Gender --%>
          <div>
            <label class="block text-sm font-medium text-gray-900 mb-1">Gender</label>
            <select
              name="selected_gender"
              class="w-full px-4 py-3 bg-gray-50 text-gray-900 border border-gray-200 focus:border-purple-400 rounded-full outline-none transition-colors appearance-none"
            >
              <option value="">Select gender</option>
              <option
                :for={gender <- @gender_options}
                value={gender}
                selected={gender == @selected_gender}
              >
                {gender}
              </option>
            </select>
          </div>
        </div>

        <%!-- Nationality --%>
        <div>
          <label class="block text-sm font-medium text-gray-900 mb-1">Nationality</label>
          <input
            type="text"
            value={@nationality}
            name="nationality"
            placeholder="e.g., American, Korean"
            class="w-full px-4 py-3 bg-gray-50 text-gray-900 border border-gray-200 focus:border-purple-400 rounded-full outline-none transition-colors"
          />
        </div>
      </div>

      <%!-- Next button --%>
      <div class="flex justify-between mt-8">
        <.link
          navigate={~p"/courses"}
          class="bg-white hover:bg-gray-50 text-gray-900 font-medium px-8 py-3 rounded-full shadow-sm border border-gray-200 transition-colors"
        >
          Cancel
        </.link>
        <button
          type="submit"
          class="bg-purple-600 hover:bg-purple-700 text-white font-medium px-8 py-3 rounded-full shadow-md transition-colors"
        >
          Next
        </button>
      </div>
    </form>
    """
  end

  # ── Step 2: Hobbies ──────────────────────────────────────────────────────

  attr :hobbies, :list, required: true
  attr :selected_hobby_ids, :any, required: true
  attr :hobby_interests, :map, required: true

  defp step2_hobbies(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-extrabold text-gray-900 mb-2">What are you into? 🎮</h2>
      <p class="text-sm text-gray-500 mb-6">
        Pick your hobbies so we can make questions more fun for you!
      </p>

      <div :if={@hobbies == []} class="text-center py-8">
        <.icon name="hero-sparkles" class="w-12 h-12 text-gray-500 mx-auto mb-3" />
        <p class="text-gray-500">
          No hobbies available yet. You can skip this step and add them later.
        </p>
      </div>

      <div :if={@hobbies != []} class="grid grid-cols-2 md:grid-cols-3 gap-4">
        <div :for={hobby <- @hobbies}>
          <button
            type="button"
            phx-click="toggle_hobby"
            phx-value-hobby-id={hobby.id}
            class={[
              "w-full p-4 rounded-2xl border-2 text-left transition-all card-hover",
              if(MapSet.member?(@selected_hobby_ids, hobby.id),
                do: "border-purple-400 bg-purple-50",
                else: "border-gray-100 bg-white hover:border-purple-300"
              )
            ]}
          >
            <p class="font-semibold text-gray-900">{hobby.name}</p>
            <p class="text-xs text-gray-500 mt-1">{hobby.category}</p>
          </button>

          <div :if={MapSet.member?(@selected_hobby_ids, hobby.id)} class="mt-2">
            <input
              type="text"
              placeholder={"Specific interests (e.g., #{example_interests(hobby.name)})"}
              value={Map.get(@hobby_interests, hobby.id, "")}
              phx-change="update_hobby_interest"
              phx-value-hobby-id={hobby.id}
              name="value"
              class="w-full px-3 py-2 text-sm bg-gray-50 text-gray-900 border border-gray-200 focus:border-purple-400 rounded-full outline-none transition-colors"
            />
          </div>
        </div>
      </div>

      <%!-- Navigation buttons --%>
      <div class="flex justify-between mt-8">
        <button
          phx-click="prev_step"
          class="bg-white hover:bg-gray-50 text-gray-900 font-medium px-8 py-3 rounded-full shadow-sm border border-gray-200 transition-colors"
        >
          Back
        </button>
        <button
          phx-click="next_step"
          class="bg-purple-600 hover:bg-purple-700 text-white font-medium px-8 py-3 rounded-full shadow-md transition-colors"
        >
          Next
        </button>
      </div>
    </div>
    """
  end

  defp example_interests("KPOP"), do: "BTS, BlackPink"
  defp example_interests("Basketball"), do: "NBA, Stephen Curry"
  defp example_interests("Gaming"), do: "Minecraft, Valorant"
  defp example_interests("Drawing"), do: "Manga, Portraits"
  defp example_interests("Coding"), do: "Python, Web Dev"
  defp example_interests("Dance"), do: "K-pop dance, Hip hop"
  defp example_interests("Soccer"), do: "Premier League, Messi"
  defp example_interests("Anime"), do: "Naruto, One Piece"
  defp example_interests("Reading"), do: "Sci-fi, Fantasy"
  defp example_interests("Cooking"), do: "Korean BBQ, Baking"
  defp example_interests(_), do: "your favorites"

  # ── Step 3: Material Upload ──────────────────────────────────────────────

  attr :uploads, :any, required: true
  attr :saving, :boolean, default: false
  attr :editing, :boolean, default: false
  attr :existing_materials, :list, default: []
  attr :folder_map, :map, default: %{}

  defp step3_upload(assigns) do
    # Group entries by folder for display
    entries = assigns.uploads.materials.entries
    fm = assigns.folder_map

    grouped =
      entries
      |> Enum.group_by(fn e -> Map.get(fm, e.client_name, :loose) end)
      |> Enum.sort_by(fn {k, _} -> if k == :loose, do: "zzz", else: k end)

    # Group existing materials by folder
    existing_grouped =
      assigns.existing_materials
      |> Enum.group_by(fn m -> m.folder_name || :loose end)
      |> Enum.sort_by(fn {k, _} -> if k == :loose, do: "zzz", else: k end)

    assigns = assign(assigns, grouped: grouped, existing_grouped: existing_grouped)
    ~H"""
    <div>
      <h2 class="text-xl font-extrabold text-gray-900 mb-2">Got study materials? 📎</h2>
      <p class="text-sm text-gray-500 mb-6">
        Drop your notes, textbooks, or worksheets here. We'll use AI to help you study them!
        (You can also skip this for now)
      </p>

      <%!-- Existing materials grouped by folder (edit mode) --%>
      <div :if={@existing_materials != []} class="mb-6">
        <p class="text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">
          Existing files ({length(@existing_materials)})
        </p>
        <div class="space-y-3">
          <div :for={{folder, mats} <- @existing_grouped} class="border border-gray-100 rounded-xl overflow-hidden">
            <div class="flex items-center gap-2 px-3 py-2 bg-gray-50">
              <.icon name={if folder == :loose, do: "hero-document", else: "hero-folder"} class="w-4 h-4 text-gray-500" />
              <span class="text-xs font-bold text-gray-600">
                {if folder == :loose, do: "Ungrouped files", else: folder}
              </span>
              <span class="text-xs text-gray-400">({length(mats)} files)</span>
            </div>
            <div class="divide-y divide-gray-50">
              <div :for={mat <- mats} class="flex items-center gap-2 px-3 py-1.5 text-sm">
                <.icon name="hero-document" class="w-4 h-4 text-gray-300 shrink-0" />
                <span class="flex-1 truncate text-gray-700">{mat.file_name}</span>
                <span class="text-xs text-gray-400 shrink-0">{format_file_size(mat.file_size)}</span>
                <button
                  type="button"
                  phx-click="delete_material"
                  phx-value-id={mat.id}
                  class="text-gray-400 hover:text-red-500 shrink-0"
                >
                  <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <form id="upload-form" phx-hook="FolderMetadata" phx-change="validate_upload" phx-submit="complete">
        <%!-- Drop zone --%>
        <div
          class="border-2 border-dashed border-gray-200 rounded-2xl p-8 text-center hover:border-purple-400 transition-colors"
          phx-drop-target={@uploads.materials.ref}
        >
          <svg
            class="w-12 h-12 mx-auto text-gray-500 mb-4"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5m-13.5-9L12 3m0 0 4.5 4.5M12 3v13.5"
            />
          </svg>
          <p class="text-gray-900 font-medium mb-1">Drag and drop files or folders here</p>
          <p class="text-sm text-gray-500 mb-4">or</p>
          <div class="flex items-center justify-center gap-3">
            <label class="inline-block bg-purple-600 hover:bg-purple-700 text-white font-medium px-6 py-2 rounded-full shadow-md cursor-pointer transition-colors">
              <.icon name="hero-document" class="w-4 h-4 inline mr-1" /> Browse Files
              <.live_file_input upload={@uploads.materials} class="hidden" />
            </label>
            <button
              type="button"
              id="folder-upload-btn"
              phx-hook="FolderUpload"
              class="inline-block bg-white hover:bg-gray-50 text-gray-700 font-medium px-6 py-2 rounded-full shadow-sm border border-gray-200 cursor-pointer transition-colors"
            >
              <.icon name="hero-folder" class="w-4 h-4 inline mr-1" /> Browse Folder
            </button>
          </div>
          <p class="text-xs text-gray-500 mt-4">
            PDF, JPG, PNG, DOC, DOCX, PPT, XLS, TXT, CSV &mdash; up to 1 GB per file, up to 1,000 files. Select multiple folders!
          </p>
        </div>

        <%!-- Upload entries grouped by folder --%>
        <div :if={@uploads.materials.entries != []} class="mt-4">
          <%!-- Summary bar --%>
          <div class="flex items-center justify-between p-3 bg-purple-50 rounded-xl mb-3">
            <div class="flex items-center gap-2">
              <.icon name="hero-document-duplicate" class="w-5 h-5 text-purple-600" />
              <span class="text-sm font-bold text-purple-700">
                {length(@uploads.materials.entries)} file(s) selected
                <span :if={map_size(@folder_map) > 0} class="font-normal text-purple-500">
                  in {length(@grouped) - (if Enum.any?(@grouped, fn {k, _} -> k == :loose end), do: 1, else: 0)} folder(s)
                </span>
              </span>
            </div>
            <button
              type="button"
              phx-click="clear_all_uploads"
              class="text-xs font-bold text-red-500 hover:text-red-700"
            >
              Remove All
            </button>
          </div>

          <%!-- Grouped file list --%>
          <div class="space-y-3 max-h-80 overflow-y-auto">
            <div :for={{folder, entries} <- @grouped} class="border border-gray-100 rounded-xl overflow-hidden">
              <%!-- Folder header --%>
              <div class="flex items-center gap-2 px-3 py-2 bg-purple-50/50">
                <.icon
                  name={if folder == :loose, do: "hero-document", else: "hero-folder"}
                  class="w-4 h-4 text-purple-500"
                />
                <span class="text-xs font-bold text-purple-700">
                  {if folder == :loose, do: "Individual files", else: folder}
                </span>
                <span class="text-xs text-purple-400">({length(entries)} files)</span>
              </div>
              <%!-- Files in folder (show first 20 per folder) --%>
              <div class="divide-y divide-gray-50">
                <div
                  :for={entry <- Enum.take(entries, 20)}
                  class="flex items-center gap-2 px-3 py-1 text-sm"
                >
                  <.icon name="hero-document" class="w-3.5 h-3.5 text-gray-300 shrink-0" />
                  <span class="flex-1 truncate text-gray-700">{entry.client_name}</span>
                  <div class="w-12 bg-gray-200 rounded-full h-1 shrink-0">
                    <div class="bg-purple-600 h-1 rounded-full" style={"width: #{entry.progress}%"} />
                  </div>
                  <button
                    type="button"
                    phx-click="cancel_upload"
                    phx-value-ref={entry.ref}
                    class="text-gray-400 hover:text-red-500 shrink-0"
                  >
                    <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
                  </button>
                </div>
                <p :if={length(entries) > 20} class="text-xs text-gray-400 text-center py-1">
                  ... and {length(entries) - 20} more files in this folder
                </p>
              </div>
            </div>
          </div>
        </div>

        <%!-- Upload errors --%>
        <div :for={err <- upload_errors(@uploads.materials)} class="mt-2">
          <p class="text-sm text-red-500">{upload_error_to_string(err)}</p>
        </div>

        <%!-- Navigation buttons --%>
        <div class="flex justify-between mt-8">
          <button
            type="button"
            phx-click="prev_step"
            class="bg-white hover:bg-gray-50 text-gray-900 font-medium px-8 py-3 rounded-full shadow-sm border border-gray-200 transition-colors"
            disabled={@saving}
          >
            Back
          </button>
          <button
            type="submit"
            disabled={@saving}
            class="bg-purple-600 hover:bg-purple-700 text-white font-medium px-8 py-3 rounded-full shadow-md transition-colors disabled:opacity-50"
          >
            <%= if @saving do %>
              <svg
                class="w-5 h-5 inline animate-spin mr-2"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
              >
                <circle
                  class="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  stroke-width="4"
                />
                <path
                  class="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                />
              </svg>
              Saving...
            <% else %>
              {if @editing, do: "Save Changes ✅", else: "Done! 🎉"}
            <% end %>
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp upload_error_to_string(:too_large), do: "File is too large (max 1 GB)"

  defp upload_error_to_string(:not_accepted),
    do: "File type not accepted"

  defp upload_error_to_string(:too_many_files), do: "Maximum 1,000 files allowed"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"

  defp format_file_size(nil), do: ""
  defp format_file_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_file_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_file_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
