defmodule FunSheepWeb.FixedTests.SessionLive do
  @moduledoc """
  Fixed-question test taking LiveView.

  Supports:
  - Free navigation (default): student can jump between questions
  - Linear (optional): one-at-a-time, no going back
  - Countdown timer if bank.time_limit_minutes is set
  - Session recovery on page reload (re-hydrates from DB)
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Accounts, FixedTests}
  alias FunSheep.FixedTests.FixedTestSession

  @timer_interval 1000

  @impl true
  def mount(%{"session_id" => session_id}, _session, socket) do
    user = socket.assigns.current_user
    user_role = Accounts.get_user_role_by_interactor_id(user["interactor_user_id"])

    session = FixedTests.get_session!(session_id)

    if session.user_role_id != user_role.id do
      {:ok, push_navigate(socket, to: ~p"/custom-tests")}
    else
      bank = FixedTests.get_bank_with_questions!(session.bank_id)

      questions = ordered_questions(bank, session)
      answers_map = build_answers_map(session)

      phase =
        case session.status do
          "completed" -> :reviewing
          "in_progress" -> :taking
          _ -> :taking
        end

      socket =
        socket
        |> assign(
          page_title: bank.title,
          session: session,
          bank: bank,
          questions: questions,
          current_index: 0,
          answers_map: answers_map,
          phase: phase,
          elapsed_seconds: elapsed_since(session),
          timer_ref: nil
        )
        |> maybe_start_timer(bank)

      {:ok, socket}
    end
  end

  # ── Timer ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_info(:tick, socket) do
    elapsed = socket.assigns.elapsed_seconds + 1
    bank = socket.assigns.bank

    if bank.time_limit_minutes && elapsed >= bank.time_limit_minutes * 60 do
      {:noreply, submit_all(socket)}
    else
      {:noreply, assign(socket, elapsed_seconds: elapsed)}
    end
  end

  # ── Navigation ────────────────────────────────────────────────────────────

  @impl true
  def handle_event("go_to", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    {:noreply, assign(socket, current_index: index)}
  end

  def handle_event("prev", _params, socket) do
    idx = max(socket.assigns.current_index - 1, 0)
    {:noreply, assign(socket, current_index: idx)}
  end

  def handle_event("next", _params, socket) do
    idx = min(socket.assigns.current_index + 1, length(socket.assigns.questions) - 1)
    {:noreply, assign(socket, current_index: idx)}
  end

  # ── Answer submission ─────────────────────────────────────────────────────

  def handle_event("answer", %{"question_id" => qid, "value" => value}, socket) do
    session = socket.assigns.session

    case FixedTests.submit_answer(session, qid, value) do
      {:ok, updated_session} ->
        answers_map = build_answers_map(updated_session)

        {:noreply,
         socket
         |> assign(session: updated_session, answers_map: answers_map)
         |> auto_advance(socket.assigns.current_index)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save answer")}
    end
  end

  def handle_event("submit_all", _params, socket) do
    {:noreply, submit_all(socket)}
  end

  # ── Render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F5F7]">
      <div class="max-w-3xl mx-auto py-6 px-4">
        <.test_header bank={@bank} elapsed={@elapsed_seconds} phase={@phase} />

        <%= case @phase do %>
          <% :taking -> %>
            <.question_panel
              question={Enum.at(@questions, @current_index)}
              current_index={@current_index}
              total={length(@questions)}
              answers_map={@answers_map}
            />
            <.navigation
              current_index={@current_index}
              total={length(@questions)}
              answers_map={@answers_map}
              questions={@questions}
            />
          <% :reviewing -> %>
            <.results_panel session={@session} questions={@questions} bank={@bank} />
        <% end %>
      </div>
    </div>
    """
  end

  defp test_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-6">
      <div>
        <div class="flex items-center gap-2 mb-1">
          <span class="text-xs font-medium bg-indigo-100 text-indigo-700 px-2 py-0.5 rounded-full">
            Custom Test
          </span>
        </div>
        <h1 class="text-xl font-bold text-[#1C1C1E]">{@bank.title}</h1>
      </div>
      <%= if @bank.time_limit_minutes && @phase == :taking do %>
        <.timer elapsed={@elapsed} limit_minutes={@bank.time_limit_minutes} />
      <% end %>
    </div>
    """
  end

  defp timer(assigns) do
    remaining = assigns.limit_minutes * 60 - assigns.elapsed
    minutes = div(remaining, 60)
    seconds = rem(remaining, 60)
    urgent = remaining < 60

    assigns = assign(assigns, minutes: minutes, seconds: seconds, urgent: urgent)

    ~H"""
    <div class={[
      "font-mono text-lg font-bold px-4 py-2 rounded-full",
      if(@urgent, do: "bg-red-50 text-red-500", else: "bg-white text-[#1C1C1E]")
    ]}>
      {String.pad_leading("#{@minutes}", 2, "0")}:{String.pad_leading("#{@seconds}", 2, "0")}
    </div>
    """
  end

  defp question_panel(assigns) do
    question = assigns.question
    answer_entry = assigns.answers_map[question.id]
    selected = answer_entry && answer_entry["answer_given"]

    assigns = assign(assigns, selected: selected)

    ~H"""
    <div class="bg-white rounded-2xl shadow-sm p-6 mb-4">
      <p class="text-xs text-[#8E8E93] mb-2">
        Question {@current_index + 1} of {@total}
      </p>
      <p class="text-lg font-medium text-[#1C1C1E] mb-5">{@question.question_text}</p>

      <%= cond do %>
        <% @question.question_type == "multiple_choice" && @question.options -> %>
          <div class="space-y-2">
            <%= for opt <- @question.options["choices"] || [] do %>
              <button
                phx-click="answer"
                phx-value-question_id={@question.id}
                phx-value-value={opt["value"]}
                class={[
                  "w-full text-left px-4 py-3 rounded-xl border transition-colors",
                  if(@selected == opt["value"],
                    do: "border-[#4CD964] bg-green-50 text-[#1C1C1E] font-medium",
                    else: "border-gray-200 hover:border-gray-300 text-[#1C1C1E]"
                  )
                ]}
              >
                {opt["label"]}
              </button>
            <% end %>
          </div>
        <% @question.question_type == "true_false" -> %>
          <div class="flex gap-3">
            <%= for val <- ["true", "false"] do %>
              <button
                phx-click="answer"
                phx-value-question_id={@question.id}
                phx-value-value={val}
                class={[
                  "flex-1 py-3 rounded-xl border font-medium transition-colors",
                  if(@selected == val,
                    do: "border-[#4CD964] bg-green-50 text-[#1C1C1E]",
                    else: "border-gray-200 hover:border-gray-300 text-[#1C1C1E]"
                  )
                ]}
              >
                {String.capitalize(val)}
              </button>
            <% end %>
          </div>
        <% true -> %>
          <.short_answer_input question_id={@question.id} current_value={@selected} />
      <% end %>
    </div>
    """
  end

  defp short_answer_input(assigns) do
    ~H"""
    <form phx-submit="answer">
      <input type="hidden" name="question_id" value={@question_id} />
      <input
        type="text"
        name="value"
        value={@current_value || ""}
        placeholder="Type your answer…"
        class="w-full border border-gray-200 rounded-xl px-4 py-3 focus:border-[#4CD964] focus:outline-none"
      />
      <button
        type="submit"
        class="mt-2 bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-5 py-2 rounded-full"
      >
        Save answer
      </button>
    </form>
    """
  end

  defp navigation(assigns) do
    answered_count = map_size(assigns.answers_map)
    all_answered = answered_count == assigns.total

    assigns = assign(assigns, answered_count: answered_count, all_answered: all_answered)

    ~H"""
    <div class="flex items-center justify-between">
      <div class="flex gap-2">
        <button
          :if={@current_index > 0}
          phx-click="prev"
          class="border border-gray-200 px-4 py-2 rounded-full text-sm hover:bg-gray-50"
        >
          ← Previous
        </button>
        <button
          :if={@current_index < @total - 1}
          phx-click="next"
          class="border border-gray-200 px-4 py-2 rounded-full text-sm hover:bg-gray-50"
        >
          Next →
        </button>
      </div>

      <div class="flex items-center gap-3">
        <span class="text-sm text-[#8E8E93]">
          {@answered_count} / {@total} answered
        </span>
        <button
          phx-click="submit_all"
          data-confirm={
            if !@all_answered,
              do: "You have #{@total - @answered_count} unanswered question(s). Submit anyway?",
              else: nil
          }
          class="bg-[#1C1C1E] hover:bg-[#3A3A3C] text-white font-medium px-5 py-2 rounded-full text-sm"
        >
          Submit test
        </button>
      </div>
    </div>
    """
  end

  defp results_panel(assigns) do
    pct =
      if assigns.session.score_total > 0,
        do: round(assigns.session.score_correct / assigns.session.score_total * 100),
        else: 0

    answers_map =
      (assigns.session.answers || [])
      |> Map.new(fn a -> {a["question_id"], a} end)

    assigns = assign(assigns, pct: pct, answers_map: answers_map)

    ~H"""
    <div>
      <div class="bg-white rounded-2xl shadow-sm p-6 mb-4 text-center">
        <p class={["text-5xl font-extrabold mb-1", score_color(@pct)]}>{@pct}%</p>
        <p class="text-[#8E8E93]">
          {@session.score_correct} of {@session.score_total} correct
          <%= if @session.time_taken_seconds do %>
            · {format_duration(@session.time_taken_seconds)}
          <% end %>
        </p>
      </div>

      <div class="space-y-3 mb-6">
        <%= for {q, idx} <- Enum.with_index(@questions, 1) do %>
          <% answer = @answers_map[q.id] %>
          <div class="bg-white rounded-2xl shadow-sm p-5">
            <div class="flex items-start gap-3">
              <span class={[
                "mt-0.5 text-lg font-bold shrink-0",
                if(answer && answer["is_correct"], do: "text-[#4CD964]", else: "text-[#FF3B30]")
              ]}>
                {if answer && answer["is_correct"], do: "✓", else: "✗"}
              </span>
              <div class="flex-1">
                <p class="text-xs text-[#8E8E93] mb-1">Q{idx}</p>
                <p class="font-medium text-[#1C1C1E]">{q.question_text}</p>
                <%= if answer do %>
                  <p class="text-sm mt-1 text-[#8E8E93]">
                    Your answer:
                    <span class={[
                      "font-medium",
                      if(answer["is_correct"], do: "text-[#4CD964]", else: "text-[#FF3B30]")
                    ]}>
                      {answer["answer_given"] || "—"}
                    </span>
                  </p>
                <% end %>
                <%= if answer && !answer["is_correct"] do %>
                  <p class="text-sm text-[#4CD964]">Correct: {q.answer_text}</p>
                <% end %>
                <%= if q.explanation do %>
                  <p class="text-sm text-[#8E8E93] mt-1 italic">{q.explanation}</p>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <div class="flex gap-3">
        <.link
          navigate={~p"/custom-tests/#{@bank.id}/start"}
          class="border border-gray-200 px-5 py-2 rounded-full text-sm hover:bg-gray-50"
        >
          Retake
        </.link>
        <.link
          navigate={~p"/custom-tests"}
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-5 py-2 rounded-full text-sm"
        >
          Done
        </.link>
      </div>
    </div>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp ordered_questions(bank, %FixedTestSession{questions_order: order})
       when is_list(order) and order != [] do
    by_id = Map.new(bank.questions, &{&1.id, &1})
    Enum.map(order, fn id -> Map.get(by_id, id) end) |> Enum.reject(&is_nil/1)
  end

  defp ordered_questions(bank, _session), do: bank.questions

  defp build_answers_map(%FixedTestSession{answers: answers}) when is_list(answers) do
    Map.new(answers, fn a -> {a["question_id"], a} end)
  end

  defp build_answers_map(_), do: %{}

  defp elapsed_since(%FixedTestSession{started_at: nil}), do: 0

  defp elapsed_since(%FixedTestSession{started_at: started_at}) do
    DateTime.diff(DateTime.utc_now(), started_at, :second)
  end

  defp maybe_start_timer(socket, %{time_limit_minutes: nil}), do: socket

  defp maybe_start_timer(socket, %{time_limit_minutes: _}) do
    if socket.assigns.phase == :taking do
      ref = Process.send_after(self(), :tick, @timer_interval)
      assign(socket, timer_ref: ref)
    else
      socket
    end
  end

  defp auto_advance(socket, current_index) do
    total = length(socket.assigns.questions)

    if current_index < total - 1 do
      assign(socket, current_index: current_index + 1)
    else
      socket
    end
  end

  defp submit_all(socket) do
    session = socket.assigns.session

    case FixedTests.complete_session(session) do
      {:ok, completed} ->
        assign(socket, session: completed, phase: :reviewing)

      {:error, _} ->
        put_flash(socket, :error, "Could not submit test")
    end
  end

  defp score_color(pct) when pct >= 70, do: "text-[#4CD964]"
  defp score_color(pct) when pct >= 40, do: "text-[#FF9500]"
  defp score_color(_), do: "text-[#FF3B30]"

  defp format_duration(seconds) do
    m = div(seconds, 60)
    s = rem(seconds, 60)
    "#{m}:#{String.pad_leading("#{s}", 2, "0")}"
  end
end
