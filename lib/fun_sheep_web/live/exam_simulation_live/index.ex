defmodule FunSheepWeb.ExamSimulationLive.Index do
  use FunSheepWeb, :live_view

  alias FunSheep.{Assessments, Billing, Courses, Questions}
  alias FunSheep.Assessments.{ExamSimulationEngine, ExamSimulations}

  @min_bank_size 10

  @impl true
  def mount(%{"course_id" => course_id}, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    role = socket.assigns.current_user["role"]
    course = Courses.get_course!(course_id)

    billing_ok = Billing.check_test_allowance(user_role_id, role) == :ok

    schedule = Assessments.primary_test(user_role_id)
    # Only use the schedule if it belongs to this course
    schedule =
      if schedule && schedule.course_id == course_id, do: schedule, else: nil

    format_template_id = schedule && schedule.format_template_id

    chapter_ids = chapter_ids_from_schedule(schedule)
    bank_size = Questions.count_for_exam(course_id, chapter_ids)
    bank_too_small = bank_size < @min_bank_size

    format_preview = build_format_preview(format_template_id)

    active_session = ExamSimulations.get_active_session(user_role_id, course_id)

    active_remaining_seconds =
      if active_session do
        elapsed = DateTime.diff(DateTime.utc_now(), active_session.started_at, :second)
        max(0, active_session.time_limit_seconds - elapsed)
      end

    {:ok,
     assign(socket,
       page_title: "Exam Simulation — #{course.name}",
       course: course,
       course_id: course_id,
       billing_ok: billing_ok,
       schedule: schedule,
       format_template_id: format_template_id,
       chapter_ids: chapter_ids,
       bank_size: bank_size,
       bank_too_small: bank_too_small,
       min_bank_size: @min_bank_size,
       format_preview: format_preview,
       active_session: active_session,
       active_remaining_seconds: active_remaining_seconds,
       starting: false,
       error: nil
     )}
  end

  @impl true
  def handle_event("start_exam", _params, socket) do
    socket = assign(socket, starting: true, error: nil)
    user_role_id = socket.assigns.current_user["user_role_id"]

    opts =
      [chapter_ids: socket.assigns.chapter_ids]
      |> then(fn o ->
        if socket.assigns.schedule,
          do: Keyword.put(o, :schedule_id, socket.assigns.schedule.id),
          else: o
      end)
      |> then(fn o ->
        if socket.assigns.format_template_id,
          do: Keyword.put(o, :format_template_id, socket.assigns.format_template_id),
          else: o
      end)

    case ExamSimulationEngine.build_session(user_role_id, socket.assigns.course_id, opts) do
      {:ok, _state} ->
        {:noreply,
         push_navigate(socket, to: ~p"/courses/#{socket.assigns.course_id}/exam-simulation/exam")}

      {:error, :insufficient_questions} ->
        {:noreply,
         assign(socket,
           starting: false,
           error:
             "Not enough questions in your question bank yet. Keep practicing to build it up!"
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket, starting: false, error: "Could not start exam: #{inspect(reason)}")}
    end
  end

  def handle_event("resume_exam", _params, socket) do
    {:noreply,
     push_navigate(socket, to: ~p"/courses/#{socket.assigns.course_id}/exam-simulation/exam")}
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp chapter_ids_from_schedule(nil), do: []

  defp chapter_ids_from_schedule(schedule) do
    get_in(schedule.scope, ["chapter_ids"]) || []
  end

  defp build_format_preview(nil) do
    [%{name: "General", count: 40, time_minutes: 45}]
  end

  defp build_format_preview(format_template_id) do
    template = FunSheep.Repo.get(FunSheep.Assessments.TestFormatTemplate, format_template_id)

    if template && is_map(template.structure) do
      sections = Map.get(template.structure, "sections", [])

      if sections != [] do
        Enum.map(sections, fn sec ->
          %{
            name: Map.get(sec, "name", "Section"),
            count: Map.get(sec, "count", 10),
            time_minutes: div(Map.get(sec, "time_seconds", 600), 60)
          }
        end)
      else
        [%{name: "General", count: 40, time_minutes: 45}]
      end
    else
      [%{name: "General", count: 40, time_minutes: 45}]
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-8 px-4">
      <div class="mb-6">
        <a href={~p"/courses/#{@course_id}"} class="text-sm text-gray-500 hover:text-gray-700">
          &larr; <%= @course.name %>
        </a>
      </div>

      <%= if not @billing_ok do %>
        <div class="rounded-2xl bg-white shadow-md p-4 sm:p-8 text-center">
          <div class="text-4xl mb-4">🔒</div>
          <h2 class="text-xl font-semibold mb-2">Exam Simulation is a Premium Feature</h2>
          <p class="text-gray-600 mb-6">
            Upgrade your plan to access full exam simulations with time tracking and pacing analysis.
          </p>
          <a
            href={~p"/subscription"}
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md inline-block"
          >
            Upgrade Now
          </a>
        </div>
      <% else %>
        <%= if @active_session && @active_remaining_seconds && @active_remaining_seconds > 0 do %>
          <div class="rounded-2xl bg-amber-50 border border-amber-200 p-4 mb-6 flex items-center justify-between">
            <div>
              <p class="font-medium text-amber-800">You have an exam in progress</p>
              <p class="text-sm text-amber-600">
                <%= format_duration(@active_remaining_seconds) %> remaining
              </p>
            </div>
            <button
              phx-click="resume_exam"
              class="bg-amber-500 hover:bg-amber-600 text-white font-medium px-4 py-2 rounded-full text-sm"
            >
              Resume Exam
            </button>
          </div>
        <% end %>

        <div class="rounded-2xl bg-white shadow-md overflow-hidden">
          <div class="bg-slate-800 text-white px-4 py-4 sm:px-8 sm:py-6">
            <h1 class="text-xl sm:text-2xl font-bold">Full Exam Simulation</h1>
            <p class="text-slate-300 mt-1 text-sm sm:text-base">
              Experience the real test. Timed. No hints. No feedback until you submit.
            </p>
          </div>

          <div class="p-4 sm:p-8">
            <%= if @bank_too_small do %>
              <div class="rounded-lg bg-amber-50 border border-amber-200 p-4 mb-6">
                <p class="text-amber-800 text-sm">
                  ⚠️ Your question bank only has <%= @bank_size %> question(s). Keep practicing to build it up — we recommend at least <%= @min_bank_size %> questions for a meaningful simulation.
                </p>
              </div>
            <% end %>

            <h3 class="font-semibold text-gray-700 mb-3">Exam Structure</h3>
            <div class="border rounded-lg overflow-hidden mb-6">
              <table class="w-full text-sm">
                <thead class="bg-gray-50">
                  <tr>
                    <th class="px-4 py-2 text-left text-gray-600">Section</th>
                    <th class="px-4 py-2 text-right text-gray-600">Questions</th>
                    <th class="px-4 py-2 text-right text-gray-600">Time</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for section <- @format_preview do %>
                    <tr class="border-t">
                      <td class="px-4 py-2"><%= section.name %></td>
                      <td class="px-4 py-2 text-right"><%= section.count %></td>
                      <td class="px-4 py-2 text-right"><%= section.time_minutes %> min</td>
                    </tr>
                  <% end %>
                  <tr class="border-t bg-gray-50 font-medium">
                    <td class="px-4 py-2">Total</td>
                    <td class="px-4 py-2 text-right">
                      <%= Enum.sum(Enum.map(@format_preview, & &1.count)) %>
                    </td>
                    <td class="px-4 py-2 text-right">
                      <%= Enum.sum(Enum.map(@format_preview, & &1.time_minutes)) %> min
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="rounded-lg bg-slate-50 p-4 mb-6 text-sm text-slate-600">
              <p>
                ✓ You will <strong>not</strong>
                see whether your answers are correct until you submit.
              </p>
              <p class="mt-1">✓ The timer cannot be paused. Submit before time runs out.</p>
              <p class="mt-1">
                ✓ You can flag questions and return to them before submitting.
              </p>
            </div>

            <%= if @error do %>
              <div class="rounded-lg bg-red-50 border border-red-200 p-3 mb-4 text-red-700 text-sm">
                <%= @error %>
              </div>
            <% end %>

            <button
              phx-click="start_exam"
              disabled={@bank_too_small || @starting}
              class={[
                "w-full sm:w-auto sm:min-w-[200px] sm:block sm:mx-auto py-3 px-8 rounded-full font-semibold text-white shadow-md transition-colors",
                if(@bank_too_small || @starting,
                  do: "bg-gray-300 cursor-not-allowed",
                  else: "bg-[#4CD964] hover:bg-[#3DBF55]"
                )
              ]}
            >
              <%= if @starting, do: "Starting...", else: "Start Exam Simulation" %>
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_duration(seconds) do
    m = div(seconds, 60)
    s = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B", [m, s]) |> to_string()
  end
end
