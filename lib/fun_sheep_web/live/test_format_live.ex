defmodule FunSheepWeb.TestFormatLive do
  use FunSheepWeb, :live_view

  alias FunSheep.{Assessments, Courses}
  alias FunSheep.Assessments.{FormatParser, FormatReplicator}

  @question_types ~w(multiple_choice short_answer free_response true_false)

  @impl true
  def mount(%{"course_id" => course_id, "schedule_id" => schedule_id}, _session, socket) do
    schedule = Assessments.get_test_schedule_with_course!(schedule_id)
    user_role_id = socket.assigns.current_user["user_role_id"]
    course = Courses.get_course_with_chapters!(schedule.course_id)

    {sections, time_limit} =
      case schedule.format_template do
        %{structure: %{"sections" => s, "time_limit_minutes" => t}} -> {s, t}
        %{structure: %{"sections" => s}} -> {s, nil}
        _ -> {[], nil}
      end

    {:ok,
     assign(socket,
       page_title: "Test Format: #{schedule.name}",
       course_id: course_id,
       schedule: schedule,
       course: course,
       user_role_id: user_role_id,
       format_description: schedule.format_description || "",
       parsing: false,
       parse_error: nil,
       sections: sections,
       new_section_name: "",
       new_section_type: "multiple_choice",
       new_section_count: 10,
       new_section_points: 1,
       time_limit: time_limit,
       saved_template: schedule.format_template,
       practice_test: nil,
       question_types: @question_types
     )}
  end

  @impl true
  def handle_event("update_description", %{"format_description" => text}, socket) do
    {:noreply, assign(socket, format_description: text, parse_error: nil)}
  end

  def handle_event("parse_format", _params, socket) do
    if String.trim(socket.assigns.format_description) == "" do
      {:noreply, put_flash(socket, :error, "Paste a format description first")}
    else
      send(self(), :do_parse)
      {:noreply, assign(socket, parsing: true, parse_error: nil)}
    end
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

  def handle_event("update_time_limit", %{"time_limit" => val}, socket) do
    {:noreply, assign(socket, time_limit: parse_int_or_nil(val))}
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
         sections: socket.assigns.sections ++ [new_section],
         new_section_name: "",
         new_section_type: "multiple_choice",
         new_section_count: 10,
         new_section_points: 1
       )}
    end
  end

  def handle_event("remove_section", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    {:noreply, assign(socket, sections: List.delete_at(socket.assigns.sections, index))}
  end

  def handle_event(
        "edit_section_field",
        %{"index" => idx_str, "field" => field, "value" => val},
        socket
      ) do
    index = String.to_integer(idx_str)

    updated =
      List.update_at(socket.assigns.sections, index, fn section ->
        case field do
          "count" ->
            Map.put(section, "count", parse_int(val, section["count"]))

          "points_per_question" ->
            Map.put(
              section,
              "points_per_question",
              parse_int(val, section["points_per_question"])
            )

          "name" ->
            Map.put(section, "name", val)

          "question_type" ->
            Map.put(section, "question_type", val)

          _ ->
            section
        end
      end)

    {:noreply, assign(socket, sections: updated)}
  end

  def handle_event("save", _params, socket) do
    Assessments.update_test_schedule(socket.assigns.schedule, %{
      format_description: socket.assigns.format_description
    })

    if socket.assigns.sections == [] do
      {:noreply, put_flash(socket, :info, "Format description saved")}
    else
      structure = %{
        "sections" => socket.assigns.sections,
        "time_limit_minutes" => socket.assigns.time_limit
      }

      template_name = "#{socket.assigns.schedule.name} Format"

      result =
        case socket.assigns.saved_template do
          nil ->
            Assessments.create_test_format_template(%{
              name: template_name,
              structure: structure,
              course_id: socket.assigns.schedule.course_id,
              created_by_id: socket.assigns.user_role_id
            })

          existing ->
            Assessments.update_test_format_template(existing, %{
              name: template_name,
              structure: structure
            })
        end

      case result do
        {:ok, template} ->
          Assessments.update_test_schedule(socket.assigns.schedule, %{
            format_template_id: template.id
          })

          {:noreply,
           socket
           |> assign(saved_template: template)
           |> put_flash(:info, "Format saved!")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to save format")}
      end
    end
  end

  def handle_event("generate_practice_test", _params, socket) do
    if socket.assigns.saved_template do
      practice_test =
        FormatReplicator.generate_practice_test(
          socket.assigns.saved_template.id,
          socket.assigns.schedule.course_id,
          socket.assigns.user_role_id
        )

      {:noreply, assign(socket, practice_test: practice_test)}
    else
      {:noreply, put_flash(socket, :error, "Save the format first")}
    end
  end

  @impl true
  def handle_info(:do_parse, socket) do
    case FormatParser.parse(socket.assigns.format_description) do
      {:ok, %{sections: sections, time_limit_minutes: time_limit}} ->
        {:noreply,
         socket
         |> assign(sections: sections, time_limit: time_limit, parsing: false)
         |> put_flash(:info, "Parsed #{length(sections)} section(s) — review and adjust below")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(
           parsing: false,
           parse_error:
             "Could not parse that format. Try adjusting the text or add sections manually."
         )
         |> put_flash(:error, "Parse failed")}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto">
      <div class="flex items-center gap-4 mb-8">
        <.link
          navigate={~p"/courses/#{@course_id}/tests"}
          class="text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
        >
          <.icon name="hero-arrow-left" class="w-6 h-6" />
        </.link>
        <div>
          <h1 class="text-2xl font-bold text-[#1C1C1E]">Test Format</h1>
          <p class="text-sm text-[#8E8E93]">{@schedule.name} · {@schedule.course.name}</p>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <%!-- LEFT: Raw format text --%>
        <div class="bg-white rounded-2xl shadow-md p-6 flex flex-col gap-4">
          <div>
            <h2 class="text-base font-semibold text-[#1C1C1E]">Format Description</h2>
            <p class="text-sm text-[#8E8E93] mt-0.5">
              Paste exactly what students received
            </p>
          </div>

          <form phx-change="update_description" class="flex-1 flex flex-col gap-3">
            <textarea
              name="format_description"
              rows="12"
              placeholder="e.g.\n20 MC (30 min)\nFRQ: 1 long - 7pts\n3 - 3pt questions (35 min)"
              class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-2xl outline-none transition-colors text-sm font-mono resize-none"
            >{@format_description}</textarea>
          </form>

          <button
            phx-click="parse_format"
            disabled={@parsing}
            class="w-full bg-[#4CD964] hover:bg-[#3DBF55] disabled:opacity-50 text-white font-medium px-6 py-2.5 rounded-full shadow-md transition-colors flex items-center justify-center gap-2"
          >
            <span :if={!@parsing}>
              <.icon name="hero-sparkles" class="w-4 h-4 inline -mt-0.5" /> Parse with AI
            </span>
            <span :if={@parsing}>Parsing…</span>
          </button>

          <p :if={@parse_error} class="text-sm text-[#FF3B30]">{@parse_error}</p>
        </div>

        <%!-- RIGHT: Editable structured sections --%>
        <div class="bg-white rounded-2xl shadow-md p-6 flex flex-col gap-4">
          <div>
            <h2 class="text-base font-semibold text-[#1C1C1E]">Structured Sections</h2>
            <p class="text-sm text-[#8E8E93] mt-0.5">
              Review AI output and fine-tune as needed
            </p>
          </div>

          <div class="space-y-2 flex-1">
            <div :if={@sections == []} class="text-sm text-[#8E8E93] italic py-6 text-center">
              No sections yet — paste a description and click Parse,<br />or add sections manually below
            </div>

            <div
              :for={{section, idx} <- Enum.with_index(@sections)}
              class="p-3 bg-[#F5F5F7] rounded-xl"
            >
              <div class="flex items-start gap-2">
                <div class="flex-1 space-y-2">
                  <input
                    type="text"
                    value={section["name"]}
                    phx-change="edit_section_field"
                    phx-value-index={idx}
                    phx-value-field="name"
                    name="value"
                    class="w-full px-3 py-1.5 bg-white border border-[#E5E5EA] focus:border-[#4CD964] rounded-full outline-none transition-colors text-sm font-medium"
                  />
                  <div class="flex items-center gap-2 flex-wrap">
                    <select
                      phx-change="edit_section_field"
                      phx-value-index={idx}
                      phx-value-field="question_type"
                      name="value"
                      class="px-3 py-1 bg-white border border-[#E5E5EA] focus:border-[#4CD964] rounded-full outline-none transition-colors text-xs"
                    >
                      <option
                        :for={qt <- @question_types}
                        value={qt}
                        selected={qt == section["question_type"]}
                      >
                        {format_question_type(qt)}
                      </option>
                    </select>
                    <input
                      type="number"
                      value={section["count"]}
                      phx-change="edit_section_field"
                      phx-value-index={idx}
                      phx-value-field="count"
                      name="value"
                      min="1"
                      class="w-14 px-2 py-1 bg-white border border-[#E5E5EA] focus:border-[#4CD964] rounded-full outline-none transition-colors text-xs text-center"
                    />
                    <span class="text-xs text-[#8E8E93]">q ×</span>
                    <input
                      type="number"
                      value={section["points_per_question"]}
                      phx-change="edit_section_field"
                      phx-value-index={idx}
                      phx-value-field="points_per_question"
                      name="value"
                      min="1"
                      class="w-12 px-2 py-1 bg-white border border-[#E5E5EA] focus:border-[#4CD964] rounded-full outline-none transition-colors text-xs text-center"
                    />
                    <span class="text-xs text-[#8E8E93]">pt</span>
                  </div>
                </div>
                <button
                  phx-click="remove_section"
                  phx-value-index={idx}
                  class="text-[#FF3B30] hover:text-red-700 p-1.5 rounded-lg transition-colors"
                >
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
              </div>
            </div>
          </div>

          <%!-- Add manually (collapsed by default) --%>
          <details class="group">
            <summary class="text-sm font-medium text-[#4CD964] cursor-pointer list-none flex items-center gap-1 hover:text-[#3DBF55] select-none">
              <.icon name="hero-plus-circle" class="w-4 h-4" /> Add section manually
            </summary>
            <form phx-change="update_section_form" phx-submit="add_section" class="mt-3 space-y-2">
              <div class="grid grid-cols-2 gap-2">
                <input
                  type="text"
                  name="name"
                  value={@new_section_name}
                  placeholder="Section name"
                  class="px-3 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none text-sm"
                />
                <select
                  name="question_type"
                  class="px-3 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none text-sm"
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
              <div class="flex items-center gap-3">
                <input
                  type="number"
                  name="count"
                  value={@new_section_count}
                  min="1"
                  class="w-20 px-3 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none text-sm text-center"
                />
                <span class="text-xs text-[#8E8E93]">questions @</span>
                <input
                  type="number"
                  name="points_per_question"
                  value={@new_section_points}
                  min="1"
                  class="w-16 px-3 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none text-sm text-center"
                />
                <span class="text-xs text-[#8E8E93]">pts</span>
              </div>
              <button
                type="submit"
                class="text-sm font-medium text-[#4CD964] hover:text-[#3DBF55] transition-colors"
              >
                + Add
              </button>
            </form>
          </details>

          <%!-- Total time --%>
          <form
            phx-change="update_time_limit"
            class="flex items-center gap-3 pt-3 border-t border-[#F5F5F7]"
          >
            <label class="text-sm font-medium text-[#1C1C1E]">Total time</label>
            <input
              type="number"
              name="time_limit"
              value={@time_limit}
              placeholder="—"
              min="1"
              class="w-20 px-3 py-1.5 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none text-sm text-center"
            />
            <span class="text-sm text-[#8E8E93]">min</span>
          </form>
        </div>
      </div>

      <%!-- Summary bar --%>
      <div
        :if={@sections != []}
        class="bg-[#F5F5F7] rounded-xl px-6 py-3 mb-6 flex flex-wrap items-center gap-6 text-sm"
      >
        <span class="font-medium text-[#1C1C1E]">
          {@sections |> Enum.map(& &1["count"]) |> Enum.sum()} questions
        </span>
        <span class="text-[#8E8E93]">
          {@sections |> Enum.map(fn s -> s["count"] * s["points_per_question"] end) |> Enum.sum()} pts total
        </span>
        <span :if={@time_limit} class="text-[#8E8E93]">{@time_limit} min</span>
        <span :if={!@time_limit} class="text-[#8E8E93]">No time limit</span>
      </div>

      <%!-- Action buttons --%>
      <div class="flex flex-wrap items-center gap-3 mb-6">
        <button
          phx-click="save"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
        >
          Save Format
        </button>
        <button
          :if={@saved_template != nil}
          phx-click="generate_practice_test"
          class="px-6 py-2 border border-[#4CD964] text-[#4CD964] font-medium rounded-full hover:bg-[#E8F8EB] transition-colors"
        >
          Generate Practice Test
        </button>
        <.link
          :if={@saved_template != nil}
          navigate={~p"/courses/#{@course_id}/tests/#{@schedule.id}/format-test"}
          class="px-6 py-2 border border-[#E5E5EA] text-[#1C1C1E] font-medium rounded-full hover:bg-[#F5F5F7] transition-colors"
        >
          Take Practice Test
        </.link>
      </div>

      <%!-- Practice test preview --%>
      <div :if={@practice_test} class="bg-white rounded-2xl shadow-md p-6">
        <h2 class="text-base font-semibold text-[#1C1C1E] mb-4">Practice Test Preview</h2>
        <div class="bg-[#F5F5F7] rounded-xl p-4 mb-4 grid grid-cols-3 gap-4 text-center">
          <div>
            <p class="text-2xl font-bold text-[#1C1C1E]">{@practice_test.total_questions}</p>
            <p class="text-xs text-[#8E8E93]">Questions</p>
          </div>
          <div>
            <p class="text-2xl font-bold text-[#1C1C1E]">{@practice_test.total_points}</p>
            <p class="text-xs text-[#8E8E93]">Points</p>
          </div>
          <div>
            <p class="text-2xl font-bold text-[#1C1C1E]">
              {if @practice_test.time_limit,
                do: "#{@practice_test.time_limit} min",
                else: "None"}
            </p>
            <p class="text-xs text-[#8E8E93]">Time Limit</p>
          </div>
        </div>
        <div class="space-y-2">
          <div
            :for={section <- @practice_test.sections}
            class="flex items-center justify-between p-3 bg-[#F5F5F7] rounded-xl"
          >
            <div>
              <p class="font-medium text-[#1C1C1E] text-sm">{section["name"]}</p>
              <p class="text-xs text-[#8E8E93]">{format_question_type(section["question_type"])}</p>
            </div>
            <div class="text-right">
              <p class="font-medium text-[#1C1C1E] text-sm">
                {section["actual_count"]}/{section["target_count"]}
              </p>
              <p class="text-xs text-[#8E8E93]">available</p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp format_question_type(type) do
    type
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
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
end
