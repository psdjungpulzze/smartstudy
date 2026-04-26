defmodule FunSheepWeb.AdminTestCourseBuilderLive do
  @moduledoc """
  Admin hub for premium catalog / standardized-test courses.

  Shows all courses where `is_premium_catalog == true`, grouped by
  `catalog_test_type`, and allows admins to:
    - Trigger question generation (ProcessCourseWorker)
    - Publish / unpublish a course
    - Create new courses from a JSON spec (via CourseBuilder)
  """

  use FunSheepWeb, :live_view

  alias FunSheep.{Courses, Questions, Repo}
  alias FunSheep.Courses.CourseBuilder

  import Ecto.Query

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Course Builder · Admin")
      |> assign(:spec_json, "")
      |> assign(:spec_preview, nil)
      |> assign(:spec_error, nil)
      |> assign(:create_result, nil)
      |> assign(:creating, false)
      |> assign(:subscribed_course_ids, MapSet.new())
      |> load_courses()

    # Subscribe to PubSub for any currently-processing courses so progress
    # updates arrive in real time without polling.
    socket = subscribe_processing_courses(socket)

    {:ok, socket}
  end

  # --- Event Handlers -------------------------------------------------------

  @impl true
  def handle_event("generate_questions", %{"course_id" => course_id}, socket) do
    course = Courses.get_course!(course_id)

    case FunSheep.Workers.ProcessCourseWorker.new(%{course_id: course_id}) |> Oban.insert() do
      {:ok, _job} ->
        socket = subscribe_course(socket, course_id)

        {:noreply,
         socket
         |> put_flash(:info, "Question generation enqueued for \"#{course.name}\".")
         |> load_courses()}

      {:error, err} ->
        Logger.error("[CourseBuilder] Failed to enqueue ProcessCourseWorker: #{inspect(err)}")

        {:noreply, put_flash(socket, :error, "Failed to enqueue generation job.")}
    end
  end

  def handle_info({:processing_update, _update}, socket) do
    {:noreply, load_courses(socket)}
  end

  def handle_event("publish_course", %{"course_id" => course_id}, socket) do
    course = Courses.get_course!(course_id)

    case Courses.update_course(course, %{published_at: DateTime.utc_now() |> DateTime.truncate(:second)}) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "\"#{course.name}\" is now published.")
         |> load_courses()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to publish course.")}
    end
  end

  def handle_event("unpublish_course", %{"course_id" => course_id}, socket) do
    course = Courses.get_course!(course_id)

    case Courses.update_course(course, %{published_at: nil}) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "\"#{course.name}\" unpublished.")
         |> load_courses()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to unpublish course.")}
    end
  end

  def handle_event("update_spec", %{"spec_json" => json}, socket) do
    {:noreply, assign(socket, :spec_json, json)}
  end

  def handle_event("preview_spec", %{"spec_json" => json}, socket) do
    case CourseBuilder.parse_spec(json) do
      {:ok, spec} ->
        preview = CourseBuilder.preview_spec(spec)

        {:noreply,
         socket
         |> assign(:spec_json, json)
         |> assign(:spec_preview, preview)
         |> assign(:spec_error, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:spec_json, json)
         |> assign(:spec_preview, nil)
         |> assign(:spec_error, reason)}
    end
  end

  def handle_event("create_from_spec", %{"spec_json" => json}, socket) do
    case CourseBuilder.parse_spec(json) do
      {:ok, spec} ->
        socket = assign(socket, :creating, true)

        case CourseBuilder.create_from_spec(spec) do
          {:ok, result} ->
            {:noreply,
             socket
             |> assign(:creating, false)
             |> assign(:create_result, {:ok, result})
             |> assign(:spec_json, "")
             |> assign(:spec_preview, nil)
             |> assign(:spec_error, nil)
             |> put_flash(:info, "Course \"#{result.course.name}\" created successfully.")
             |> load_courses()}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:creating, false)
             |> assign(:create_result, {:error, inspect(reason)})
             |> assign(:spec_error, "Creation failed: #{inspect(reason)}")}
        end

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:spec_error, reason)
         |> assign(:spec_preview, nil)}
    end
  end

  # --- PubSub subscriptions -------------------------------------------------

  defp subscribe_processing_courses(socket) do
    socket.assigns.courses
    |> Enum.filter(&(&1.processing_status == "processing"))
    |> Enum.reduce(socket, fn course, acc -> subscribe_course(acc, course.id) end)
  end

  defp subscribe_course(socket, course_id) do
    if MapSet.member?(socket.assigns.subscribed_course_ids, course_id) do
      socket
    else
      Phoenix.PubSub.subscribe(FunSheep.PubSub, "course:#{course_id}")
      assign(socket, :subscribed_course_ids, MapSet.put(socket.assigns.subscribed_course_ids, course_id))
    end
  end

  # --- Data Loading ---------------------------------------------------------

  defp load_courses(socket) do
    courses =
      from(c in FunSheep.Courses.Course,
        where: c.is_premium_catalog == true,
        order_by: [asc: c.catalog_test_type, asc: c.name]
      )
      |> Repo.all()

    question_counts = build_question_counts(courses)
    coverage_counts = count_section_coverage(Enum.map(courses, & &1.id))

    grouped =
      courses
      |> Enum.group_by(& &1.catalog_test_type)
      |> Enum.sort_by(fn {type, _} -> type end)

    socket
    |> assign(:courses, courses)
    |> assign(:grouped_courses, grouped)
    |> assign(:question_counts, question_counts)
    |> assign(:coverage_counts, coverage_counts)
  end

  defp build_question_counts(courses) do
    Enum.reduce(courses, %{}, fn course, acc ->
      Map.put(acc, course.id, Questions.count_questions_by_course(course.id))
    end)
  end

  # Returns a map of %{course_id => {questions_with_section, total_questions}}
  defp count_section_coverage(course_ids) do
    Enum.reduce(course_ids, %{}, fn course_id, acc ->
      total =
        from(q in FunSheep.Questions.Question,
          where: q.course_id == ^course_id,
          select: count(q.id)
        )
        |> Repo.one() || 0

      with_section =
        from(q in FunSheep.Questions.Question,
          where: q.course_id == ^course_id and not is_nil(q.section_id),
          select: count(q.id)
        )
        |> Repo.one() || 0

      Map.put(acc, course_id, {with_section, total})
    end)
  end

  # --- Render ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-[#1C1C1E] dark:text-white">Course Builder</h1>
        <span class="text-sm text-[#8E8E93]">{length(@courses)} courses</span>
      </div>

      <%!-- Grouped course list --%>
      <div class="space-y-8 mb-10">
        <div :for={{test_type, courses} <- @grouped_courses}>
          <div class="flex items-center gap-3 mb-3">
            <span class="text-xs font-bold uppercase tracking-widest text-[#8E8E93]">
              {String.upcase(test_type || "Unknown")}
            </span>
            <div class="flex-1 border-t border-[#E5E5EA] dark:border-[#3A3A3C]"></div>
          </div>

          <div class="bg-white dark:bg-[#2D2D2D] rounded-2xl shadow-md overflow-hidden">
            <div class="overflow-x-auto">
              <table class="w-full text-sm min-w-[900px]">
                <thead class="bg-[#F5F5F7] dark:bg-[#1C1C1E] text-[#8E8E93] uppercase text-xs">
                  <tr>
                    <th class="text-left px-4 py-3 whitespace-nowrap">Course</th>
                    <th class="text-left px-4 py-3 whitespace-nowrap">Status</th>
                    <th class="text-right px-4 py-3 whitespace-nowrap">Questions</th>
                    <th class="text-right px-4 py-3 whitespace-nowrap">Coverage</th>
                    <th class="text-right px-4 py-3 whitespace-nowrap">Price</th>
                    <th class="text-left px-4 py-3 whitespace-nowrap">Published</th>
                    <th class="text-right px-4 py-3 whitespace-nowrap">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={course <- courses} class="border-t border-[#F5F5F7] dark:border-[#3A3A3C]">
                    <td class="px-4 py-3">
                      <div class="font-medium text-[#1C1C1E] dark:text-white">{course.name}</div>
                      <div class="text-xs text-[#8E8E93]">{course.catalog_subject || course.subject}</div>
                    </td>
                    <td class="px-4 py-3">
                      <.status_badge status={course.processing_status} />
                      <div
                        :if={course.processing_status == "processing" and not is_nil(course.processing_step)}
                        class="text-xs text-[#8E8E93] mt-1 max-w-[220px] truncate"
                        title={course.processing_step}
                      >
                        {course.processing_step}
                      </div>
                    </td>
                    <td class="px-4 py-3 text-right text-[#1C1C1E] dark:text-white font-mono">
                      {Map.get(@question_counts, course.id, 0)}
                    </td>
                    <td class="px-4 py-3 text-right">
                      <.coverage_badge coverage={Map.get(@coverage_counts, course.id, {0, 0})} />
                    </td>
                    <td class="px-4 py-3 text-right text-[#1C1C1E] dark:text-[#EBEBF5]">
                      {format_price(course.price_cents, course.currency)}
                    </td>
                    <td class="px-4 py-3 text-[#8E8E93] text-xs">
                      <%= if course.published_at do %>
                        <span class="text-[#4CD964] font-medium">
                          Live · {Calendar.strftime(course.published_at, "%b %d %Y")}
                        </span>
                      <% else %>
                        <span class="text-[#8E8E93]">Not published</span>
                      <% end %>
                    </td>
                    <td class="px-4 py-3 text-right">
                      <div class="flex items-center justify-end gap-2">
                        <%!-- Generate Questions --%>
                        <button
                          :if={course.processing_status in ["pending", "ready", "failed"]}
                          phx-click="generate_questions"
                          phx-value-course_id={course.id}
                          data-confirm={"Re-run question generation for \"#{course.name}\"?"}
                          class="px-3 py-1 text-xs bg-[#007AFF] hover:bg-[#0062CC] text-white rounded-full font-medium transition-colors"
                        >
                          Generate
                        </button>

                        <%!-- Publish --%>
                        <button
                          :if={course.processing_status == "ready" and is_nil(course.published_at)}
                          phx-click="publish_course"
                          phx-value-course_id={course.id}
                          data-confirm={"Publish \"#{course.name}\"? Students will be able to purchase it."}
                          class="px-3 py-1 text-xs bg-[#4CD964] hover:bg-[#3DBF55] text-white rounded-full font-medium transition-colors"
                        >
                          Publish
                        </button>

                        <%!-- Unpublish --%>
                        <button
                          :if={not is_nil(course.published_at)}
                          phx-click="unpublish_course"
                          phx-value-course_id={course.id}
                          data-confirm={"Unpublish \"#{course.name}\"? Students won't see it until republished."}
                          class="px-3 py-1 text-xs bg-[#FF9500] hover:bg-[#E08700] text-white rounded-full font-medium transition-colors"
                        >
                          Unpublish
                        </button>

                        <%!-- View --%>
                        <a
                          href={"/courses/#{course.id}"}
                          target="_blank"
                          class="px-3 py-1 text-xs bg-[#F5F5F7] dark:bg-[#3A3A3C] hover:bg-[#E5E5EA] text-[#1C1C1E] dark:text-white rounded-full font-medium transition-colors"
                        >
                          View
                        </a>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <div :if={@grouped_courses == []} class="bg-white dark:bg-[#2D2D2D] rounded-2xl shadow-md p-8 text-center text-[#8E8E93]">
          No premium catalog courses yet. Create one below.
        </div>
      </div>

      <%!-- Create New Test Course panel --%>
      <div class="bg-white dark:bg-[#2D2D2D] rounded-2xl shadow-md p-6">
        <h2 class="text-lg font-semibold text-[#1C1C1E] dark:text-white mb-4">
          Create New Test Course
        </h2>
        <p class="text-sm text-[#8E8E93] mb-4">
          Paste a JSON spec below. See <code class="bg-[#F5F5F7] dark:bg-[#1C1C1E] px-1 rounded">.claude/commands/course-create.md</code> for the spec format.
        </p>

        <form phx-submit="create_from_spec" phx-change="update_spec" class="space-y-4">
          <textarea
            name="spec_json"
            rows="12"
            placeholder={"{\n  \"name\": \"ACT Math\",\n  \"test_type\": \"act\",\n  \"subject\": \"mathematics\",\n  \"grades\": [\"10\", \"11\", \"12\", \"College\"],\n  ...\n}"}
            class="w-full px-4 py-3 bg-[#F5F5F7] dark:bg-[#1C1C1E] border border-transparent focus:border-[#4CD964] focus:bg-white dark:focus:bg-[#2D2D2D] rounded-2xl outline-none transition-colors font-mono text-sm text-[#1C1C1E] dark:text-white resize-y"
            phx-debounce="500"
          >{@spec_json}</textarea>

          <%!-- Error message --%>
          <div :if={@spec_error} class="text-sm text-[#FF3B30] bg-[#FFF2F1] dark:bg-[#3A1515] px-4 py-3 rounded-xl">
            {@spec_error}
          </div>

          <%!-- Preview --%>
          <div :if={@spec_preview} class="bg-[#F0FFF4] dark:bg-[#1A2E1A] border border-[#4CD964] rounded-xl px-4 py-3 text-sm">
            <div class="font-semibold text-[#1C1C1E] dark:text-white mb-2">Preview</div>
            <div class="space-y-1 text-[#3C3C43] dark:text-[#EBEBF5]">
              <div><span class="text-[#8E8E93]">Name:</span> {@spec_preview.name}</div>
              <div><span class="text-[#8E8E93]">Test type:</span> {@spec_preview.test_type}</div>
              <div>
                <span class="text-[#8E8E93]">Chapters:</span>
                {@spec_preview.chapter_count} ({@spec_preview.total_sections} sections total)
              </div>
              <div :if={@spec_preview.has_exam_simulation}>
                <span class="text-[#8E8E93]">Exam template:</span> Yes
              </div>
              <div :if={@spec_preview.has_textbook}>
                <span class="text-[#8E8E93]">Textbook:</span> {@spec_preview.textbook_title}
              </div>
              <div :if={@spec_preview.has_bundle}>
                <span class="text-[#8E8E93]">Bundle:</span> Yes
              </div>
              <div :if={@spec_preview.price_cents}>
                <span class="text-[#8E8E93]">Price:</span>
                ${div(@spec_preview.price_cents, 100)}
              </div>
            </div>
            <details class="mt-2 text-xs text-[#8E8E93]">
              <summary class="cursor-pointer hover:text-[#1C1C1E] dark:hover:text-white">
                Chapter breakdown
              </summary>
              <ul class="mt-1 list-disc list-inside space-y-0.5">
                <li :for={ch <- @spec_preview.chapters}>
                  {ch.name} — {ch.section_count} sections
                </li>
              </ul>
            </details>
          </div>

          <div class="flex gap-3">
            <button
              type="button"
              phx-click="preview_spec"
              phx-value-spec_json={@spec_json}
              class="px-5 py-2 bg-[#F5F5F7] dark:bg-[#3A3A3C] hover:bg-[#E5E5EA] text-[#1C1C1E] dark:text-white rounded-full font-medium text-sm transition-colors"
            >
              Validate & Preview
            </button>

            <button
              type="submit"
              disabled={@creating or @spec_json == ""}
              class="px-5 py-2 bg-[#4CD964] hover:bg-[#3DBF55] disabled:opacity-50 disabled:cursor-not-allowed text-white rounded-full font-medium text-sm transition-colors"
            >
              <%= if @creating do %>
                Creating…
              <% else %>
                Create Course
              <% end %>
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  # --- Sub-components -------------------------------------------------------

  defp status_badge(assigns) do
    {bg, text} =
      case assigns.status do
        "pending" -> {"bg-[#F5F5F7] dark:bg-[#3A3A3C]", "text-[#8E8E93]"}
        "processing" -> {"bg-[#FFF9E6]", "text-[#FFCC00]"}
        "validating" -> {"bg-[#E8F4FD]", "text-[#007AFF]"}
        "ready" -> {"bg-[#F0FFF4]", "text-[#4CD964]"}
        "failed" -> {"bg-[#FFF2F1]", "text-[#FF3B30]"}
        "cancelled" -> {"bg-[#F5F5F7] dark:bg-[#3A3A3C]", "text-[#8E8E93]"}
        _ -> {"bg-[#F5F5F7] dark:bg-[#3A3A3C]", "text-[#8E8E93]"}
      end

    assigns = assign(assigns, :bg, bg) |> assign(:text, text)

    ~H"""
    <span class={"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium #{@bg} #{@text}"}>
      {@status}
    </span>
    """
  end

  defp coverage_badge(assigns) do
    {with_section, total} = assigns.coverage

    pct =
      if total > 0 do
        round(with_section / total * 100)
      else
        0
      end

    color =
      cond do
        pct >= 80 -> "text-[#4CD964]"
        pct >= 40 -> "text-[#FF9500]"
        true -> "text-[#FF3B30]"
      end

    assigns = assign(assigns, :pct, pct) |> assign(:color, color) |> assign(:total, total)

    ~H"""
    <span class={"font-mono text-xs #{@color}"}>
      <%= if @total == 0 do %>
        —
      <% else %>
        {@pct}%
      <% end %>
    </span>
    """
  end

  defp format_price(nil, _), do: "—"

  defp format_price(cents, currency) do
    dollars = div(cents, 100)
    cents_part = rem(cents, 100) |> to_string() |> String.pad_leading(2, "0")
    "$#{dollars}.#{cents_part} #{String.upcase(currency || "USD")}"
  end
end
