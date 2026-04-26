defmodule FunSheepWeb.CourseNewLive do
  use FunSheepWeb, :live_view

  alias FunSheep.Accounts
  alias FunSheep.Courses
  alias FunSheep.Courses.KnownTestProfiles
  alias FunSheep.Courses.TextbookSearch

  @grade_options ~w(K 1 2 3 4 5 6 7 8 9 10 11 12 College)

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    user_role = load_user_role(user)

    socket =
      socket
      |> assign(
        grade_options: @grade_options,
        course_name: "",
        subject: "",
        selected_grades: if(user_role && user_role.grade, do: [user_role.grade], else: []),
        description: "",
        errors: %{},
        # Textbook selection
        textbooks: [],
        textbook_search: "",
        selected_textbook: nil,
        custom_textbook_name: "",
        textbook_mode: :none,
        show_textbook_section: false,
        # Test detection & generation
        detected_profile: nil,
        generation_brief: "",
        generation_brief_auto: false,
        # State
        user_role: user_role,
        editing_course: nil,
        saving: false,
        flow_mode: :default
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => course_id}, _url, socket) do
    course = Courses.get_course_with_chapters!(course_id)

    existing_brief = get_in(course.metadata || %{}, ["generation_config", "prompt_context"]) || ""

    socket =
      socket
      |> assign(
        page_title: "Edit Course",
        editing_course: course,
        course_name: course.name,
        subject: course.subject,
        selected_grades: course.grades || [],
        description: course.description || "",
        generation_brief: existing_brief
      )
      |> maybe_detect_profile()
      |> prefill_textbook_from_course(course)

    {:noreply, socket}
  end

  def handle_params(params, _url, socket) do
    flow_mode = if params["flow"] == "test", do: :test, else: :default

    page_title =
      case flow_mode do
        :test -> "Add a Test"
        :default -> "Add New Course"
      end

    {:noreply, assign(socket, page_title: page_title, flow_mode: flow_mode)}
  end

  defp prefill_textbook_from_course(socket, course) do
    cond do
      course.textbook_id ->
        textbook = Courses.get_textbook!(course.textbook_id)

        assign(socket,
          selected_textbook: textbook,
          textbook_mode: :selected,
          show_textbook_section: true
        )

      course.custom_textbook_name && course.custom_textbook_name != "" ->
        assign(socket,
          custom_textbook_name: course.custom_textbook_name,
          textbook_mode: :custom,
          show_textbook_section: true
        )

      true ->
        socket
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

  # ── Events ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("form_change", params, socket) do
    socket =
      socket
      |> maybe_assign(params, "course_name", :course_name)
      |> maybe_assign(params, "subject", :subject)
      |> maybe_assign(params, "description", :description)
      |> maybe_detect_profile()
      |> maybe_refresh_textbooks()

    {:noreply, socket}
  end

  def handle_event("update_brief", %{"value" => value}, socket) do
    {:noreply, assign(socket, generation_brief: value, generation_brief_auto: false)}
  end

  def handle_event("toggle_grade", %{"grade" => grade}, socket) do
    grades = socket.assigns.selected_grades
    updated = if grade in grades, do: List.delete(grades, grade), else: [grade | grades]
    {:noreply, socket |> assign(selected_grades: updated) |> maybe_refresh_textbooks()}
  end

  # ── Textbook Events ──────────────────────────────────────────────────────

  def handle_event("textbook_search", %{"textbook_query" => query}, socket) do
    subject = socket.assigns.subject
    grade = List.first(socket.assigns.selected_grades)

    textbooks =
      if subject != "" do
        TextbookSearch.search(subject, grade, query)
      else
        []
      end

    {:noreply, assign(socket, textbooks: textbooks, textbook_search: query)}
  end

  def handle_event("select_textbook", %{"key" => openlibrary_key}, socket) do
    # Find in current results — could be local DB or API result
    textbook =
      Enum.find(socket.assigns.textbooks, fn t ->
        key = if is_struct(t), do: t.openlibrary_key, else: t[:openlibrary_key]
        key == openlibrary_key
      end)

    if textbook do
      # If it's from the API (has :from_api flag), persist it
      textbook =
        if not is_struct(textbook) && textbook[:from_api] do
          attrs =
            textbook
            |> Map.drop([:id, :from_api])
            |> Map.new(fn {k, v} -> {to_string(k), v} end)

          case Courses.find_or_create_textbook(attrs) do
            {:ok, saved} -> saved
            _ -> textbook
          end
        else
          textbook
        end

      {:noreply,
       assign(socket,
         selected_textbook: textbook,
         textbook_mode: :selected,
         custom_textbook_name: ""
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("deselect_textbook", _params, socket) do
    {:noreply,
     assign(socket,
       selected_textbook: nil,
       textbook_mode: :none
     )
     |> maybe_refresh_textbooks()}
  end

  def handle_event("use_custom_textbook", _params, socket) do
    {:noreply,
     assign(socket,
       textbook_mode: :custom,
       selected_textbook: nil
     )}
  end

  def handle_event("update_custom_textbook", %{"value" => value}, socket) do
    {:noreply, assign(socket, custom_textbook_name: value)}
  end

  def handle_event("no_textbook", _params, socket) do
    {:noreply,
     assign(socket,
       textbook_mode: :skipped,
       selected_textbook: nil,
       custom_textbook_name: ""
     )}
  end

  def handle_event("back_to_textbook_list", _params, socket) do
    {:noreply,
     assign(socket, textbook_mode: :none)
     |> maybe_refresh_textbooks()}
  end

  def handle_event("save_course", _params, socket) do
    errors = validate_form(socket.assigns)

    if map_size(errors) == 0 do
      {:noreply, assign(socket, saving: true, errors: %{}) |> do_save()}
    else
      {:noreply, assign(socket, errors: errors)}
    end
  end

  # ── Save Logic ──────────────────────────────────────────────────────────

  defp do_save(socket) do
    assigns = socket.assigns
    user_role = assigns.user_role

    textbook_id =
      if assigns.textbook_mode == :selected && assigns.selected_textbook do
        textbook_field(assigns.selected_textbook, :id)
      end

    custom_textbook =
      if assigns.textbook_mode == :custom && assigns.custom_textbook_name != "" do
        assigns.custom_textbook_name
      end

    existing_metadata =
      if assigns.editing_course, do: assigns.editing_course.metadata || %{}, else: %{}

    generation_metadata = build_generation_metadata(assigns, existing_metadata)
    catalog_attrs = build_catalog_attrs(assigns)

    base_attrs =
      %{
        "name" => assigns.course_name,
        "subject" => assigns.subject,
        "grades" => assigns.selected_grades,
        "description" => assigns.description,
        "textbook_id" => textbook_id,
        "custom_textbook_name" => custom_textbook,
        "metadata" => generation_metadata
      }
      |> Map.merge(catalog_attrs)

    # Don't overwrite created_by_id or school_id when editing an existing course
    course_attrs =
      if assigns.editing_course do
        base_attrs
      else
        Map.merge(base_attrs, %{
          "created_by_id" => user_role && user_role.id,
          "school_id" => user_role && user_role.school_id
        })
      end

    course_result =
      case assigns.editing_course do
        nil -> Courses.create_course(course_attrs)
        existing -> Courses.update_course(existing, course_attrs)
      end

    case course_result do
      {:ok, course} ->
        socket =
          if assigns.editing_course do
            # Editing: only re-run the pipeline if the textbook changed, since
            # name/grade/description changes don't affect content generation.
            textbook_changed =
              course.textbook_id != assigns.editing_course.textbook_id or
                course.custom_textbook_name != assigns.editing_course.custom_textbook_name

            if textbook_changed do
              %{course_id: course.id}
              |> FunSheep.Workers.ProcessCourseWorker.new()
              |> Oban.insert()

              put_flash(socket, :info, "Course updated! Re-processing content for new textbook...")
            else
              put_flash(socket, :info, "Course updated!")
            end
          else
            # New course: always kick off the full pipeline
            %{course_id: course.id}
            |> FunSheep.Workers.ProcessCourseWorker.new()
            |> Oban.insert()

            flash_msg =
              if assigns.flow_mode == :test,
                do: "Class created! Now let's schedule the test.",
                else: "Course created! Searching for content..."

            put_flash(socket, :info, flash_msg)
          end

        redirect_path =
          cond do
            assigns.editing_course -> ~p"/courses/#{course.id}"
            assigns.flow_mode == :test -> ~p"/courses/#{course.id}/tests/new"
            true -> ~p"/courses/#{course.id}"
          end

        push_navigate(socket, to: redirect_path)

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = format_changeset_errors(changeset)

        socket
        |> assign(saving: false, errors: errors)
        |> put_flash(:error, "Please fix the errors and try again.")
    end
  end

  defp maybe_assign(socket, params, param_key, assign_key) do
    case Map.get(params, param_key) do
      nil -> socket
      value -> assign(socket, [{assign_key, value}])
    end
  end

  defp maybe_assign_brief(socket, params) do
    case Map.get(params, "generation_brief") do
      nil ->
        socket

      value ->
        # If user edited an auto-filled brief, mark as user-owned so detection won't overwrite it
        if socket.assigns.generation_brief_auto and value != socket.assigns.generation_brief do
          assign(socket, generation_brief: value, generation_brief_auto: false)
        else
          assign(socket, generation_brief: value)
        end
    end
  end

  defp maybe_detect_profile(socket) do
    case KnownTestProfiles.detect(socket.assigns.course_name) do
      {:ok, profile} ->
        socket
        |> assign(detected_profile: profile)
        # Always update subject from profile (clears stale subject from prior detection)
        |> assign(subject: profile.catalog_subject)
        |> then(fn s ->
          # Only overwrite brief if it hasn't been user-edited
          if s.assigns.generation_brief_auto or s.assigns.generation_brief == "" do
            s
            |> assign(generation_brief: profile.generation_config["prompt_context"])
            |> assign(generation_brief_auto: true)
          else
            s
          end
        end)

      :unknown ->
        socket
        |> assign(detected_profile: nil)
        |> then(fn s ->
          if s.assigns.generation_brief_auto do
            s |> assign(generation_brief: "", generation_brief_auto: false)
          else
            s
          end
        end)
    end
  end

  defp build_generation_metadata(assigns, existing_metadata) do
    profile = assigns.detected_profile
    brief = assigns.generation_brief

    generation_config =
      cond do
        profile ->
          # Known test: use profile's validation_rules, override prompt_context if user edited brief
          profile_ctx = profile.generation_config["prompt_context"]
          prompt = if brief != "" and brief != profile_ctx, do: brief, else: profile_ctx

          %{
            "prompt_context" => prompt,
            "validation_rules" => profile.generation_config["validation_rules"]
          }

        brief != "" ->
          %{
            "prompt_context" => brief,
            "validation_rules" => %{"mcq_option_count" => 4, "answer_labels" => ["A", "B", "C", "D"]}
          }

        true ->
          existing_metadata["generation_config"]
      end

    score_weights =
      if profile, do: profile.score_predictor_weights, else: existing_metadata["score_predictor_weights"]

    existing_metadata
    |> then(fn m -> if generation_config, do: Map.put(m, "generation_config", generation_config), else: m end)
    |> then(fn m -> if score_weights, do: Map.put(m, "score_predictor_weights", score_weights), else: m end)
  end

  defp build_catalog_attrs(assigns) do
    if assigns.detected_profile do
      profile = assigns.detected_profile
      %{"catalog_test_type" => profile.catalog_test_type, "catalog_subject" => profile.catalog_subject}
    else
      %{}
    end
  end

  defp maybe_refresh_textbooks(socket) do
    subject = socket.assigns.subject
    grade = List.first(socket.assigns.selected_grades)

    if subject != "" and grade != nil do
      textbooks = TextbookSearch.search(subject, grade, socket.assigns.textbook_search)
      assign(socket, textbooks: textbooks, show_textbook_section: true)
    else
      assign(socket, textbooks: [], show_textbook_section: false)
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.into(%{}, fn {field, msgs} -> {field, Enum.join(msgs, ", ")} end)
  end

  defp validate_form(assigns) do
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
      if assigns.selected_grades == [] do
        Map.put(errors, :grade, "Grade level is required")
      else
        errors
      end

    if assigns.textbook_mode == :none do
      Map.put(errors, :textbook, "Please select a textbook")
    else
      errors
    end
  end

  # ── Render ─────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-xl mx-auto">
      <div class="mb-6">
        <.link
          navigate={if @editing_course, do: ~p"/courses/#{@editing_course.id}", else: ~p"/courses"}
          class="text-gray-400 hover:text-gray-600 text-sm inline-flex items-center transition-colors font-medium"
        >
          <.icon name="hero-arrow-left" class="w-4 h-4 mr-1" /> Back
        </.link>
        <h1 class="text-2xl font-extrabold text-gray-900 mt-2">
          {cond do
            @editing_course -> "Edit Course"
            @flow_mode == :test -> "Add a Test"
            true -> "New Course"
          end}
        </h1>
        <p class="text-gray-500 text-sm mt-1">
          {cond do
            @flow_mode == :test ->
              "Tests live inside a class. Tell us about the class first, and we'll take you to schedule the test next."

            true ->
              "Define your course and textbook. We'll find questions and study materials automatically."
          end}
        </p>
      </div>

      <div class="bg-white rounded-2xl border border-gray-100 p-6 sm:p-8">
        <form id="course-form" phx-change="form_change" phx-submit="save_course">
          <div class="space-y-4">
            <%!-- Course Name --%>
            <div>
              <label class="block text-sm font-medium text-gray-900 mb-1">
                {if @flow_mode == :test, do: "Class Name *", else: "Course Name *"}
              </label>
              <input
                type="text"
                value={@course_name}
                name="course_name"
                placeholder="e.g., AP Biology, Algebra 2"
                class={"w-full px-4 py-3 bg-gray-50 text-gray-900 border rounded-full outline-none transition-colors #{if @errors[:course_name], do: "border-red-400", else: "border-gray-200 focus:border-[#4CD964]"}"}
              />
              <p :if={@errors[:course_name]} class="text-sm text-red-500 mt-1">
                {@errors[:course_name]}
              </p>
            </div>

            <%!-- Recognized test banner --%>
            <div
              :if={@detected_profile}
              class="flex items-start gap-3 p-3 bg-green-50 border border-green-200 rounded-xl"
            >
              <.icon name="hero-check-circle" class="w-5 h-5 text-green-600 shrink-0 mt-0.5" />
              <div>
                <p class="text-sm font-semibold text-green-800">{@detected_profile.display_name}</p>
                <p class="text-xs text-green-700 mt-0.5">
                  {length(@detected_profile.suggested_chapters)} chapters ·
                  {@detected_profile.generation_config["validation_rules"]["mcq_option_count"]}-option MCQ ·
                  Questions tailored to official test format
                </p>
              </div>
            </div>

            <%!-- Subject --%>
            <div>
              <label class="block text-sm font-medium text-gray-900 mb-1">Subject *</label>
              <input
                type="text"
                value={@subject}
                name="subject"
                placeholder="e.g., Biology, Mathematics"
                class={"w-full px-4 py-3 bg-gray-50 text-gray-900 border rounded-full outline-none transition-colors #{if @errors[:subject], do: "border-red-400", else: "border-gray-200 focus:border-[#4CD964]"}"}
              />
              <p :if={@errors[:subject]} class="text-sm text-red-500 mt-1">{@errors[:subject]}</p>
            </div>

            <%!-- Grade Level --%>
            <div>
              <label class="block text-sm font-medium text-gray-900 mb-2">Grade Level *</label>
              <div class="flex flex-wrap gap-2">
                <button
                  :for={grade <- @grade_options}
                  type="button"
                  phx-click="toggle_grade"
                  phx-value-grade={grade}
                  class={"px-3 py-1.5 rounded-full text-sm font-medium border transition-colors #{if grade in @selected_grades, do: "bg-[#4CD964] border-[#4CD964] text-white", else: "bg-white border-gray-200 text-gray-700 hover:border-[#4CD964]"}"}
                >
                  {grade}
                </button>
              </div>
              <p :if={@errors[:grade]} class="text-sm text-red-500 mt-1">{@errors[:grade]}</p>
            </div>

            <%!-- Generation Brief --%>
            <div>
              <label class="block text-sm font-medium text-gray-900 mb-1">
                Generation Brief
                <span class="text-gray-400 font-normal text-xs ml-1">(used by AI to generate questions)</span>
              </label>
              <textarea
                id={"brief-#{if @detected_profile, do: @detected_profile.display_name, else: "custom"}"}
                phx-change="update_brief"
                phx-debounce="300"
                name="value"
                rows="4"
                placeholder={
                  if @detected_profile,
                    do: "Auto-filled from test profile. Edit to customize.",
                    else:
                      "Describe what this course covers and how questions should be generated.\ne.g., \"Grade 10 Biology — cell biology, genetics, ecology, and evolution. NCEA Level 1 standards. Focus on application and analysis, not recall.\""
                }
                class="w-full px-4 py-3 bg-gray-50 text-gray-900 border border-gray-200 focus:border-[#4CD964] rounded-2xl outline-none transition-colors resize-none text-sm"
              >{@generation_brief}</textarea>
              <p :if={@detected_profile} class="text-xs text-gray-500 mt-1">
                Pre-filled from the recognized test profile. Edit only if you want to customize question focus.
              </p>
              <p :if={!@detected_profile} class="text-xs text-gray-500 mt-1">
                The more specific your brief, the better the AI-generated questions will match your course.
              </p>
            </div>

            <%!-- Textbook Selection — shown once subject + grade are filled --%>
            <.textbook_selector
              :if={@show_textbook_section}
              textbooks={@textbooks}
              textbook_search={@textbook_search}
              selected_textbook={@selected_textbook}
              custom_textbook_name={@custom_textbook_name}
              textbook_mode={@textbook_mode}
            />
          </div>

          <%!-- What happens next --%>
          <div class="mt-6 p-4 bg-[#F5F5F7] rounded-xl">
            <p class="text-xs font-medium text-[#8E8E93] uppercase tracking-wide mb-2">
              What happens next
            </p>
            <ul class="text-sm text-[#8E8E93] space-y-1">
              <li class="flex items-center gap-2">
                <.icon name="hero-magnifying-glass" class="w-4 h-4 text-[#007AFF]" />
                We search for textbooks, question banks, and practice tests
              </li>
              <li class="flex items-center gap-2">
                <.icon name="hero-sparkles" class="w-4 h-4 text-[#4CD964]" />
                AI generates questions organized by chapter
              </li>
              <li class="flex items-center gap-2">
                <.icon name="hero-document-arrow-up" class="w-4 h-4 text-[#8E8E93]" />
                You can upload your own materials later to make it richer
              </li>
            </ul>
          </div>

          <%!-- Action buttons --%>
          <div class="flex justify-between mt-8">
            <.link
              navigate={~p"/courses"}
              class="bg-white hover:bg-gray-50 text-gray-900 font-medium px-8 py-3 rounded-full shadow-sm border border-gray-200 transition-colors"
            >
              Cancel
            </.link>
            <button
              type="submit"
              disabled={@saving}
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-8 py-3 rounded-full shadow-md transition-colors disabled:opacity-50"
            >
              <%= if @saving do %>
                Creating...
              <% else %>
                {cond do
                  @editing_course -> "Save Changes"
                  @flow_mode == :test -> "Continue to test"
                  true -> "Create Course"
                end}
              <% end %>
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  # ── Textbook Selector Component ──────────────────────────────────────────

  attr :textbooks, :list, required: true
  attr :textbook_search, :string, default: ""
  attr :selected_textbook, :any, default: nil
  attr :custom_textbook_name, :string, default: ""
  attr :textbook_mode, :atom, default: :none

  defp textbook_selector(assigns) do
    ~H"""
    <div class="mt-2">
      <label class="block text-sm font-medium text-gray-900 mb-2">
        Textbook <span class="text-red-500">*</span>
      </label>

      <%!-- Selected textbook confirmation --%>
      <div
        :if={@textbook_mode == :selected && @selected_textbook}
        class="flex items-center gap-4 p-4 border-2 border-purple-400 bg-purple-50 rounded-2xl"
      >
        <.textbook_cover url={textbook_field(@selected_textbook, :cover_image_url)} size="lg" />
        <div class="flex-1 min-w-0">
          <p class="font-semibold text-gray-900">
            {textbook_field(@selected_textbook, :title)}
          </p>
          <p
            :if={textbook_field(@selected_textbook, :author) not in ["", nil]}
            class="text-sm text-gray-600 truncate"
          >
            {textbook_field(@selected_textbook, :author)}
          </p>
          <p :if={textbook_field(@selected_textbook, :publisher)} class="text-xs text-gray-500">
            {textbook_field(@selected_textbook, :publisher)}
            <span :if={textbook_field(@selected_textbook, :edition)}>
              · {textbook_field(@selected_textbook, :edition)}
            </span>
          </p>
        </div>
        <button
          type="button"
          phx-click="deselect_textbook"
          class="text-sm font-medium text-purple-600 hover:text-purple-800 shrink-0"
        >
          Change
        </button>
      </div>

      <%!-- No-textbook confirmation --%>
      <div
        :if={@textbook_mode == :skipped}
        class="flex items-center justify-between gap-4 p-4 border border-gray-200 bg-gray-50 rounded-2xl"
      >
        <p class="text-sm text-gray-700">
          Proceeding without a textbook. We'll search the web for study materials.
        </p>
        <button
          type="button"
          phx-click="back_to_textbook_list"
          class="text-sm font-medium text-purple-600 hover:text-purple-800 shrink-0"
        >
          Change
        </button>
      </div>

      <%!-- Custom textbook name input --%>
      <div :if={@textbook_mode == :custom}>
        <input
          type="text"
          value={@custom_textbook_name}
          phx-change="update_custom_textbook"
          phx-debounce="300"
          name="value"
          placeholder="Enter your textbook name..."
          class="w-full px-4 py-3 bg-gray-50 text-gray-900 border border-gray-200 focus:border-purple-400 rounded-full outline-none transition-colors"
        />
        <button
          type="button"
          phx-click="back_to_textbook_list"
          class="text-sm text-purple-600 hover:text-purple-800 font-medium mt-2"
        >
          ← Back to textbook list
        </button>
      </div>

      <%!-- Textbook search and grid (default mode) --%>
      <div :if={@textbook_mode == :none}>
        <%!-- Search input --%>
        <div class="relative">
          <svg
            class="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z"
            />
          </svg>
          <input
            type="text"
            value={@textbook_search}
            phx-change="textbook_search"
            phx-debounce="400"
            name="textbook_query"
            placeholder="Search for your textbook..."
            class="w-full pl-10 pr-4 py-3 bg-gray-50 text-gray-900 border border-gray-200 focus:border-purple-400 rounded-full outline-none transition-colors"
          />
        </div>

        <%!-- Textbook results grid --%>
        <div
          :if={@textbooks != []}
          class="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-3 max-h-72 overflow-y-auto"
        >
          <button
            :for={textbook <- Enum.take(@textbooks, 24)}
            type="button"
            phx-click="select_textbook"
            phx-value-key={textbook_field(textbook, :openlibrary_key)}
            class="flex items-center gap-3 p-3 border-2 border-gray-100 bg-white hover:border-purple-300 rounded-2xl text-left transition-all"
          >
            <.textbook_cover url={textbook_field(textbook, :cover_image_url)} />
            <div class="flex-1 min-w-0">
              <p class="font-semibold text-gray-900 text-sm truncate">
                {textbook_field(textbook, :title)}
              </p>
              <p
                :if={textbook_field(textbook, :author) not in ["", nil]}
                class="text-xs text-gray-600 truncate"
              >
                {textbook_field(textbook, :author)}
              </p>
              <p :if={textbook_field(textbook, :publisher)} class="text-xs text-gray-500 truncate">
                {textbook_field(textbook, :publisher)}
                <span :if={textbook_field(textbook, :edition)}>
                  · {textbook_field(textbook, :edition)}
                </span>
              </p>
            </div>
          </button>
        </div>

        <p
          :if={@textbooks == [] && @textbook_search != ""}
          class="text-sm text-gray-500 mt-3 text-center py-4"
        >
          No textbooks found. Try a different search or use the options below.
        </p>

        <%!-- Action links --%>
        <div class="flex items-center gap-4 mt-3 text-sm">
          <button
            type="button"
            phx-click="use_custom_textbook"
            class="text-purple-600 hover:text-purple-800 font-medium"
          >
            My textbook isn't listed
          </button>
          <span class="text-gray-300">|</span>
          <button
            type="button"
            phx-click="no_textbook"
            class="text-gray-500 hover:text-gray-700 font-medium"
          >
            I don't have a textbook
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :url, :string, default: nil
  attr :size, :string, default: "sm"

  defp textbook_cover(assigns) do
    {img_class, icon_class} =
      case assigns.size do
        "lg" ->
          {"w-16 h-20 object-cover rounded-lg bg-gray-100 shrink-0", "w-8 h-8 text-gray-400"}

        _ ->
          {"w-12 h-16 object-cover rounded-lg bg-gray-100 shrink-0", "w-6 h-6 text-gray-400"}
      end

    container_class =
      case assigns.size do
        "lg" -> "w-16 h-20 bg-gray-100 rounded-lg shrink-0"
        _ -> "w-12 h-16 bg-gray-100 rounded-lg shrink-0"
      end

    assigns =
      assigns
      |> assign(:img_class, img_class)
      |> assign(:icon_class, icon_class)
      |> assign(:container_class, container_class)

    ~H"""
    <%= if @url do %>
      <img
        src={@url}
        class={@img_class}
        onerror="this.style.display='none';this.nextElementSibling.style.display='flex'"
      />
      <div class={[@container_class, "items-center justify-center hidden"]}>
        <svg
          class={@icon_class}
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M12 6.042A8.967 8.967 0 0 0 6 3.75c-1.052 0-2.062.18-3 .512v14.25A8.987 8.987 0 0 1 6 18c2.305 0 4.408.867 6 2.292m0-14.25a8.966 8.966 0 0 1 6-2.292c1.052 0 2.062.18 3 .512v14.25A8.987 8.987 0 0 0 18 18a8.967 8.967 0 0 0-6 2.292m0-14.25v14.25"
          />
        </svg>
      </div>
    <% else %>
      <div class={[@container_class, "flex items-center justify-center"]}>
        <svg
          class={@icon_class}
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M12 6.042A8.967 8.967 0 0 0 6 3.75c-1.052 0-2.062.18-3 .512v14.25A8.987 8.987 0 0 1 6 18c2.305 0 4.408.867 6 2.292m0-14.25a8.966 8.966 0 0 1 6-2.292c1.052 0 2.062.18 3 .512v14.25A8.987 8.987 0 0 0 18 18a8.967 8.967 0 0 0-6 2.292m0-14.25v14.25"
          />
        </svg>
      </div>
    <% end %>
    """
  end

  defp textbook_field(textbook, field) when is_struct(textbook) do
    Map.get(textbook, field)
  end

  defp textbook_field(textbook, field) when is_map(textbook) do
    Map.get(textbook, field) || Map.get(textbook, to_string(field))
  end

  defp textbook_field(_, _), do: nil
end
