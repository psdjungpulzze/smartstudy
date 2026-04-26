defmodule FunSheepWeb.TestScheduleNewLive do
  use FunSheepWeb, :live_view

  alias FunSheep.{Assessments, Courses, FixedTests}

  @question_types ~w(multiple_choice short_answer free_response true_false)

  @impl true
  def mount(%{"course_id" => course_id} = params, _session, socket) do
    course = Courses.get_course!(course_id)
    chapters = Courses.list_chapters_by_course(course_id)

    {schedule, changeset, form_name, form_date, selected_chapters, selected_sections, action} =
      case params do
        %{"schedule_id" => schedule_id} ->
          schedule = Assessments.get_test_schedule!(schedule_id)
          cs = Assessments.change_test_schedule(schedule)
          scope = schedule.scope || %{}
          ch_ids = MapSet.new(scope["chapter_ids"] || [])
          sec_ids = MapSet.new(scope["section_ids"] || [])

          {schedule, cs, schedule.name, Date.to_iso8601(schedule.test_date), ch_ids, sec_ids,
           :edit}

        _ ->
          cs = Assessments.change_test_schedule(%Assessments.TestSchedule{}, %{})
          {nil, cs, "", "", MapSet.new(), MapSet.new(), :new}
      end

    {:ok,
     socket
     |> assign(
       page_title:
         if(action == :edit,
           do: "Edit Test - #{course.name}",
           else: "New Test - #{course.name}"
         ),
       live_action: action,
       course: course,
       course_id: course_id,
       chapters: chapters,
       selected_course_id: course_id,
       schedule: schedule,
       selected_chapter_ids: selected_chapters,
       selected_section_ids: selected_sections,
       expanded_chapter_ids: MapSet.new(),
       form: to_form(changeset),
       form_name: form_name,
       form_test_date: form_date,
       # Test type (new tests only; edit always adaptive)
       test_type: :adaptive,
       # Format
       format_description: "",
       format_sections: [],
       new_section_name: "",
       new_section_type: "multiple_choice",
       new_section_count: 10,
       new_section_points: 1,
       time_limit: nil,
       question_types: @question_types
     )
     |> allow_upload(:questions_file,
       accept: ~w(.csv),
       max_entries: 1,
       max_file_size: 2_000_000
     )}
  end

  @impl true
  def handle_event("set_test_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, test_type: String.to_existing_atom(type))}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :questions_file, ref)}
  end

  def handle_event("toggle_expand", %{"chapter-id" => chapter_id}, socket) do
    expanded = socket.assigns.expanded_chapter_ids

    expanded =
      if MapSet.member?(expanded, chapter_id) do
        MapSet.delete(expanded, chapter_id)
      else
        MapSet.put(expanded, chapter_id)
      end

    {:noreply, assign(socket, expanded_chapter_ids: expanded)}
  end

  def handle_event("toggle_chapter", %{"chapter-id" => chapter_id}, socket) do
    selected_chapters = socket.assigns.selected_chapter_ids
    selected_sections = socket.assigns.selected_section_ids

    chapter = Enum.find(socket.assigns.chapters, &(&1.id == chapter_id))
    section_ids = if chapter, do: Enum.map(chapter.sections, & &1.id), else: []

    if MapSet.member?(selected_chapters, chapter_id) do
      # Deselect chapter and all its sections
      {:noreply,
       assign(socket,
         selected_chapter_ids: MapSet.delete(selected_chapters, chapter_id),
         selected_section_ids: Enum.reduce(section_ids, selected_sections, &MapSet.delete(&2, &1))
       )}
    else
      # Select chapter and all its sections
      {:noreply,
       assign(socket,
         selected_chapter_ids: MapSet.put(selected_chapters, chapter_id),
         selected_section_ids: Enum.reduce(section_ids, selected_sections, &MapSet.put(&2, &1))
       )}
    end
  end

  def handle_event(
        "toggle_section",
        %{"section-id" => section_id, "chapter-id" => chapter_id},
        socket
      ) do
    selected_sections = socket.assigns.selected_section_ids
    selected_chapters = socket.assigns.selected_chapter_ids

    chapter = Enum.find(socket.assigns.chapters, &(&1.id == chapter_id))

    selected_sections =
      if MapSet.member?(selected_sections, section_id) do
        MapSet.delete(selected_sections, section_id)
      else
        MapSet.put(selected_sections, section_id)
      end

    # Update chapter selection based on section state
    selected_chapters =
      if chapter do
        all_section_ids = MapSet.new(Enum.map(chapter.sections, & &1.id))
        selected_in_chapter = MapSet.intersection(selected_sections, all_section_ids)

        cond do
          MapSet.size(selected_in_chapter) == 0 ->
            MapSet.delete(selected_chapters, chapter_id)

          true ->
            MapSet.put(selected_chapters, chapter_id)
        end
      else
        selected_chapters
      end

    {:noreply,
     assign(socket,
       selected_section_ids: selected_sections,
       selected_chapter_ids: selected_chapters
     )}
  end

  def handle_event("select_all_chapters", _params, socket) do
    all_chapter_ids = MapSet.new(Enum.map(socket.assigns.chapters, & &1.id))

    all_section_ids =
      socket.assigns.chapters
      |> Enum.flat_map(& &1.sections)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    {:noreply,
     assign(socket,
       selected_chapter_ids: all_chapter_ids,
       selected_section_ids: all_section_ids
     )}
  end

  def handle_event("deselect_all_chapters", _params, socket) do
    {:noreply,
     assign(socket,
       selected_chapter_ids: MapSet.new(),
       selected_section_ids: MapSet.new()
     )}
  end

  def handle_event("validate", %{"name" => name, "test_date" => test_date}, socket) do
    {:noreply, assign(socket, form_name: name, form_test_date: test_date)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_description", %{"format_description" => text}, socket) do
    {:noreply, assign(socket, format_description: text)}
  end

  def handle_event("update_section_form", params, socket) do
    {:noreply,
     assign(socket,
       new_section_name: params["name"] || "",
       new_section_type: params["question_type"] || "multiple_choice",
       new_section_count: parse_int(params["count"], 10),
       new_section_points: parse_int(params["points_per_question"], 1)
     )}
  end

  def handle_event("update_time_limit", %{"time_limit" => time_limit}, socket) do
    {:noreply, assign(socket, time_limit: parse_int_or_nil(time_limit))}
  end

  def handle_event("add_section", _params, socket) do
    name = socket.assigns.new_section_name

    if name == "" do
      {:noreply, put_flash(socket, :error, "Section name is required")}
    else
      new_section = %{
        "name" => name,
        "question_type" => socket.assigns.new_section_type,
        "count" => socket.assigns.new_section_count,
        "points_per_question" => socket.assigns.new_section_points,
        "chapter_ids" => []
      }

      {:noreply,
       assign(socket,
         format_sections: socket.assigns.format_sections ++ [new_section],
         new_section_name: "",
         new_section_type: "multiple_choice",
         new_section_count: 10,
         new_section_points: 1
       )}
    end
  end

  def handle_event("remove_section", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    sections = List.delete_at(socket.assigns.format_sections, index)
    {:noreply, assign(socket, format_sections: sections)}
  end

  def handle_event("save", %{"name" => name, "test_date" => test_date}, socket) do
    case socket.assigns.test_type do
      :custom -> save_custom_test(name, socket)
      :adaptive -> save_adaptive_test(name, test_date, socket)
    end
  end

  defp save_custom_test(name, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    course_id = socket.assigns.course_id

    if String.trim(name) == "" do
      {:noreply, put_flash(socket, :error, "Test name is required")}
    else
      attrs = %{
        "title" => name,
        "course_id" => course_id,
        "created_by_id" => user_role_id,
        "visibility" => "class"
      }

      case FixedTests.create_bank(attrs) do
        {:ok, bank} ->
          all_questions =
            consume_uploaded_entries(socket, :questions_file, fn %{path: path}, _entry ->
              {:ok, parse_questions_csv(path)}
            end)
            |> List.flatten()

          {flash_key, flash_msg} =
            if all_questions == [] do
              {:info, "Custom test created — add questions now"}
            else
              case FixedTests.bulk_import_questions(bank, all_questions) do
                {:ok, _} ->
                  {:info, "Custom test created with #{length(all_questions)} question(s)"}

                {:error, _} ->
                  {:error, "Test created but some questions failed to import. Check your CSV format."}
              end
            end

          {:noreply,
           socket
           |> put_flash(flash_key, flash_msg)
           |> push_navigate(to: ~p"/custom-tests/#{bank.id}")}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    end
  end

  defp save_adaptive_test(name, test_date, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    course_id = socket.assigns.selected_course_id
    chapter_ids = MapSet.to_list(socket.assigns.selected_chapter_ids)
    section_ids = MapSet.to_list(socket.assigns.selected_section_ids)

    scope = %{"chapter_ids" => chapter_ids, "section_ids" => section_ids}

    attrs = %{
      name: name,
      test_date: test_date,
      scope: scope,
      user_role_id: user_role_id,
      course_id: course_id,
      format_description: socket.assigns.format_description
    }

    result =
      if socket.assigns.live_action == :edit && socket.assigns.schedule do
        Assessments.update_test_schedule(socket.assigns.schedule, attrs)
      else
        Assessments.create_test_schedule(attrs)
      end

    case result do
      {:ok, schedule} ->
        if socket.assigns.live_action == :new && socket.assigns.format_sections != [] do
          structure = %{
            "sections" => socket.assigns.format_sections,
            "time_limit_minutes" => socket.assigns.time_limit
          }

          case Assessments.create_test_format_template(%{
                 name: "#{name} Format",
                 structure: structure,
                 course_id: course_id,
                 created_by_id: user_role_id
               }) do
            {:ok, template} ->
              Assessments.update_test_schedule(schedule, %{format_template_id: template.id})

            _ ->
              :ok
          end
        end

        flash_msg =
          if socket.assigns.live_action == :edit,
            do: "Test updated successfully!",
            else: "Test scheduled successfully!"

        {:noreply,
         socket
         |> put_flash(:info, flash_msg)
         |> push_navigate(to: ~p"/courses/#{socket.assigns.course_id}/tests")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val
  defp parse_int(_, default), do: default

  defp parse_int_or_nil(nil), do: nil
  defp parse_int_or_nil(""), do: nil

  defp parse_int_or_nil(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int_or_nil(val) when is_integer(val), do: val
  defp parse_int_or_nil(_), do: nil

  defp format_question_type(type) do
    type
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp chapter_selection_state(chapter, selected_section_ids) do
    section_ids = MapSet.new(Enum.map(chapter.sections, & &1.id))
    selected_in_chapter = MapSet.intersection(selected_section_ids, section_ids)
    total = MapSet.size(section_ids)
    selected = MapSet.size(selected_in_chapter)

    cond do
      total == 0 -> :no_sections
      selected == total -> :all
      selected > 0 -> :partial
      true -> :none
    end
  end

  defp count_selected_items(chapters, selected_chapter_ids, selected_section_ids) do
    chapters_without_sections = Enum.filter(chapters, &(&1.sections == []))

    selected_no_section_chapters =
      Enum.count(chapters_without_sections, &MapSet.member?(selected_chapter_ids, &1.id))

    selected_sections = MapSet.size(selected_section_ids)

    total_items =
      Enum.reduce(chapters, 0, fn ch, acc ->
        if ch.sections == [], do: acc + 1, else: acc + length(ch.sections)
      end)

    {selected_no_section_chapters + selected_sections, total_items}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <div class="flex items-center gap-4 mb-8">
        <.link
          navigate={~p"/courses/#{@course_id}/tests"}
          class="text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
        >
          <.icon name="hero-arrow-left" class="w-6 h-6" />
        </.link>
        <div>
          <h1 class="text-2xl sm:text-3xl font-bold text-[#1C1C1E]">
            {if @live_action == :edit, do: "Edit Test", else: "New Test"}
          </h1>
          <p class="text-sm text-[#8E8E93]">{@course.name}</p>
        </div>
      </div>

      <div class="bg-white rounded-2xl shadow-md p-4 sm:p-8">
        <%!-- Test type toggle (new tests only) --%>
        <div :if={@live_action == :new} class="flex rounded-xl bg-[#F5F5F7] p-1 mb-6">
          <button
            type="button"
            phx-click="set_test_type"
            phx-value-type="adaptive"
            class={[
              "flex-1 py-2 text-xs sm:text-sm font-medium rounded-lg transition-colors",
              if(@test_type == :adaptive,
                do: "bg-white shadow-sm text-[#1C1C1E]",
                else: "text-[#8E8E93] hover:text-[#1C1C1E]"
              )
            ]}
          >
            Adaptive (AI questions)
          </button>
          <button
            type="button"
            phx-click="set_test_type"
            phx-value-type="custom"
            class={[
              "flex-1 py-2 text-xs sm:text-sm font-medium rounded-lg transition-colors",
              if(@test_type == :custom,
                do: "bg-white shadow-sm text-[#1C1C1E]",
                else: "text-[#8E8E93] hover:text-[#1C1C1E]"
              )
            ]}
          >
            Custom (upload questions)
          </button>
        </div>

        <form phx-submit="save" phx-change="validate" class="space-y-6">
          <div>
            <label for="test-name" class="block text-sm font-medium text-[#1C1C1E] mb-2">
              Test Name
            </label>
            <input
              id="test-name"
              type="text"
              name="name"
              value={@form_name}
              placeholder="e.g., Midterm Exam, Chapter 5 Quiz"
              required
              class="w-full px-4 py-3 bg-[#F5F5F7] dark:bg-[#2C2C2E] text-[#1C1C1E] dark:text-white border border-[#E5E5EA] dark:border-[#3A3A3C] focus:border-[#4CD964] rounded-full outline-none transition-colors"
            />
          </div>

          <%!-- Test date: required for adaptive, optional for custom --%>
          <div :if={@test_type == :adaptive or @live_action == :edit}>
            <label for="test-date" class="block text-sm font-medium text-[#1C1C1E] mb-2">
              Test Date
            </label>
            <input
              id="test-date"
              type="date"
              name="test_date"
              value={@form_test_date}
              min={Date.to_iso8601(Date.utc_today())}
              required
              class="w-full px-4 py-3 min-h-[48px] bg-[#F5F5F7] dark:bg-[#2C2C2E] text-base text-[#1C1C1E] dark:text-white border border-[#E5E5EA] dark:border-[#3A3A3C] focus:border-[#4CD964] rounded-full outline-none transition-colors"
            />
          </div>

          <%!-- Adaptive: chapter scope selection --%>
          <div :if={@test_type == :adaptive and @chapters != []}>
            <div class="flex items-center justify-between mb-2">
              <label class="block text-sm font-medium text-[#1C1C1E]">
                Test Scope
              </label>
              <div class="flex gap-2">
                <button
                  type="button"
                  phx-click="select_all_chapters"
                  class="text-xs text-[#4CD964] hover:text-[#3DBF55] font-medium"
                >
                  Select All
                </button>
                <span class="text-[#E5E5EA]">|</span>
                <button
                  type="button"
                  phx-click="deselect_all_chapters"
                  class="text-xs text-[#8E8E93] hover:text-[#1C1C1E] font-medium"
                >
                  Deselect All
                </button>
              </div>
            </div>
            <div class="space-y-1 max-h-96 overflow-y-auto bg-[#F5F5F7] rounded-xl p-4">
              <%= for chapter <- @chapters do %>
                <% state = chapter_selection_state(chapter, @selected_section_ids) %>
                <% has_sections = chapter.sections != [] %>
                <% expanded = MapSet.member?(@expanded_chapter_ids, chapter.id) %>

                <div class="rounded-lg">
                  <div class="flex items-center gap-2 p-2 rounded-lg hover:bg-white transition-colors">
                    <%= if has_sections do %>
                      <button
                        type="button"
                        phx-click="toggle_expand"
                        phx-value-chapter-id={chapter.id}
                        class="text-[#8E8E93] hover:text-[#1C1C1E] p-0.5 transition-colors"
                      >
                        <.icon
                          name={if expanded, do: "hero-chevron-down", else: "hero-chevron-right"}
                          class="w-4 h-4"
                        />
                      </button>
                    <% else %>
                      <span class="w-5" />
                    <% end %>

                    <label class="flex items-center gap-3 flex-1 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={MapSet.member?(@selected_chapter_ids, chapter.id)}
                        phx-click="toggle_chapter"
                        phx-value-chapter-id={chapter.id}
                        class={"w-5 h-5 rounded accent-[#4CD964] #{if state == :partial, do: "opacity-60"}"}
                      />
                      <span class="text-[#1C1C1E] font-medium text-sm">{chapter.name}</span>
                      <span :if={has_sections} class="text-xs text-[#8E8E93] ml-auto">
                        {MapSet.size(
                          MapSet.intersection(
                            @selected_section_ids,
                            MapSet.new(Enum.map(chapter.sections, & &1.id))
                          )
                        )} / {length(chapter.sections)}
                      </span>
                    </label>
                  </div>

                  <div :if={has_sections && expanded} class="ml-10 space-y-0.5 pb-1">
                    <label
                      :for={section <- chapter.sections}
                      class="flex items-center gap-3 p-1.5 pl-2 rounded-lg hover:bg-white cursor-pointer transition-colors"
                    >
                      <input
                        type="checkbox"
                        checked={MapSet.member?(@selected_section_ids, section.id)}
                        phx-click="toggle_section"
                        phx-value-section-id={section.id}
                        phx-value-chapter-id={chapter.id}
                        class="w-4 h-4 rounded accent-[#4CD964]"
                      />
                      <span class="text-[#1C1C1E] text-sm">{section.name}</span>
                    </label>
                  </div>
                </div>
              <% end %>
            </div>
            <% {selected, total} =
              count_selected_items(@chapters, @selected_chapter_ids, @selected_section_ids) %>
            <p class="text-xs text-[#8E8E93] mt-1">
              {selected} of {total} items selected
            </p>
          </div>

          <%!-- Custom: question upload --%>
          <div :if={@test_type == :custom} class="space-y-3">
            <div>
              <label class="block text-sm font-medium text-[#1C1C1E] mb-1">
                Upload Questions (CSV) <span class="text-[#8E8E93] font-normal">— optional</span>
              </label>
              <p class="text-xs text-[#8E8E93] mb-3">
                CSV headers: <code class="bg-[#F5F5F7] px-1 py-0.5 rounded text-xs">question_type, question_text, answer_text, explanation, points</code>.
                Valid types: <code class="bg-[#F5F5F7] px-1 py-0.5 rounded text-xs">multiple_choice</code>,
                <code class="bg-[#F5F5F7] px-1 py-0.5 rounded text-xs">true_false</code>,
                <code class="bg-[#F5F5F7] px-1 py-0.5 rounded text-xs">short_answer</code>.
                You can also add questions manually after creating the test.
              </p>

              <div
                class="border-2 border-dashed border-[#E5E5EA] rounded-2xl p-6 text-center hover:border-[#4CD964] transition-colors"
                phx-drop-target={@uploads.questions_file.ref}
              >
                <.icon name="hero-document-arrow-up" class="w-8 h-8 text-[#8E8E93] mx-auto mb-2" />
                <p class="text-sm text-[#8E8E93] mb-2">Drop a CSV file here, or</p>
                <label class="cursor-pointer bg-[#4CD964] hover:bg-[#3DBF55] text-white text-sm font-medium px-4 py-2 rounded-full transition-colors inline-block">
                  Choose File
                  <.live_file_input upload={@uploads.questions_file} class="sr-only" />
                </label>
              </div>

              <%!-- Uploaded file preview --%>
              <div :for={entry <- @uploads.questions_file.entries} class="mt-3 flex items-center gap-3 p-3 bg-[#F5F5F7] rounded-xl">
                <.icon name="hero-document-text" class="w-5 h-5 text-[#4CD964] shrink-0" />
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-medium text-[#1C1C1E] truncate">{entry.client_name}</p>
                  <p class="text-xs text-[#8E8E93]">{Float.round(entry.client_size / 1024, 1)} KB</p>
                </div>
                <button
                  type="button"
                  phx-click="cancel_upload"
                  phx-value-ref={entry.ref}
                  class="text-[#8E8E93] hover:text-[#FF3B30] transition-colors"
                >
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </div>

              <%!-- Upload errors --%>
              <p
                :for={err <- upload_errors(@uploads.questions_file)}
                class="mt-2 text-xs text-[#FF3B30]"
              >
                {upload_error_message(err)}
              </p>
            </div>
          </div>

          <div class="flex flex-col-reverse sm:flex-row sm:justify-end gap-3 pt-4">
            <.link
              navigate={~p"/courses/#{@course_id}/tests"}
              class="px-6 py-2.5 sm:py-2 text-center border border-[#E5E5EA] text-[#1C1C1E] font-medium rounded-full hover:bg-[#F5F5F7] transition-colors"
            >
              Cancel
            </.link>
            <button
              type="submit"
              phx-disable-with="Saving..."
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2.5 sm:py-2 rounded-full shadow-md transition-colors disabled:opacity-60 disabled:cursor-not-allowed"
            >
              {cond do
                @live_action == :edit -> "Save Changes"
                @test_type == :custom -> "Create Test"
                true -> "Schedule Test"
              end}
            </button>
          </div>
        </form>
      </div>

      <%!-- Test Format (adaptive only, optional) --%>
      <div :if={@test_type == :adaptive} class="bg-white rounded-2xl shadow-md p-4 sm:p-8 mt-6">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-1">Test Format</h2>
        <p class="text-sm text-[#8E8E93] mb-4">
          Paste the format you gave students — you can parse it into sections after saving
        </p>

        <form phx-change="update_description" class="mb-4">
          <textarea
            name="format_description"
            rows="5"
            placeholder="e.g.\n20 MC (30 min)\nFRQ: 1 long - 7pts, 3 - 3pt questions (35 min)"
            class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-2xl outline-none transition-colors text-sm font-mono resize-none"
          >{@format_description}</textarea>
        </form>

        <div :if={@format_sections != []} class="space-y-2 mb-4">
          <div
            :for={{section, index} <- Enum.with_index(@format_sections)}
            class="flex items-center justify-between p-3 bg-[#F5F5F7] rounded-xl"
          >
            <div>
              <p class="font-medium text-[#1C1C1E] text-sm">{section["name"]}</p>
              <p class="text-xs text-[#8E8E93]">
                {format_question_type(section["question_type"])} · {section["count"]} questions · {section[
                  "points_per_question"
                ]} pts each
              </p>
            </div>
            <button
              phx-click="remove_section"
              phx-value-index={index}
              class="text-[#FF3B30] hover:text-red-700 p-1.5 rounded-lg transition-colors"
            >
              <.icon name="hero-trash" class="w-4 h-4" />
            </button>
          </div>
        </div>

        <form phx-change="update_section_form" phx-submit="add_section" class="space-y-3">
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-medium text-[#8E8E93] mb-1">Section Name</label>
              <input
                type="text"
                name="name"
                value={@new_section_name}
                placeholder="e.g., Multiple Choice"
                class="w-full px-4 py-2.5 bg-[#F5F5F7] dark:bg-[#2C2C2E] text-[#1C1C1E] dark:text-white border border-[#E5E5EA] dark:border-[#3A3A3C] focus:border-[#4CD964] rounded-full outline-none transition-colors text-sm"
              />
            </div>
            <div>
              <label class="block text-xs font-medium text-[#8E8E93] mb-1">Question Type</label>
              <select
                name="question_type"
                class="w-full px-4 py-2.5 bg-[#F5F5F7] dark:bg-[#2C2C2E] text-[#1C1C1E] dark:text-white border border-[#E5E5EA] dark:border-[#3A3A3C] focus:border-[#4CD964] rounded-full outline-none transition-colors text-sm"
              >
                <option
                  :for={qt <- @question_types}
                  value={qt}
                  selected={qt == @new_section_type}
                >
                  {format_question_type(qt)}
                </option>
              </select>
            </div>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-medium text-[#8E8E93] mb-1"># Questions</label>
              <input
                type="number"
                name="count"
                value={@new_section_count}
                min="1"
                class="w-full px-4 py-2.5 bg-[#F5F5F7] dark:bg-[#2C2C2E] text-[#1C1C1E] dark:text-white border border-[#E5E5EA] dark:border-[#3A3A3C] focus:border-[#4CD964] rounded-full outline-none transition-colors text-sm"
              />
            </div>
            <div>
              <label class="block text-xs font-medium text-[#8E8E93] mb-1">Points Each</label>
              <input
                type="number"
                name="points_per_question"
                value={@new_section_points}
                min="1"
                class="w-full px-4 py-2.5 bg-[#F5F5F7] dark:bg-[#2C2C2E] text-[#1C1C1E] dark:text-white border border-[#E5E5EA] dark:border-[#3A3A3C] focus:border-[#4CD964] rounded-full outline-none transition-colors text-sm"
              />
            </div>
          </div>
          <button
            type="submit"
            class="text-sm font-medium text-[#4CD964] hover:text-[#3DBF55] transition-colors"
          >
            + Add Section
          </button>
        </form>

        <div class="mt-4 pt-4 border-t border-[#F5F5F7]">
          <form phx-change="update_time_limit">
            <div class="flex items-center gap-3">
              <label class="text-sm font-medium text-[#1C1C1E]">Time Limit</label>
              <input
                type="number"
                name="time_limit"
                value={@time_limit}
                placeholder="No limit"
                min="1"
                class="w-24 px-3 py-2 bg-[#F5F5F7] dark:bg-[#2C2C2E] text-[#1C1C1E] dark:text-white border border-[#E5E5EA] dark:border-[#3A3A3C] focus:border-[#4CD964] rounded-full outline-none transition-colors text-sm"
              />
              <span class="text-sm text-[#8E8E93]">minutes</span>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp upload_error_message(:too_large), do: "File too large — max 2 MB"
  defp upload_error_message(:too_many_files), do: "Only one file allowed"
  defp upload_error_message(:not_accepted), do: "Only CSV files are accepted"
  defp upload_error_message(err), do: "Upload error: #{inspect(err)}"

  defp parse_questions_csv(path) do
    valid_types = ~w(multiple_choice true_false short_answer)

    path
    |> FunSheep.Ingest.CsvParser.stream()
    |> Stream.map(fn row ->
      %{
        "question_type" => Map.get(row, "question_type") || "short_answer",
        "question_text" => Map.get(row, "question_text") || "",
        "answer_text" => Map.get(row, "answer_text") || "",
        "explanation" => Map.get(row, "explanation"),
        "points" => parse_int(Map.get(row, "points", "1"), 1)
      }
    end)
    |> Stream.filter(fn row ->
      row["question_text"] != "" and row["answer_text"] != "" and
        row["question_type"] in valid_types
    end)
    |> Enum.to_list()
  rescue
    _ -> []
  end
end
