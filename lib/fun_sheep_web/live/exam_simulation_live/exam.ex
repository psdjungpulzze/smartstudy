defmodule FunSheepWeb.ExamSimulationLive.Exam do
  use FunSheepWeb, :live_view

  alias FunSheep.{Billing, Courses}
  alias FunSheep.Assessments.{ExamSimulationEngine, ExamSimulations}

  @tick_interval_ms 1_000

  @impl true
  def mount(%{"course_id" => course_id}, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    role = socket.assigns.current_user["role"]
    course = Courses.get_course!(course_id)

    if Billing.check_test_allowance(user_role_id, role) != :ok do
      {:ok, push_navigate(socket, to: ~p"/courses/#{course_id}/exam-simulation")}
    else
      case load_state(user_role_id, course_id) do
        nil ->
          {:ok, push_navigate(socket, to: ~p"/courses/#{course_id}/exam-simulation")}

        state ->
          remaining = ExamSimulationEngine.remaining_seconds(state)

          if remaining <= 0 do
            ExamSimulationEngine.timeout(state)
            {:ok, push_navigate(socket, to: ~p"/courses/#{course_id}/exam-simulation")}
          else
            if connected?(socket), do: schedule_tick()

            {section_idx, question_idx} = first_unanswered_position(state)

            {:ok,
             assign(socket,
               page_title: "Exam — #{course.name}",
               course: course,
               course_id: course_id,
               engine_state: state,
               current_section_index: section_idx,
               current_question_index: question_idx,
               remaining_seconds: remaining,
               timer_urgency: urgency(remaining, state.time_limit_seconds),
               show_overview: false,
               submit_modal_open: false,
               unanswered_count: ExamSimulationEngine.unanswered_count(state),
               question_entered_at: System.monotonic_time(:millisecond)
             )}
          end
      end
    end
  end

  @impl true
  def handle_info(:tick, socket) do
    state = socket.assigns.engine_state
    remaining = ExamSimulationEngine.remaining_seconds(state)

    if remaining <= 0 do
      ExamSimulationEngine.timeout(state)

      {:noreply,
       push_navigate(socket, to: ~p"/courses/#{socket.assigns.course_id}/exam-simulation")}
    else
      schedule_tick()

      {:noreply,
       assign(socket,
         remaining_seconds: remaining,
         timer_urgency: urgency(remaining, state.time_limit_seconds)
       )}
    end
  end

  @impl true
  def handle_event("answer", %{"question_id" => qid, "answer" => answer}, socket) do
    time_spent = time_spent_seconds(socket.assigns.question_entered_at)
    state = ExamSimulationEngine.record_answer(socket.assigns.engine_state, qid, answer, time_spent)

    {:noreply,
     socket
     |> assign(
       engine_state: state,
       question_entered_at: System.monotonic_time(:millisecond),
       unanswered_count: ExamSimulationEngine.unanswered_count(state)
     )
     |> advance_question()}
  end

  def handle_event("flag", %{"question_id" => qid}, socket) do
    current_flagged = get_in(socket.assigns.engine_state.answers, [qid, "flagged"]) || false
    state = ExamSimulationEngine.flag_question(socket.assigns.engine_state, qid, !current_flagged)
    {:noreply, assign(socket, engine_state: state)}
  end

  def handle_event("navigate", %{"section" => si, "question" => qi}, socket) do
    {:noreply,
     assign(socket,
       current_section_index: String.to_integer(si),
       current_question_index: String.to_integer(qi),
       question_entered_at: System.monotonic_time(:millisecond)
     )}
  end

  def handle_event("prev", _params, socket) do
    {:noreply, move_question(socket, -1)}
  end

  def handle_event("next", _params, socket) do
    {:noreply, move_question(socket, 1)}
  end

  def handle_event("toggle_overview", _params, socket) do
    {:noreply, assign(socket, show_overview: !socket.assigns.show_overview)}
  end

  def handle_event("open_submit_modal", _params, socket) do
    count = ExamSimulationEngine.unanswered_count(socket.assigns.engine_state)
    {:noreply, assign(socket, submit_modal_open: true, unanswered_count: count)}
  end

  def handle_event("close_submit_modal", _params, socket) do
    {:noreply, assign(socket, submit_modal_open: false)}
  end

  def handle_event("confirm_submit", _params, socket) do
    case ExamSimulationEngine.submit(socket.assigns.engine_state) do
      {:ok, session} ->
        {:noreply,
         push_navigate(socket,
           to:
             ~p"/courses/#{socket.assigns.course_id}/exam-simulation/results/#{session.id}"
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not submit exam. Please try again.")}
    end
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp load_state(user_role_id, course_id) do
    case ExamSimulations.get_active_session(user_role_id, course_id) do
      nil ->
        nil

      active_session ->
        case ExamSimulationEngine.cache_get(user_role_id, active_session.id) do
          {:ok, state} ->
            state

          :miss ->
            questions = load_questions_for_session(active_session)
            state = build_state_from_session(active_session, questions)
            ExamSimulationEngine.cache_put(user_role_id, active_session.id, state)
            state
        end
    end
  end

  defp load_questions_for_session(session) do
    import Ecto.Query
    ids = session.question_ids_order || []

    if ids == [] do
      []
    else
      from(q in FunSheep.Questions.Question, where: q.id in ^ids)
      |> FunSheep.Repo.all()
      |> Enum.sort_by(&Enum.find_index(ids, fn id -> id == &1.id end))
    end
  end

  defp build_state_from_session(session, questions) do
    %{
      session_id: session.id,
      user_role_id: session.user_role_id,
      course_id: session.course_id,
      schedule_id: session.schedule_id,
      format_template_id: session.format_template_id,
      questions: questions,
      question_ids_order: session.question_ids_order || [],
      section_boundaries: session.section_boundaries || [],
      answers: session.answers || %{},
      time_limit_seconds: session.time_limit_seconds,
      started_at: session.started_at,
      status: :in_progress
    }
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_interval_ms)

  defp urgency(remaining, total) when total > 0 do
    pct = remaining / total

    cond do
      pct <= 0.10 -> :critical
      pct <= 0.20 -> :warning
      true -> :normal
    end
  end

  defp urgency(_, _), do: :normal

  defp time_spent_seconds(entered_at_ms) do
    now_ms = System.monotonic_time(:millisecond)
    max(0, div(now_ms - entered_at_ms, 1000))
  end

  defp advance_question(socket) do
    move_question(socket, 1)
  end

  defp move_question(socket, delta) do
    %{engine_state: state, current_section_index: si, current_question_index: qi} =
      socket.assigns

    sec_count = length(state.section_boundaries)
    sec = Enum.at(state.section_boundaries, si)
    q_count = if sec, do: sec["question_count"], else: 0
    new_qi = qi + delta

    cond do
      new_qi >= 0 && new_qi < q_count ->
        assign(socket,
          current_question_index: new_qi,
          question_entered_at: System.monotonic_time(:millisecond)
        )

      delta > 0 && si + 1 < sec_count ->
        assign(socket,
          current_section_index: si + 1,
          current_question_index: 0,
          question_entered_at: System.monotonic_time(:millisecond)
        )

      delta < 0 && si > 0 ->
        prev_sec = Enum.at(state.section_boundaries, si - 1)
        prev_count = if prev_sec, do: max(0, prev_sec["question_count"] - 1), else: 0

        assign(socket,
          current_section_index: si - 1,
          current_question_index: prev_count,
          question_entered_at: System.monotonic_time(:millisecond)
        )

      true ->
        socket
    end
  end

  defp first_unanswered_position(state) do
    answered_ids =
      state.answers
      |> Enum.filter(fn {_id, e} -> Map.get(e, "answer") not in [nil, ""] end)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

    first_unanswered = Enum.find_index(state.question_ids_order, &(&1 not in answered_ids))

    if first_unanswered do
      find_section_and_local_index(state, first_unanswered)
    else
      {0, 0}
    end
  end

  defp find_section_and_local_index(state, flat_index) do
    result =
      Enum.find_index(state.section_boundaries, fn sec ->
        flat_index >= sec["start_index"] &&
          flat_index < sec["start_index"] + sec["question_count"]
      end)

    case result do
      nil ->
        {0, 0}

      si ->
        sec = Enum.at(state.section_boundaries, si)
        local_qi = flat_index - sec["start_index"]
        {si, local_qi}
    end
  end

  # ── Template helpers ──────────────────────────────────────────────────────

  defp current_question(state, si, qi) do
    sec = Enum.at(state.section_boundaries, si)

    if sec do
      flat_index = sec["start_index"] + qi
      qid = Enum.at(state.question_ids_order, flat_index)
      Enum.find(state.questions, &(&1.id == qid))
    end
  end

  defp question_status(state, qid) do
    entry = Map.get(state.answers, qid, %{})
    answered = Map.get(entry, "answer") not in [nil, ""]
    flagged = Map.get(entry, "flagged", false)

    cond do
      flagged -> :flagged
      answered -> :answered
      true -> :unanswered
    end
  end

  defp selected_answer(state, qid) do
    get_in(state.answers, [qid, "answer"])
  end

  defp format_timer(seconds) when seconds >= 0 do
    m = div(seconds, 60)
    s = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B", [m, s]) |> to_string()
  end

  defp format_timer(_), do: "00:00"

  defp timer_class(:normal), do: "text-white"
  defp timer_class(:warning), do: "text-amber-300"
  defp timer_class(:critical), do: "text-red-400 font-bold animate-pulse"

  @impl true
  def render(assigns) do
    current_q = current_question(assigns.engine_state, assigns.current_section_index, assigns.current_question_index)
    assigns = assign(assigns, current_question: current_q)
    current_qid = current_q && current_q.id
    assigns = assign(assigns, current_qid: current_qid)

    ~H"""
    <div class="flex flex-col bg-slate-900 text-white" style="min-height: 100vh;">
      <!-- Header bar -->
      <div class="bg-slate-800 border-b border-slate-700 px-4 py-3 flex items-center gap-3 flex-shrink-0">
        <button
          phx-click="toggle_overview"
          class="text-slate-300 hover:text-white text-sm flex items-center gap-1"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-4 w-4"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            stroke-width="1.5"
          >
            <path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 12h16M4 18h16" />
          </svg>
          Overview
        </button>

        <div class="flex gap-2 overflow-x-auto flex-1">
          <%= for {sec, idx} <- Enum.with_index(@engine_state.section_boundaries) do %>
            <% ids = ExamSimulationEngine.question_ids_for_section(@engine_state, idx) %>
            <% answered = Enum.count(ids, fn id -> get_in(@engine_state.answers, [id, "answer"]) not in [nil, ""] end) %>
            <button
              phx-click="navigate"
              phx-value-section={idx}
              phx-value-question={0}
              class={[
                "px-3 py-1 rounded-full text-xs whitespace-nowrap transition-colors",
                if(@current_section_index == idx,
                  do: "bg-[#4CD964] text-white",
                  else: "bg-slate-700 text-slate-300 hover:bg-slate-600"
                )
              ]}
            >
              <%= sec["name"] %> (<%= answered %>/<%= sec["question_count"] %>)
            </button>
          <% end %>
        </div>

        <div class={["font-mono text-lg tabular-nums", timer_class(@timer_urgency)]}>
          ⏱ <%= format_timer(@remaining_seconds) %>
        </div>

        <button
          phx-click="open_submit_modal"
          class="bg-white text-slate-800 font-medium px-4 py-1.5 rounded-full text-sm hover:bg-slate-100"
        >
          Submit
        </button>
      </div>

      <div class="flex flex-1 overflow-hidden" style="min-height: calc(100vh - 64px);">
        <!-- Overview sidebar -->
        <%= if @show_overview do %>
          <div class="w-64 bg-slate-800 border-r border-slate-700 p-4 overflow-y-auto flex-shrink-0">
            <h3 class="text-sm font-semibold text-slate-400 mb-3">Question Overview</h3>
            <%= for {sec, si} <- Enum.with_index(@engine_state.section_boundaries) do %>
              <div class="mb-4">
                <p class="text-xs text-slate-400 mb-2"><%= sec["name"] %></p>
                <div class="flex flex-wrap gap-1">
                  <%= for qi <- 0..(sec["question_count"] - 1) do %>
                    <% flat_i = sec["start_index"] + qi %>
                    <% qid = Enum.at(@engine_state.question_ids_order, flat_i) %>
                    <% status = question_status(@engine_state, qid) %>
                    <button
                      phx-click="navigate"
                      phx-value-section={si}
                      phx-value-question={qi}
                      class={[
                        "w-7 h-7 rounded text-xs flex items-center justify-center",
                        case status do
                          :answered -> "bg-slate-500 text-white"
                          :flagged -> "bg-amber-500 text-white"
                          :unanswered -> "bg-slate-700 text-slate-400 hover:bg-slate-600"
                        end
                      ]}
                    >
                      <%= flat_i + 1 %>
                    </button>
                  <% end %>
                </div>
              </div>
            <% end %>
            <div class="mt-4 text-xs text-slate-400 space-y-1">
              <div class="flex items-center gap-2">
                <span class="w-3 h-3 rounded bg-slate-500 inline-block"></span> Answered
              </div>
              <div class="flex items-center gap-2">
                <span class="w-3 h-3 rounded bg-amber-500 inline-block"></span> Flagged
              </div>
              <div class="flex items-center gap-2">
                <span class="w-3 h-3 rounded bg-slate-700 inline-block"></span> Unanswered
              </div>
            </div>
          </div>
        <% end %>

        <!-- Main question area -->
        <div class="flex-1 overflow-y-auto p-6">
          <%= if @current_question do %>
            <div class="max-w-2xl mx-auto">
              <div class="flex items-center justify-between mb-4">
                <span class="text-slate-400 text-sm">
                  Question
                  <%= Enum.find_index(@engine_state.question_ids_order, &(&1 == @current_qid)) |> Kernel.+(1) %>
                  of <%= length(@engine_state.question_ids_order) %>
                </span>
                <button
                  phx-click="flag"
                  phx-value-question_id={@current_qid}
                  class={[
                    "text-sm flex items-center gap-1 px-3 py-1 rounded-full border transition-colors",
                    if(get_in(@engine_state.answers, [@current_qid, "flagged"]),
                      do: "border-amber-400 text-amber-400 bg-amber-400/10",
                      else:
                        "border-slate-600 text-slate-400 hover:border-amber-400 hover:text-amber-400"
                    )
                  ]}
                >
                  🚩 Flag for Review
                </button>
              </div>

              <div class="bg-slate-800 rounded-2xl p-6 mb-6">
                <p class="text-lg leading-relaxed"><%= @current_question.content %></p>
              </div>

              <!-- Answer area -->
              <%= cond do %>
                <% @current_question.question_type in [:multiple_choice, :true_false] -> %>
                  <div class="space-y-3" role="radiogroup">
                    <%= for {key, value} <- answer_options(@current_question) do %>
                      <button
                        phx-click="answer"
                        phx-value-question_id={@current_qid}
                        phx-value-answer={key}
                        role="radio"
                        aria-checked={selected_answer(@engine_state, @current_qid) == key}
                        class={[
                          "w-full text-left px-4 py-3 rounded-xl border transition-colors",
                          if(selected_answer(@engine_state, @current_qid) == key,
                            do: "border-slate-400 bg-slate-700 text-white",
                            else:
                              "border-slate-600 bg-slate-800 text-slate-300 hover:border-slate-500 hover:bg-slate-700"
                          )
                        ]}
                      >
                        <span class="font-medium mr-2"><%= key %>.</span>
                        <%= value %>
                      </button>
                    <% end %>
                  </div>
                <% @current_question.question_type in [:short_answer, :free_response] -> %>
                  <form phx-submit="answer">
                    <input type="hidden" name="question_id" value={@current_qid} />
                    <textarea
                      name="answer"
                      rows={if @current_question.question_type == :free_response, do: 6, else: 2}
                      placeholder="Your answer..."
                      class="w-full bg-slate-800 border border-slate-600 rounded-xl px-4 py-3 text-white placeholder-slate-500 focus:outline-none focus:border-slate-400 resize-none"
                    ><%= selected_answer(@engine_state, @current_qid) %></textarea>
                    <button
                      type="submit"
                      class="mt-2 bg-slate-700 hover:bg-slate-600 text-white px-4 py-2 rounded-full text-sm"
                    >
                      Save Answer
                    </button>
                  </form>
                <% true -> %>
                  <p class="text-slate-400 text-sm">
                    Question type not supported in simulation yet.
                  </p>
              <% end %>

              <!-- Navigation -->
              <div class="flex justify-between mt-8">
                <button
                  phx-click="prev"
                  class="text-slate-400 hover:text-white flex items-center gap-1 text-sm"
                >
                  &larr; Previous
                </button>
                <button
                  phx-click="next"
                  class="text-slate-400 hover:text-white flex items-center gap-1 text-sm"
                >
                  Next &rarr;
                </button>
              </div>
            </div>
          <% else %>
            <div class="max-w-2xl mx-auto text-center py-16 text-slate-400">
              No questions available in this section.
            </div>
          <% end %>
        </div>
      </div>

      <!-- Submit confirmation modal -->
      <%= if @submit_modal_open do %>
        <div
          class="fixed inset-0 bg-black/60 flex items-center justify-center z-50"
          role="dialog"
          aria-modal="true"
        >
          <div class="bg-slate-800 rounded-2xl p-8 max-w-md w-full mx-4 shadow-2xl">
            <h2 class="text-xl font-semibold mb-4">Submit Exam?</h2>
            <%= if @unanswered_count > 0 do %>
              <p class="text-slate-300 mb-2">
                You have
                <strong class="text-amber-400"><%= @unanswered_count %> unanswered question(s)</strong>. They will be marked incorrect.
              </p>
            <% else %>
              <p class="text-slate-300 mb-2">You've answered all questions. Ready to submit?</p>
            <% end %>
            <p class="text-slate-400 text-sm mb-6">
              This will end your exam and show your results.
            </p>
            <div class="flex gap-3">
              <button
                phx-click="close_submit_modal"
                class="flex-1 border border-slate-600 text-slate-300 py-2 rounded-full hover:bg-slate-700"
              >
                Cancel
              </button>
              <button
                phx-click="confirm_submit"
                class="flex-1 bg-[#4CD964] hover:bg-[#3DBF55] text-white py-2 rounded-full font-medium"
              >
                Submit Exam
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp answer_options(%{question_type: :true_false}) do
    [{"True", "True"}, {"False", "False"}]
  end

  defp answer_options(%{options: options}) when is_map(options) do
    options
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map(fn {k, v} -> {k, v} end)
  end

  defp answer_options(_), do: []
end
