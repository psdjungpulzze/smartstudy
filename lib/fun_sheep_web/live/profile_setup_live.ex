defmodule FunSheepWeb.ProfileSetupLive do
  use FunSheepWeb, :live_view

  require Logger

  alias FunSheep.Accounts
  alias FunSheep.Geo
  alias FunSheep.Learning

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
    existing = load_existing_profile(socket.assigns.current_user)
    has_data? = profile_has_data?(existing)

    socket =
      socket
      |> assign(
        page_title: "Profile",
        # mode :view shows a read-only summary; :edit shows the wizard.
        # first_time? preserves onboarding redirect-to-dashboard behaviour.
        mode: if(has_data?, do: :view, else: :edit),
        first_time?: not has_data?,
        summary_hobbies: existing.summary_hobbies,
        summary_school: existing.summary_school,
        step: 1,
        # Step 1 fields
        countries: countries,
        states: existing.states,
        grade_options: @grade_options,
        gender_options: @gender_options,
        selected_country_id: existing.country_id,
        selected_state_id: existing.state_id,
        selected_school_id: existing.school_id,
        # Keep a lightweight reference to the already-chosen school so the
        # autocomplete can render its name without an extra query.
        selected_school: existing.summary_school,
        # School autocomplete state — query + top-N results live here.
        school_query: "",
        school_results: [],
        selected_grade: existing.grade,
        selected_gender: existing.gender,
        ethnicity: existing.ethnicity || "",
        step1_errors: %{},
        # Step 2 fields
        hobbies: Learning.list_hobbies(),
        selected_hobby_ids: existing.hobby_ids,
        hobby_interests: existing.hobby_interests
      )

    {:ok, socket}
  end

  defp profile_has_data?(existing) do
    (is_binary(existing.grade) and existing.grade != "") or
      MapSet.size(existing.hobby_ids) > 0
  end

  defp load_existing_profile(current_user) do
    empty = %{
      grade: nil,
      gender: nil,
      ethnicity: nil,
      school_id: nil,
      country_id: nil,
      state_id: nil,
      states: [],
      hobby_ids: MapSet.new(),
      hobby_interests: %{},
      summary_hobbies: [],
      summary_school: nil
    }

    interactor_id = current_user && current_user["interactor_user_id"]

    case interactor_id && Accounts.get_user_role_by_interactor_id(interactor_id) do
      %Accounts.UserRole{} = user_role ->
        location = rebuild_location_from_school(user_role.school_id)

        student_hobbies = Learning.list_hobbies_for_user(user_role.id)

        hobby_ids =
          student_hobbies
          |> Enum.map(& &1.hobby_id)
          |> MapSet.new()

        hobby_interests =
          Map.new(student_hobbies, fn sh ->
            {sh.hobby_id, get_in(sh.specific_interests, ["text"]) || ""}
          end)

        summary_hobbies =
          Enum.map(student_hobbies, fn sh ->
            %{
              id: sh.hobby_id,
              name: sh.hobby && sh.hobby.name,
              category: sh.hobby && sh.hobby.category,
              interest: get_in(sh.specific_interests, ["text"]) || ""
            }
          end)

        Map.merge(empty, %{
          grade: user_role.grade,
          gender: user_role.gender,
          ethnicity: user_role.ethnicity,
          school_id: user_role.school_id,
          country_id: location.country_id,
          state_id: location.state_id,
          states: location.states,
          hobby_ids: hobby_ids,
          hobby_interests: hobby_interests,
          summary_hobbies: summary_hobbies,
          summary_school: location.school
        })

      _ ->
        empty
    end
  end

  # Resolve (country_id, state_id, states-for-country, school) from a saved
  # school_id. Schools ingested from NCES carry state_id/country_id directly
  # (denormalized), while legacy seed schools only have district_id — fall
  # back to the district→state walk for those.
  defp rebuild_location_from_school(nil) do
    %{country_id: nil, state_id: nil, states: [], school: nil}
  end

  defp rebuild_location_from_school(school_id) do
    case Geo.get_school(school_id) do
      %FunSheep.Geo.School{} = school ->
        {state_id, country_id} = resolve_state_and_country(school)

        states =
          if country_id, do: Geo.list_states_by_country(country_id), else: []

        %{country_id: country_id, state_id: state_id, states: states, school: school}

      _ ->
        %{country_id: nil, state_id: nil, states: [], school: nil}
    end
  end

  defp resolve_state_and_country(%FunSheep.Geo.School{} = s) do
    cond do
      s.state_id && s.country_id ->
        {s.state_id, s.country_id}

      s.district_id ->
        case Geo.get_district(s.district_id) do
          %FunSheep.Geo.District{state_id: state_id} ->
            case state_id && Geo.get_state(state_id) do
              %FunSheep.Geo.State{country_id: country_id} -> {state_id, country_id}
              _ -> {state_id, nil}
            end

          _ ->
            {nil, nil}
        end

      true ->
        {s.state_id, s.country_id}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("step1_change", params, socket) do
    socket =
      socket
      |> maybe_assign(params, "selected_grade", :selected_grade)
      |> maybe_assign(params, "selected_gender", :selected_gender)
      |> maybe_assign(params, "ethnicity", :ethnicity)

    {:noreply, socket}
  end

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
       selected_state_id: nil,
       selected_school_id: nil,
       selected_school: nil,
       school_query: "",
       school_results: []
     )}
  end

  def handle_event("select_state", %{"state_id" => state_id}, socket) do
    # Pre-populate the top 20 schools for the chosen state so the user sees
    # options immediately without having to type.
    results =
      if state_id != "" do
        Geo.search_schools(state_id: state_id, limit: 20)
      else
        []
      end

    {:noreply,
     assign(socket,
       selected_state_id: state_id,
       selected_school_id: nil,
       selected_school: nil,
       school_query: "",
       school_results: results
     )}
  end

  # phx-keyup sends `%{"key" => key, "value" => current_input_value}`.
  # phx-change on a wrapping form would send `%{"school_query" => ...}`.
  # Accept both shapes so the autocomplete works regardless of how it's wired.
  def handle_event("search_schools", params, socket) do
    query = params["value"] || params["school_query"] || params["query"] || ""
    state_id = socket.assigns.selected_state_id
    country_id = socket.assigns.selected_country_id

    results =
      cond do
        state_id not in [nil, ""] ->
          Geo.search_schools(state_id: state_id, query: query, limit: 20)

        country_id not in [nil, ""] ->
          Geo.search_schools(country_id: country_id, query: query, limit: 20)

        true ->
          []
      end

    {:noreply, assign(socket, school_query: query, school_results: results)}
  end

  def handle_event("select_school", %{"school_id" => school_id}, socket) do
    school = school_id && school_id != "" && Geo.get_school(school_id)

    {:noreply,
     assign(socket,
       selected_school_id: school_id,
       selected_school: school || nil,
       # Collapse the result list once a school is picked.
       school_results: []
     )}
  end

  def handle_event("clear_school", _params, socket) do
    state_id = socket.assigns.selected_state_id

    results =
      if state_id not in [nil, ""] do
        Geo.search_schools(state_id: state_id, limit: 20)
      else
        []
      end

    {:noreply,
     assign(socket,
       selected_school_id: nil,
       selected_school: nil,
       school_query: "",
       school_results: results
     )}
  end

  def handle_event("update_field", %{"field" => field, "value" => value}, socket) do
    key = String.to_existing_atom(field)
    {:noreply, assign(socket, [{key, value}])}
  end

  def handle_event("next_step", params, %{assigns: %{step: 1}} = socket) do
    # Ensure form params are captured in assigns (fallback if step1_change didn't fire)
    socket =
      socket
      |> maybe_assign(params, "selected_grade", :selected_grade)
      |> maybe_assign(params, "selected_gender", :selected_gender)
      |> maybe_assign(params, "ethnicity", :ethnicity)

    errors = validate_step1(socket.assigns)

    if map_size(errors) == 0 do
      case save_profile_now(socket.assigns) do
        {:ok, _user_role} ->
          hobbies = Learning.list_hobbies()
          {:noreply, assign(socket, step: 2, hobbies: hobbies, step1_errors: %{})}

        {:error, reason} ->
          Logger.error("ProfileSetupLive demographics save failed: #{inspect(reason)}")

          {:noreply,
           socket
           |> put_flash(:error, "Could not save profile: #{format_save_error(reason)}")
           |> assign(step1_errors: %{})}
      end
    else
      {:noreply, assign(socket, step1_errors: errors)}
    end
  end

  def handle_event("complete_hobbies", _params, socket) do
    assigns = socket.assigns

    # Safety net: re-save profile in case step 1's save was missed
    # (e.g. user landed directly on step 2 via back/forward, or earlier save silently failed).
    with {:ok, user_role} <- save_profile_now(assigns),
         :ok <-
           save_hobbies(
             user_role.id,
             assigns.selected_hobby_ids,
             assigns.hobby_interests
           ) do
      if assigns.first_time? do
        {:noreply,
         socket
         |> put_flash(:info, "Profile setup complete!")
         |> redirect(to: "/dashboard")}
      else
        # Returning user finished an edit — refresh the summary and flip back to view mode.
        refreshed = load_existing_profile(assigns.current_user)

        {:noreply,
         socket
         |> put_flash(:info, "Profile updated.")
         |> assign(
           mode: :view,
           step: 1,
           summary_hobbies: refreshed.summary_hobbies,
           summary_school: refreshed.summary_school,
           selected_grade: refreshed.grade,
           selected_gender: refreshed.gender,
           ethnicity: refreshed.ethnicity || "",
           selected_country_id: refreshed.country_id,
           selected_state_id: refreshed.state_id,
           selected_school_id: refreshed.school_id,
           selected_school: refreshed.summary_school,
           states: refreshed.states,
           school_query: "",
           school_results: [],
           selected_hobby_ids: refreshed.hobby_ids,
           hobby_interests: refreshed.hobby_interests
         )}
      end
    else
      {:error, reason} ->
        Logger.error("ProfileSetupLive complete_hobbies save failed: #{inspect(reason)}")

        {:noreply,
         put_flash(socket, :error, "Could not save profile: #{format_save_error(reason)}")}
    end
  end

  def handle_event("prev_step", _params, %{assigns: %{step: step}} = socket) when step > 1 do
    {:noreply, assign(socket, step: step - 1)}
  end

  def handle_event("edit_profile", _params, socket) do
    {:noreply, assign(socket, mode: :edit, step: 1, step1_errors: %{})}
  end

  def handle_event("cancel_edit", _params, socket) do
    # Revert any in-flight form changes by re-reading the persisted profile.
    refreshed = load_existing_profile(socket.assigns.current_user)

    {:noreply,
     assign(socket,
       mode: :view,
       step: 1,
       step1_errors: %{},
       summary_hobbies: refreshed.summary_hobbies,
       summary_school: refreshed.summary_school,
       selected_grade: refreshed.grade,
       selected_gender: refreshed.gender,
       ethnicity: refreshed.ethnicity || "",
       selected_country_id: refreshed.country_id,
       selected_state_id: refreshed.state_id,
       selected_school_id: refreshed.school_id,
       selected_school: refreshed.summary_school,
       states: refreshed.states,
       school_query: "",
       school_results: [],
       selected_hobby_ids: refreshed.hobby_ids,
       hobby_interests: refreshed.hobby_interests
     )}
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
      <%= case @mode do %>
        <% :view -> %>
          <.profile_summary
            current_user={@current_user}
            grade={@selected_grade}
            gender={@selected_gender}
            ethnicity={@ethnicity}
            school={@summary_school}
            hobbies={@summary_hobbies}
          />
        <% :edit -> %>
          <h1 class="text-2xl font-bold text-[#1C1C1E] text-center mb-2">
            {if @first_time?, do: "Profile Setup", else: "Edit Profile"}
          </h1>
          <p class="text-[#8E8E93] text-center mb-8">
            {if @first_time?,
              do: "Let's set up your profile to personalize your learning experience.",
              else: "Update your profile to keep personalization fresh."}
          </p>

          <.step_indicator step={@step} />

          <div class="bg-white rounded-2xl shadow-md p-4 sm:p-8 mt-6 sm:mt-8">
            <%= case @step do %>
              <% 1 -> %>
                <.step1_demographics
                  current_user={@current_user}
                  countries={@countries}
                  states={@states}
                  grade_options={@grade_options}
                  gender_options={@gender_options}
                  selected_country_id={@selected_country_id}
                  selected_state_id={@selected_state_id}
                  selected_school_id={@selected_school_id}
                  selected_school={@selected_school}
                  school_query={@school_query}
                  school_results={@school_results}
                  selected_grade={@selected_grade}
                  selected_gender={@selected_gender}
                  ethnicity={@ethnicity}
                  errors={@step1_errors}
                  first_time?={@first_time?}
                />
              <% 2 -> %>
                <.step2_hobbies
                  hobbies={@hobbies}
                  selected_hobby_ids={@selected_hobby_ids}
                  hobby_interests={@hobby_interests}
                  first_time?={@first_time?}
                />
            <% end %>
          </div>
      <% end %>
    </div>
    """
  end

  # ── Profile Summary (view mode) ───────────────────────────────────────────

  attr :current_user, :map, required: true
  attr :grade, :string, default: nil
  attr :gender, :string, default: nil
  attr :ethnicity, :string, default: ""
  attr :school, :any, default: nil
  attr :hobbies, :list, default: []

  defp profile_summary(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-6 sm:p-8">
      <div class="flex items-center justify-between mb-6 gap-4 flex-wrap">
        <div>
          <h1 class="text-2xl font-bold text-[#1C1C1E]">Your Profile</h1>
          <p class="text-sm text-[#8E8E93] mt-1">
            {@current_user["display_name"] || @current_user["email"]}
          </p>
        </div>
        <button
          phx-click="edit_profile"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
        >
          Edit
        </button>
      </div>

      <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-4">
        <.summary_field label="Role" value={String.capitalize(@current_user["role"] || "student")} />
        <.summary_field label="Grade Level" value={@grade} />
        <.summary_field label="Gender" value={@gender} />
        <.summary_field label="Ethnicity" value={@ethnicity} />
        <div class="sm:col-span-2">
          <.summary_field label="School" value={@school && @school.name} />
        </div>
      </dl>

      <div class="mt-8">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-3">Hobbies</h2>

        <div :if={@hobbies == []} class="text-sm text-[#8E8E93]">
          No hobbies selected yet.
        </div>

        <ul :if={@hobbies != []} class="flex flex-wrap gap-2">
          <li
            :for={hobby <- @hobbies}
            class="rounded-full bg-[#E8F8EB] border border-[#4CD964]/30 px-4 py-2"
          >
            <p class="text-sm font-semibold text-[#1C1C1E]">{hobby.name}</p>
            <p :if={hobby.interest != ""} class="text-xs text-[#3DBF55] mt-0.5">
              {hobby.interest}
            </p>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, default: nil

  defp summary_field(assigns) do
    ~H"""
    <div>
      <dt class="text-xs font-medium uppercase tracking-wide text-[#8E8E93]">{@label}</dt>
      <dd class="mt-1 text-sm text-[#1C1C1E]">
        {if is_nil(@value) or @value == "", do: "—", else: @value}
      </dd>
    </div>
    """
  end

  # ── Step Indicator Component ──────────────────────────────────────────────

  attr :step, :integer, required: true

  defp step_indicator(assigns) do
    ~H"""
    <div class="flex items-center justify-center gap-0">
      <.step_dot number={1} label="Demographics" active={@step >= 1} current={@step == 1} />
      <div class={"w-8 sm:w-16 h-0.5 #{if @step > 1, do: "bg-[#4CD964]", else: "bg-[#E5E5EA]"}"} />
      <.step_dot number={2} label="Hobbies" active={@step >= 2} current={@step == 2} />
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
  attr :grade_options, :list, required: true
  attr :gender_options, :list, required: true
  attr :selected_country_id, :string, default: nil
  attr :selected_state_id, :string, default: nil
  attr :selected_school_id, :string, default: nil
  attr :selected_school, :any, default: nil
  attr :school_query, :string, default: ""
  attr :school_results, :list, default: []
  attr :selected_grade, :string, default: nil
  attr :selected_gender, :string, default: nil
  attr :ethnicity, :string, default: ""
  attr :errors, :map, default: %{}
  attr :first_time?, :boolean, default: true

  defp step1_demographics(assigns) do
    ~H"""
    <form id="step1-form" phx-change="step1_change" phx-submit="next_step">
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
            class={"w-full px-4 py-3 bg-[#F5F5F7] border rounded-lg outline-none transition-colors appearance-none #{if @errors[:country], do: "border-[#FF3B30]", else: "border-[#D1D1D6] focus:border-[#4CD964]"}"}
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
            class="w-full px-4 py-3 bg-[#F5F5F7] border border-[#D1D1D6] focus:border-[#4CD964] rounded-lg outline-none transition-colors appearance-none disabled:opacity-50"
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

        <%!-- School: typeahead over ingested 100K+ schools.
             The state filter keeps result sets tractable. --%>
        <div>
          <label class="block text-sm font-medium text-[#1C1C1E] mb-1">School</label>

          <%= if @selected_school do %>
            <div class="flex items-center justify-between gap-3 px-4 py-3 bg-[#E8F8EB] border border-[#4CD964]/30 rounded-full">
              <div class="flex-1 min-w-0">
                <div class="font-medium text-[#1C1C1E] truncate">{@selected_school.name}</div>
                <div :if={@selected_school.city} class="text-xs text-[#8E8E93] truncate">
                  {@selected_school.city}{if @selected_school.type, do: " · #{@selected_school.type}"}
                </div>
              </div>
              <button
                type="button"
                phx-click="clear_school"
                class="shrink-0 text-sm font-medium text-[#4CD964] hover:text-[#3DBF55] transition-colors"
                aria-label="Clear school"
              >
                Change
              </button>
            </div>
            <input type="hidden" name="school_id" value={@selected_school_id} />
          <% else %>
            <div class="relative">
              <input
                type="text"
                name="school_query"
                value={@school_query}
                placeholder={
                  if @selected_state_id in [nil, ""],
                    do: "Select a state first",
                    else: "Search by name (e.g. Saratoga, Palo Alto)"
                }
                disabled={@selected_state_id in [nil, ""]}
                phx-keyup="search_schools"
                phx-debounce="250"
                autocomplete="off"
                class="w-full px-4 py-3 bg-[#F5F5F7] border border-[#D1D1D6] focus:border-[#4CD964] rounded-full outline-none transition-colors disabled:opacity-50"
              />

              <ul
                :if={@school_results != []}
                class="absolute z-10 mt-1 w-full max-h-64 overflow-y-auto bg-white border border-[#E5E5EA] rounded-xl shadow-lg"
              >
                <li
                  :for={school <- @school_results}
                  phx-click="select_school"
                  phx-value-school_id={school.id}
                  class="px-4 py-2 hover:bg-[#E8F8EB] cursor-pointer border-b border-[#F5F5F7] last:border-b-0"
                >
                  <div class="text-sm font-medium text-[#1C1C1E] truncate">{school.name}</div>
                  <div class="text-xs text-[#8E8E93] truncate">
                    {[school.city, school.level, school.type]
                    |> Enum.reject(&(is_nil(&1) or &1 == ""))
                    |> Enum.join(" · ")}
                  </div>
                </li>
              </ul>

              <p
                :if={@selected_state_id not in [nil, ""] and @school_query != "" and @school_results == []}
                class="text-xs text-[#8E8E93] mt-1"
              >
                No schools match "{@school_query}" in this state.
              </p>
            </div>
          <% end %>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <%!-- Grade Level --%>
          <div>
            <label class="block text-sm font-medium text-[#1C1C1E] mb-1">Grade Level *</label>
            <select
              name="selected_grade"
              class={"w-full px-4 py-3 bg-[#F5F5F7] border rounded-lg outline-none transition-colors appearance-none #{if @errors[:grade], do: "border-[#FF3B30]", else: "border-[#D1D1D6] focus:border-[#4CD964]"}"}
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
              name="selected_gender"
              class="w-full px-4 py-3 bg-[#F5F5F7] border border-[#D1D1D6] focus:border-[#4CD964] rounded-lg outline-none transition-colors appearance-none"
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

        <%!-- Ethnicity --%>
        <div>
          <label class="block text-sm font-medium text-[#1C1C1E] mb-1">Ethnicity</label>
          <input
            type="text"
            value={@ethnicity}
            name="ethnicity"
            placeholder="e.g., Korean, Hispanic, Asian"
            class="w-full px-4 py-3 bg-[#F5F5F7] border border-[#D1D1D6] focus:border-[#4CD964] rounded-lg outline-none transition-colors"
          />
        </div>
      </div>

      <%!-- Navigation buttons --%>
      <div class="flex justify-between mt-8 gap-4">
        <button
          :if={not @first_time?}
          type="button"
          phx-click="cancel_edit"
          class="bg-white hover:bg-gray-50 text-[#1C1C1E] font-medium px-6 py-3 rounded-full shadow-sm border border-gray-200 transition-colors"
        >
          Cancel
        </button>
        <span :if={@first_time?}></span>
        <button
          type="submit"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-8 py-3 rounded-full shadow-md transition-colors"
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
  attr :first_time?, :boolean, default: true

  defp step2_hobbies(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-semibold text-[#1C1C1E] mb-2">Your Hobbies</h2>
      <p class="text-sm text-[#8E8E93] mb-6">
        Select hobbies to help us personalize your study experience.
      </p>

      <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3 sm:gap-4">
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
              class="w-full px-3 py-2 text-sm bg-[#F5F5F7] border border-[#D1D1D6] focus:border-[#4CD964] rounded-lg outline-none transition-colors"
            />
          </div>
        </div>
      </div>

      <%!-- Navigation buttons --%>
      <div class="flex justify-between mt-8 gap-4 flex-wrap">
        <div class="flex gap-2">
          <button
            type="button"
            phx-click="prev_step"
            class="bg-white hover:bg-gray-50 text-[#1C1C1E] font-medium px-6 py-3 rounded-full shadow-sm border border-gray-200 transition-colors"
          >
            Back
          </button>
          <button
            :if={not @first_time?}
            type="button"
            phx-click="cancel_edit"
            class="bg-white hover:bg-gray-50 text-[#1C1C1E] font-medium px-6 py-3 rounded-full shadow-sm border border-gray-200 transition-colors"
          >
            Cancel
          </button>
        </div>
        <button
          type="button"
          phx-click="complete_hobbies"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-8 py-3 rounded-full shadow-md transition-colors"
        >
          {if @first_time?, do: "Complete Setup", else: "Save Changes"}
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

  defp maybe_assign(socket, params, param_key, assign_key) do
    case Map.get(params, param_key) do
      nil -> socket
      value -> assign(socket, [{assign_key, value}])
    end
  end

  defp non_empty(""), do: nil
  defp non_empty(nil), do: nil
  defp non_empty(val), do: val

  defp save_profile_now(assigns) do
    user = assigns.current_user
    interactor_id = user && user["interactor_user_id"]

    cond do
      is_nil(interactor_id) or interactor_id == "" ->
        {:error, :missing_interactor_user_id}

      true ->
        Accounts.upsert_user_profile(interactor_id, %{
          role: user["role"] || "student",
          email: user["email"] || "unknown@example.com",
          display_name: user["display_name"],
          grade: assigns.selected_grade,
          gender: assigns.selected_gender,
          ethnicity: assigns.ethnicity,
          school_id: non_empty(assigns.selected_school_id)
        })
    end
  end

  defp save_hobbies(user_role_id, selected_ids, interests) do
    existing = Learning.list_hobbies_for_user(user_role_id)
    existing_by_hobby = Map.new(existing, &{&1.hobby_id, &1})

    # Delete deselected hobbies.
    Enum.each(existing, fn sh ->
      unless MapSet.member?(selected_ids, sh.hobby_id) do
        Learning.delete_student_hobby(sh)
      end
    end)

    # For each selected hobby: create if new, update if the interest text changed.
    Enum.reduce_while(selected_ids, :ok, fn hobby_id, :ok ->
      new_interest_text = Map.get(interests, hobby_id, "")
      desired = %{"text" => new_interest_text}

      case Map.get(existing_by_hobby, hobby_id) do
        nil ->
          case Learning.create_student_hobby(%{
                 user_role_id: user_role_id,
                 hobby_id: hobby_id,
                 specific_interests: desired
               }) do
            {:ok, _} -> {:cont, :ok}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end

        %{specific_interests: stored} = sh ->
          stored_text = (stored || %{}) |> Map.get("text", "")

          if stored_text == new_interest_text do
            {:cont, :ok}
          else
            case Learning.update_student_hobby(sh, %{specific_interests: desired}) do
              {:ok, _} -> {:cont, :ok}
              {:error, changeset} -> {:halt, {:error, changeset}}
            end
          end
      end
    end)
  end

  defp format_save_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field} #{Enum.join(errors, ", ")}" end)
  end

  defp format_save_error(:missing_interactor_user_id),
    do: "you're not logged in. Please sign in again."

  defp format_save_error(other), do: inspect(other)
end
