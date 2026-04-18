defmodule StudySmartWeb.TestFormatLive do
  use StudySmartWeb, :live_view

  alias StudySmart.{Assessments, Courses}
  alias StudySmart.Assessments.FormatReplicator

  @question_types ~w(multiple_choice short_answer free_response true_false)

  @impl true
  def mount(%{"schedule_id" => schedule_id}, _session, socket) do
    schedule = Assessments.get_test_schedule_with_course!(schedule_id)
    user_role_id = socket.assigns.current_user["user_role_id"]
    course = Courses.get_course_with_chapters!(schedule.course_id)

    {:ok,
     assign(socket,
       page_title: "Test Format: #{schedule.name}",
       schedule: schedule,
       course: course,
       user_role_id: user_role_id,
       sections: [],
       new_section_name: "",
       new_section_type: "multiple_choice",
       new_section_count: 10,
       new_section_points: 1,
       time_limit: nil,
       saved_template: nil,
       practice_test: nil,
       question_types: @question_types
     )}
  end

  @impl true
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
    sections = List.delete_at(socket.assigns.sections, index)
    {:noreply, assign(socket, sections: sections)}
  end

  def handle_event("save_template", _params, socket) do
    structure = %{
      "sections" => socket.assigns.sections,
      "time_limit_minutes" => socket.assigns.time_limit
    }

    template_name = "#{socket.assigns.schedule.name} Format"

    case Assessments.create_test_format_template(%{
           name: template_name,
           structure: structure,
           course_id: socket.assigns.schedule.course_id,
           created_by_id: socket.assigns.user_role_id
         }) do
      {:ok, template} ->
        # Link template to the test schedule
        Assessments.update_test_schedule(socket.assigns.schedule, %{
          format_template_id: template.id
        })

        {:noreply,
         socket
         |> assign(saved_template: template)
         |> put_flash(:info, "Test format template saved!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save template")}
    end
  end

  def handle_event("generate_practice_test", _params, socket) do
    template = socket.assigns.saved_template

    if template do
      practice_test =
        FormatReplicator.generate_practice_test(
          template.id,
          socket.assigns.schedule.course_id,
          socket.assigns.user_role_id
        )

      {:noreply, assign(socket, practice_test: practice_test)}
    else
      {:noreply, put_flash(socket, :error, "Save a template first")}
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <div class="flex items-center gap-4 mb-8">
        <.link
          navigate={~p"/tests"}
          class="text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
        >
          <.icon name="hero-arrow-left" class="w-6 h-6" />
        </.link>
        <div>
          <h1 class="text-2xl font-bold text-[#1C1C1E]">Test Format</h1>
          <p class="text-sm text-[#8E8E93]">{@schedule.name} - {@schedule.course.name}</p>
        </div>
      </div>

      <%!-- Section Builder --%>
      <div class="bg-white rounded-2xl shadow-md p-8 mb-6">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-4">Define Test Sections</h2>

        <%!-- Existing sections --%>
        <div :if={@sections != []} class="space-y-3 mb-6">
          <div
            :for={{section, index} <- Enum.with_index(@sections)}
            class="flex items-center justify-between p-4 bg-[#F5F5F7] rounded-xl"
          >
            <div>
              <p class="font-medium text-[#1C1C1E]">{section["name"]}</p>
              <p class="text-sm text-[#8E8E93]">
                {format_question_type(section["question_type"])} | {section["count"]} questions | {section[
                  "points_per_question"
                ]} pts each
              </p>
            </div>
            <button
              phx-click="remove_section"
              phx-value-index={index}
              class="text-[#FF3B30] hover:text-red-700 p-2 rounded-lg transition-colors"
            >
              <.icon name="hero-trash" class="w-5 h-5" />
            </button>
          </div>
        </div>

        <%!-- Add section form --%>
        <form phx-change="update_section_form" phx-submit="add_section" class="space-y-4">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-[#1C1C1E] mb-1">Section Name</label>
              <input
                type="text"
                name="name"
                value={@new_section_name}
                placeholder="e.g., Multiple Choice"
                class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-[#1C1C1E] mb-1">Question Type</label>
              <select
                name="question_type"
                class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors"
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
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-[#1C1C1E] mb-1">Number of Questions</label>
              <input
                type="number"
                name="count"
                value={@new_section_count}
                min="1"
                class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-[#1C1C1E] mb-1">Points per Question</label>
              <input
                type="number"
                name="points_per_question"
                value={@new_section_points}
                min="1"
                class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors"
              />
            </div>
          </div>
          <button
            type="submit"
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Add Section
          </button>
        </form>
      </div>

      <%!-- Time Limit --%>
      <div class="bg-white rounded-2xl shadow-md p-8 mb-6">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-4">Time Limit</h2>
        <form phx-change="update_time_limit">
          <div class="flex items-center gap-4">
            <input
              type="number"
              name="time_limit"
              value={@time_limit}
              placeholder="No limit"
              min="1"
              class="w-48 px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors"
            />
            <span class="text-[#8E8E93]">minutes</span>
          </div>
        </form>
      </div>

      <%!-- Actions --%>
      <div class="flex items-center gap-4 mb-6">
        <button
          :if={@sections != []}
          phx-click="save_template"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
        >
          Save Template
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
          navigate={~p"/tests/#{@schedule.id}/format-test"}
          class="px-6 py-2 border border-[#E5E5EA] text-[#1C1C1E] font-medium rounded-full hover:bg-[#F5F5F7] transition-colors"
        >
          Take Practice Test
        </.link>
      </div>

      <%!-- Practice Test Preview --%>
      <div :if={@practice_test} class="bg-white rounded-2xl shadow-md p-8">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-4">Practice Test Preview</h2>

        <div class="bg-[#F5F5F7] rounded-xl p-4 mb-4">
          <div class="grid grid-cols-3 gap-4 text-center">
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
                {if @practice_test.time_limit, do: "#{@practice_test.time_limit} min", else: "None"}
              </p>
              <p class="text-xs text-[#8E8E93]">Time Limit</p>
            </div>
          </div>
        </div>

        <div class="space-y-3">
          <div
            :for={section <- @practice_test.sections}
            class="flex items-center justify-between p-3 bg-[#F5F5F7] rounded-xl"
          >
            <div>
              <p class="font-medium text-[#1C1C1E]">{section["name"]}</p>
              <p class="text-sm text-[#8E8E93]">{format_question_type(section["question_type"])}</p>
            </div>
            <div class="text-right">
              <p class="font-medium text-[#1C1C1E]">
                {section["actual_count"]}/{section["target_count"]}
              </p>
              <p class="text-xs text-[#8E8E93]">questions available</p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
