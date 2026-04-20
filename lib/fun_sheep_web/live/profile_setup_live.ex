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

    socket =
      socket
      |> assign(
        page_title: "Profile Setup",
        step: 1,
        # Step 1 fields
        countries: countries,
        states: existing.states,
        districts: existing.districts,
        schools: existing.schools,
        grade_options: @grade_options,
        gender_options: @gender_options,
        selected_country_id: existing.country_id,
        selected_state_id: existing.state_id,
        selected_district_id: existing.district_id,
        selected_school_id: existing.school_id,
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

  defp load_existing_profile(current_user) do
    empty = %{
      grade: nil,
      gender: nil,
      ethnicity: nil,
      school_id: nil,
      country_id: nil,
      state_id: nil,
      district_id: nil,
      states: [],
      districts: [],
      schools: [],
      hobby_ids: MapSet.new(),
      hobby_interests: %{}
    }

    interactor_id = current_user && current_user["interactor_user_id"]

    case interactor_id && Accounts.get_user_role_by_interactor_id(interactor_id) do
      %Accounts.UserRole{} = user_role ->
        location = rebuild_location_cascades(user_role.school_id)

        student_hobbies = Learning.list_hobbies_for_user(user_role.id)

        hobby_ids =
          student_hobbies
          |> Enum.map(& &1.hobby_id)
          |> MapSet.new()

        hobby_interests =
          Map.new(student_hobbies, fn sh ->
            {sh.hobby_id, get_in(sh.specific_interests, ["text"]) || ""}
          end)

        Map.merge(empty, %{
          grade: user_role.grade,
          gender: user_role.gender,
          ethnicity: user_role.ethnicity,
          school_id: user_role.school_id,
          country_id: location.country_id,
          state_id: location.state_id,
          district_id: location.district_id,
          states: location.states,
          districts: location.districts,
          schools: location.schools,
          hobby_ids: hobby_ids,
          hobby_interests: hobby_interests
        })

      _ ->
        empty
    end
  end

  defp rebuild_location_cascades(nil) do
    %{country_id: nil, state_id: nil, district_id: nil, states: [], districts: [], schools: []}
  end

  defp rebuild_location_cascades(school_id) do
    with %FunSheep.Geo.School{district_id: district_id} <- Geo.get_school(school_id),
         %FunSheep.Geo.District{state_id: state_id} = district <- Geo.get_district(district_id),
         %FunSheep.Geo.State{country_id: country_id} <- Geo.get_state(state_id) do
      %{
        country_id: country_id,
        state_id: state_id,
        district_id: district_id,
        states: Geo.list_states_by_country(country_id),
        districts: Geo.list_districts_by_state(state_id),
        schools: Geo.list_schools_by_district(district.id)
      }
    else
      _ ->
        %{country_id: nil, state_id: nil, district_id: nil, states: [], districts: [], schools: []}
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
      {:noreply,
       socket
       |> put_flash(:info, "Profile setup complete!")
       |> redirect(to: "/dashboard")}
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
      <h1 class="text-2xl font-bold text-[#1C1C1E] text-center mb-2">Profile Setup</h1>
      <p class="text-[#8E8E93] text-center mb-8">
        Let's set up your profile to personalize your learning experience.
      </p>

      <%!-- Step Indicator --%>
      <.step_indicator step={@step} />

      <%!-- Step Content --%>
      <div class="bg-white rounded-2xl shadow-md p-4 sm:p-8 mt-6 sm:mt-8">
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
              selected_grade={@selected_grade}
              selected_gender={@selected_gender}
              ethnicity={@ethnicity}
              errors={@step1_errors}
            />
          <% 2 -> %>
            <.step2_hobbies
              hobbies={@hobbies}
              selected_hobby_ids={@selected_hobby_ids}
              hobby_interests={@hobby_interests}
            />
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
  attr :districts, :list, required: true
  attr :schools, :list, required: true
  attr :grade_options, :list, required: true
  attr :gender_options, :list, required: true
  attr :selected_country_id, :string, default: nil
  attr :selected_state_id, :string, default: nil
  attr :selected_district_id, :string, default: nil
  attr :selected_school_id, :string, default: nil
  attr :selected_grade, :string, default: nil
  attr :selected_gender, :string, default: nil
  attr :ethnicity, :string, default: ""
  attr :errors, :map, default: %{}

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

        <%!-- District --%>
        <div>
          <label class="block text-sm font-medium text-[#1C1C1E] mb-1">District</label>
          <select
            phx-change="select_district"
            name="district_id"
            disabled={@districts == []}
            class="w-full px-4 py-3 bg-[#F5F5F7] border border-[#D1D1D6] focus:border-[#4CD964] rounded-lg outline-none transition-colors appearance-none disabled:opacity-50"
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
            class="w-full px-4 py-3 bg-[#F5F5F7] border border-[#D1D1D6] focus:border-[#4CD964] rounded-lg outline-none transition-colors appearance-none disabled:opacity-50"
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

      <%!-- Next button --%>
      <div class="flex justify-end mt-8">
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
      <div class="flex justify-between mt-8">
        <button
          phx-click="prev_step"
          class="bg-white hover:bg-gray-50 text-[#1C1C1E] font-medium px-8 py-3 rounded-full shadow-sm border border-gray-200 transition-colors"
        >
          Back
        </button>
        <button
          phx-click="complete_hobbies"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-8 py-3 rounded-full shadow-md transition-colors"
        >
          Complete Setup
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

    Enum.each(existing, fn sh ->
      unless MapSet.member?(selected_ids, sh.hobby_id) do
        Learning.delete_student_hobby(sh)
      end
    end)

    existing_hobby_ids = MapSet.new(existing, & &1.hobby_id)

    selected_ids
    |> Enum.reject(&MapSet.member?(existing_hobby_ids, &1))
    |> Enum.reduce_while(:ok, fn hobby_id, :ok ->
      case Learning.create_student_hobby(%{
             user_role_id: user_role_id,
             hobby_id: hobby_id,
             specific_interests: %{"text" => Map.get(interests, hobby_id, "")}
           }) do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
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
