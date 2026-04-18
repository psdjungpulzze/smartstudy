defmodule StudySmartWeb.ProfileSetupLive do
  use StudySmartWeb, :live_view

  alias StudySmart.Geo
  alias StudySmart.Learning

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

    socket =
      socket
      |> assign(
        page_title: "Profile Setup",
        step: 1,
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
        subject_class: "",
        selected_grade: nil,
        selected_gender: nil,
        nationality: "",
        step1_errors: %{},
        # Step 2 fields
        hobbies: [],
        selected_hobby_ids: MapSet.new(),
        hobby_interests: %{},
        # Step 3 fields
        uploaded_files: []
      )
      |> allow_upload(:materials,
        accept: ~w(.pdf .jpg .jpeg .png),
        max_entries: 5,
        max_file_size: 50_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_country", %{"country_id" => country_id}, socket) do
    states =
      if country_id != "" do
        Geo.list_states_by_country(country_id)
      else
        []
      end

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
    districts =
      if state_id != "" do
        Geo.list_districts_by_state(state_id)
      else
        []
      end

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
    schools =
      if district_id != "" do
        Geo.list_schools_by_district(district_id)
      else
        []
      end

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

  def handle_event("update_field", %{"field" => field, "value" => value}, socket) do
    key = String.to_existing_atom(field)
    {:noreply, assign(socket, [{key, value}])}
  end

  def handle_event("next_step", _params, %{assigns: %{step: 1}} = socket) do
    errors = validate_step1(socket.assigns)

    if map_size(errors) == 0 do
      hobbies = Learning.list_hobbies()
      {:noreply, assign(socket, step: 2, hobbies: hobbies, step1_errors: %{})}
    else
      {:noreply, assign(socket, step1_errors: errors)}
    end
  end

  def handle_event("next_step", _params, %{assigns: %{step: 2}} = socket) do
    {:noreply, assign(socket, step: 3)}
  end

  def handle_event("prev_step", _params, %{assigns: %{step: step}} = socket) when step > 1 do
    {:noreply, assign(socket, step: step - 1)}
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

  def handle_event(
        "update_hobby_interest",
        %{"hobby-id" => hobby_id, "value" => value},
        socket
      ) do
    interests = Map.put(socket.assigns.hobby_interests, hobby_id, value)
    {:noreply, assign(socket, hobby_interests: interests)}
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :materials, ref)}
  end

  def handle_event("complete_setup", _params, socket) do
    # Consume uploaded files (move to storage)
    _uploaded =
      consume_uploaded_entries(socket, :materials, fn %{path: path}, entry ->
        dest =
          Path.join([
            Application.app_dir(:study_smart, "priv/static/uploads"),
            entry.client_name
          ])

        File.mkdir_p!(Path.dirname(dest))
        File.cp!(path, dest)
        {:ok, "/uploads/#{entry.client_name}"}
      end)

    {:noreply,
     socket
     |> put_flash(:info, "Profile setup complete!")
     |> redirect(to: "/dashboard")}
  end

  defp validate_step1(assigns) do
    errors = %{}

    errors =
      if is_nil(assigns.selected_country_id) or assigns.selected_country_id == "" do
        Map.put(errors, :country, "Country is required")
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
    <div class="max-w-3xl mx-auto py-8 px-4">
      <h1 class="text-2xl font-bold text-[#1C1C1E] text-center mb-2">Profile Setup</h1>
      <p class="text-[#8E8E93] text-center mb-8">
        Let's set up your profile to personalize your learning experience.
      </p>

      <%!-- Step Indicator --%>
      <.step_indicator step={@step} />

      <%!-- Step Content --%>
      <div class="bg-white rounded-2xl shadow-md p-8 mt-8">
        <%= case @step do %>
          <% 1 -> %>
            <.step1_demographics
              current_user={@current_user}
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
              subject_class={@subject_class}
              selected_grade={@selected_grade}
              selected_gender={@selected_gender}
              nationality={@nationality}
              errors={@step1_errors}
            />
          <% 2 -> %>
            <.step2_hobbies
              hobbies={@hobbies}
              selected_hobby_ids={@selected_hobby_ids}
              hobby_interests={@hobby_interests}
            />
          <% 3 -> %>
            <.step3_upload uploads={@uploads} />
        <% end %>
      </div>
    </div>
    """
  end

  # ── Step Indicator Component ──────────────────────────────────────────────

  attr :step, :integer, required: true

  defp step_indicator(assigns) do
    ~H"""
    <div class="flex items-center justify-center gap-0">
      <.step_dot number={1} label="Demographics" active={@step >= 1} current={@step == 1} />
      <div class={"w-16 h-0.5 #{if @step > 1, do: "bg-[#4CD964]", else: "bg-[#E5E5EA]"}"} />
      <.step_dot number={2} label="Hobbies" active={@step >= 2} current={@step == 2} />
      <div class={"w-16 h-0.5 #{if @step > 2, do: "bg-[#4CD964]", else: "bg-[#E5E5EA]"}"} />
      <.step_dot number={3} label="Materials" active={@step >= 3} current={@step == 3} />
    </div>
    """
  end

  attr :number, :integer, required: true
  attr :label, :string, required: true
  attr :active, :boolean, required: true
  attr :current, :boolean, required: true

  defp step_dot(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-1">
      <div class={[
        "w-8 h-8 rounded-full flex items-center justify-center text-sm font-semibold transition-colors",
        @current && "bg-[#4CD964] text-white",
        @active && !@current && "bg-[#E8F8EB] text-[#4CD964]",
        !@active && "bg-[#F5F5F7] text-[#8E8E93]"
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
      <span class={"text-xs font-medium #{if @active, do: "text-[#4CD964]", else: "text-[#8E8E93]"}"}>
        {@label}
      </span>
    </div>
    """
  end

  # ── Step 1: Demographics ──────────────────────────────────────────────────

  attr :current_user, :map, required: true
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
  attr :subject_class, :string, default: ""
  attr :selected_grade, :string, default: nil
  attr :selected_gender, :string, default: nil
  attr :nationality, :string, default: ""
  attr :errors, :map, default: %{}

  defp step1_demographics(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-semibold text-[#1C1C1E] mb-6">Demographics</h2>

      <div class="space-y-4">
        <%!-- Role (display only) --%>
        <div>
          <label class="block text-sm font-medium text-[#1C1C1E] mb-1">Role</label>
          <div class="px-4 py-3 bg-[#F5F5F7] rounded-lg text-[#8E8E93]">
            {String.capitalize(@current_user["role"] || "student")}
          </div>
        </div>

        <%!-- Country --%>
        <div>
          <label class="block text-sm font-medium text-[#1C1C1E] mb-1">Country *</label>
          <select
            phx-change="select_country"
            name="country_id"
            class={"w-full px-4 py-3 bg-[#F5F5F7] border rounded-lg outline-none transition-colors appearance-none #{if @errors[:country], do: "border-[#FF3B30]", else: "border-transparent focus:border-[#4CD964]"}"}
          >
            <option value="">Select a country</option>
            <option
              :for={country <- @countries}
              value={country.id}
              selected={country.id == @selected_country_id}
            >
              {country.name}
            </option>
          </select>
          <p :if={@errors[:country]} class="text-sm text-[#FF3B30] mt-1">{@errors[:country]}</p>
        </div>

        <%!-- State --%>
        <div>
          <label class="block text-sm font-medium text-[#1C1C1E] mb-1">State / Province</label>
          <select
            phx-change="select_state"
            name="state_id"
            disabled={@states == []}
            class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-lg outline-none transition-colors appearance-none disabled:opacity-50"
          >
            <option value="">Select a state</option>
            <option
              :for={state <- @states}
              value={state.id}
              selected={state.id == @selected_state_id}
            >
              {state.name}
            </option>
          </select>
        </div>

        <%!-- District --%>
        <div>
          <label class="block text-sm font-medium text-[#1C1C1E] mb-1">District</label>
          <select
            phx-change="select_district"
            name="district_id"
            disabled={@districts == []}
            class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-lg outline-none transition-colors appearance-none disabled:opacity-50"
          >
            <option value="">Select a district</option>
            <option
              :for={district <- @districts}
              value={district.id}
              selected={district.id == @selected_district_id}
            >
              {district.name}
            </option>
          </select>
        </div>

        <%!-- School --%>
        <div>
          <label class="block text-sm font-medium text-[#1C1C1E] mb-1">School</label>
          <select
            phx-change="select_school"
            name="school_id"
            disabled={@schools == []}
            class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-lg outline-none transition-colors appearance-none disabled:opacity-50"
          >
            <option value="">Select a school</option>
            <option
              :for={school <- @schools}
              value={school.id}
              selected={school.id == @selected_school_id}
            >
              {school.name}
            </option>
          </select>
        </div>

        <%!-- Subject/Class --%>
        <div>
          <label class="block text-sm font-medium text-[#1C1C1E] mb-1">Subject / Class</label>
          <input
            type="text"
            value={@subject_class}
            phx-change="update_field"
            phx-value-field="subject_class"
            name="value"
            placeholder="e.g., AP Biology, Math 101"
            class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-lg outline-none transition-colors"
          />
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <%!-- Grade Level --%>
          <div>
            <label class="block text-sm font-medium text-[#1C1C1E] mb-1">Grade Level *</label>
            <select
              phx-change="update_field"
              phx-value-field="selected_grade"
              name="value"
              class={"w-full px-4 py-3 bg-[#F5F5F7] border rounded-lg outline-none transition-colors appearance-none #{if @errors[:grade], do: "border-[#FF3B30]", else: "border-transparent focus:border-[#4CD964]"}"}
            >
              <option value="">Select grade</option>
              <option :for={grade <- @grade_options} value={grade} selected={grade == @selected_grade}>
                {grade}
              </option>
            </select>
            <p :if={@errors[:grade]} class="text-sm text-[#FF3B30] mt-1">{@errors[:grade]}</p>
          </div>

          <%!-- Gender --%>
          <div>
            <label class="block text-sm font-medium text-[#1C1C1E] mb-1">Gender</label>
            <select
              phx-change="update_field"
              phx-value-field="selected_gender"
              name="value"
              class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-lg outline-none transition-colors appearance-none"
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
          <label class="block text-sm font-medium text-[#1C1C1E] mb-1">Nationality</label>
          <input
            type="text"
            value={@nationality}
            phx-change="update_field"
            phx-value-field="nationality"
            name="value"
            placeholder="e.g., American, Korean"
            class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-lg outline-none transition-colors"
          />
        </div>
      </div>

      <%!-- Next button --%>
      <div class="flex justify-end mt-8">
        <button
          phx-click="next_step"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-8 py-3 rounded-full shadow-md transition-colors"
        >
          Next
        </button>
      </div>
    </div>
    """
  end

  # ── Step 2: Hobbies ──────────────────────────────────────────────────────

  attr :hobbies, :list, required: true
  attr :selected_hobby_ids, :any, required: true
  attr :hobby_interests, :map, required: true

  defp step2_hobbies(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-semibold text-[#1C1C1E] mb-2">Your Hobbies</h2>
      <p class="text-sm text-[#8E8E93] mb-6">
        Select hobbies to help us personalize your study experience.
      </p>

      <div class="grid grid-cols-2 md:grid-cols-3 gap-4">
        <div :for={hobby <- @hobbies}>
          <button
            type="button"
            phx-click="toggle_hobby"
            phx-value-hobby-id={hobby.id}
            class={[
              "w-full p-4 rounded-2xl border-2 text-left transition-all",
              if(MapSet.member?(@selected_hobby_ids, hobby.id),
                do: "border-[#4CD964] bg-[#E8F8EB]",
                else: "border-[#E5E5EA] bg-white hover:border-[#4CD964]"
              )
            ]}
          >
            <p class="font-semibold text-[#1C1C1E]">{hobby.name}</p>
            <p class="text-xs text-[#8E8E93] mt-1">{hobby.category}</p>
          </button>

          <div :if={MapSet.member?(@selected_hobby_ids, hobby.id)} class="mt-2">
            <input
              type="text"
              placeholder={"Specific interests (e.g., #{example_interests(hobby.name)})"}
              value={Map.get(@hobby_interests, hobby.id, "")}
              phx-change="update_hobby_interest"
              phx-value-hobby-id={hobby.id}
              name="value"
              class="w-full px-3 py-2 text-sm bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-lg outline-none transition-colors"
            />
          </div>
        </div>
      </div>

      <%!-- Navigation buttons --%>
      <div class="flex justify-between mt-8">
        <button
          phx-click="prev_step"
          class="bg-white hover:bg-gray-50 text-[#1C1C1E] font-medium px-8 py-3 rounded-full shadow-sm border border-gray-200 transition-colors"
        >
          Back
        </button>
        <button
          phx-click="next_step"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-8 py-3 rounded-full shadow-md transition-colors"
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

  defp step3_upload(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-semibold text-[#1C1C1E] mb-2">Upload Materials</h2>
      <p class="text-sm text-[#8E8E93] mb-6">
        Upload your course materials (PDFs, images) for AI-powered study assistance.
      </p>

      <form id="upload-form" phx-change="validate_upload" phx-submit="complete_setup">
        <%!-- Drop zone --%>
        <div
          class="border-2 border-dashed border-[#E5E5EA] rounded-2xl p-8 text-center hover:border-[#4CD964] transition-colors"
          phx-drop-target={@uploads.materials.ref}
        >
          <svg
            class="w-12 h-12 mx-auto text-[#8E8E93] mb-4"
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
          <p class="text-[#1C1C1E] font-medium mb-1">Drag and drop files here</p>
          <p class="text-sm text-[#8E8E93] mb-4">or</p>
          <label class="inline-block bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md cursor-pointer transition-colors">
            Browse Files <.live_file_input upload={@uploads.materials} class="hidden" />
          </label>
          <p class="text-xs text-[#8E8E93] mt-4">
            PDF, JPG, PNG up to 50MB each (max 5 files)
          </p>
        </div>

        <%!-- Upload entries --%>
        <div :if={@uploads.materials.entries != []} class="mt-4 space-y-3">
          <div
            :for={entry <- @uploads.materials.entries}
            class="flex items-center gap-3 p-3 bg-[#F5F5F7] rounded-xl"
          >
            <svg
              class="w-5 h-5 text-[#8E8E93] shrink-0"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z"
              />
            </svg>
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-[#1C1C1E] truncate">{entry.client_name}</p>
              <div class="w-full bg-[#E5E5EA] rounded-full h-1.5 mt-1">
                <div
                  class="bg-[#4CD964] h-1.5 rounded-full transition-all"
                  style={"width: #{entry.progress}%"}
                />
              </div>
            </div>
            <button
              type="button"
              phx-click="cancel_upload"
              phx-value-ref={entry.ref}
              class="text-[#FF3B30] hover:text-red-700 shrink-0"
              aria-label="Remove file"
            >
              <svg
                class="w-5 h-5"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>

        <%!-- Upload errors --%>
        <div :for={err <- upload_errors(@uploads.materials)} class="mt-2">
          <p class="text-sm text-[#FF3B30]">{upload_error_to_string(err)}</p>
        </div>

        <%!-- Navigation buttons --%>
        <div class="flex justify-between mt-8">
          <button
            type="button"
            phx-click="prev_step"
            class="bg-white hover:bg-gray-50 text-[#1C1C1E] font-medium px-8 py-3 rounded-full shadow-sm border border-gray-200 transition-colors"
          >
            Back
          </button>
          <button
            type="submit"
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-8 py-3 rounded-full shadow-md transition-colors"
          >
            Complete Setup
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp upload_error_to_string(:too_large), do: "File is too large (max 50MB)"
  defp upload_error_to_string(:not_accepted), do: "File type not accepted (PDF, JPG, PNG only)"
  defp upload_error_to_string(:too_many_files), do: "Maximum 5 files allowed"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
end
