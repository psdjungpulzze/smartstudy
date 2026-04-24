defmodule FunSheepWeb.QuickPracticeLive do
  @moduledoc """
  Swipeable "Tinder for learning" practice experience.

  Defaults to the closest upcoming `TestSchedule`'s course so students
  drill for their next exam; supports `?test_id=` / `?course_id=` URL
  params to switch via the upcoming-tests pill row. Mobile uses swipe
  gestures via the `SwipeCard` JS hook; desktop uses arrow-key
  shortcuts wired through `phx-window-keydown`.
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Assessments, Billing, Content, Courses, Questions, Tutor, Tutorials}
  alias FunSheep.Assessments.QuickTestEngine
  alias FunSheep.Gamification
  alias FunSheep.Questions.{FreeformGrader, ScoredFreeformGrader}

  @batch_size 30
  @tutorial_key "quick_practice"

  @impl true
  def mount(_params, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]

    courses = Courses.list_courses_for_user(user_role_id)
    upcoming_tests = Assessments.list_upcoming_schedules(user_role_id, 365)
    streak_info = Gamification.dashboard_summary(user_role_id)
    show_tutorial = not Tutorials.seen?(user_role_id, @tutorial_key)

    socket =
      socket
      |> assign(
        page_title: "Practice",
        courses: courses,
        upcoming_tests: upcoming_tests,
        selected_course_id: nil,
        selected_test_id: nil,
        engine_state: nil,
        current_question: nil,
        selected_answer: nil,
        show_answer: false,
        feedback: nil,
        question_number: 0,
        total_questions: 0,
        session_complete: false,
        summary: nil,
        stats: %{correct: 0, incorrect: 0, skipped: 0},
        card_phase: :question,
        streak: streak_info.streak,
        session_streak: 0,
        show_tutorial: show_tutorial,
        pending_is_correct: nil,
        pending_answer: nil,
        # Tutor state
        tutor_open: false,
        tutor_session_id: nil,
        tutor_messages: [],
        tutor_loading: false,
        tutor_input: "",
        # Async grading state
        grading: false,
        grading_task: nil,
        pending_grade_result: nil,
        # Study references
        current_question_videos: []
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    %{upcoming_tests: upcoming, current_user: user} = socket.assigns
    user_role_id = user["user_role_id"]

    {selected_course_id, selected_test_id} =
      resolve_selection(params, upcoming)

    state =
      QuickTestEngine.start_session(user_role_id, %{
        course_id: selected_course_id,
        limit: @batch_size
      })

    socket =
      socket
      |> assign(
        selected_course_id: selected_course_id,
        selected_test_id: selected_test_id,
        engine_state: state,
        total_questions: length(state.questions),
        question_number: 0,
        session_complete: false,
        summary: nil,
        stats: %{correct: 0, incorrect: 0, skipped: 0},
        card_phase: :question,
        selected_answer: nil,
        show_answer: false,
        feedback: nil,
        session_streak: 0
      )
      |> reset_tutor()
      |> advance_to_next_card()

    {:noreply, socket}
  end

  # Picks the selected course_id and test_id from URL params, falling back to
  # the closest upcoming test's course. Returns {nil, nil} if no upcoming tests
  # and no params — meaning practice pulls from all enrolled courses.
  defp resolve_selection(params, upcoming_tests) do
    cond do
      test_id = params["test_id"] ->
        case Enum.find(upcoming_tests, &(&1.id == test_id)) do
          nil -> fallback_selection(upcoming_tests)
          test -> {test.course_id, test.id}
        end

      course_id = params["course_id"] ->
        matching_test = Enum.find(upcoming_tests, &(&1.course_id == course_id))
        {course_id, matching_test && matching_test.id}

      true ->
        fallback_selection(upcoming_tests)
    end
  end

  defp fallback_selection([]), do: {nil, nil}

  defp fallback_selection([closest | _]) do
    {closest.course_id, closest.id}
  end

  # ── Swipe events (from JS hook) ──

  @impl true
  def handle_event("swipe", %{"direction" => "right"}, socket) do
    handle_event("mark_i_know", %{}, socket)
  end

  def handle_event("swipe", %{"direction" => "left"}, socket) do
    handle_event("mark_dont_know", %{}, socket)
  end

  def handle_event("swipe", %{"direction" => "up"}, socket) do
    handle_event("skip", %{}, socket)
  end

  # ── Button events (accessibility fallbacks) ──

  # ── Confidence-based flashcard handlers (I-17) ──
  # These replace mark_known / mark_unknown with a 3-way confidence signal.

  def handle_event("mark_i_know", _params, socket) do
    %{current_question: question, engine_state: state, stats: stats} = socket.assigns

    if question do
      record_attempt(socket, question, "known", true, confidence: :i_know)
      new_state = QuickTestEngine.mark_known(state, question.id)

      socket =
        socket
        |> assign(
          engine_state: new_state,
          stats: %{stats | correct: stats.correct + 1},
          card_phase: :question,
          feedback: nil,
          selected_answer: nil,
          show_answer: false,
          session_streak: socket.assigns.session_streak + 1
        )
        |> reset_tutor()
        |> advance_to_next_card()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("mark_not_sure", _params, socket) do
    %{current_question: question, engine_state: state, stats: stats} = socket.assigns

    if question do
      record_attempt(socket, question, "not_sure", false, confidence: :not_sure)
      new_state = QuickTestEngine.mark_unknown(state, question.id)
      videos = Content.list_videos_for_section(question.section_id)

      {:noreply,
       assign(socket,
         engine_state: new_state,
         card_phase: :reveal,
         show_answer: true,
         feedback: nil,
         stats: %{stats | incorrect: stats.incorrect + 1},
         session_streak: 0,
         current_question_videos: videos
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("mark_dont_know", _params, socket) do
    %{current_question: question, engine_state: state, stats: stats} = socket.assigns

    if question do
      record_attempt(socket, question, "dont_know", false, confidence: :dont_know)
      new_state = QuickTestEngine.mark_unknown(state, question.id)
      videos = Content.list_videos_for_section(question.section_id)

      {:noreply,
       assign(socket,
         engine_state: new_state,
         card_phase: :reveal,
         show_answer: true,
         feedback: nil,
         stats: %{stats | incorrect: stats.incorrect + 1},
         session_streak: 0,
         current_question_videos: videos
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("skip", _params, socket) do
    %{current_question: question, engine_state: state, stats: stats} = socket.assigns

    if question do
      new_state = QuickTestEngine.skip(state, question.id)

      socket =
        socket
        |> assign(
          engine_state: new_state,
          stats: %{stats | skipped: stats.skipped + 1},
          card_phase: :question,
          feedback: nil,
          selected_answer: nil,
          show_answer: false
        )
        |> reset_tutor()
        |> advance_to_next_card()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("show_answer_input", _params, socket) do
    {:noreply, assign(socket, card_phase: :answering)}
  end

  def handle_event("select_answer", %{"answer" => answer}, socket) do
    {:noreply, assign(socket, selected_answer: answer)}
  end

  def handle_event("update_text_answer", %{"answer" => answer}, socket) do
    {:noreply, assign(socket, selected_answer: answer)}
  end

  def handle_event("submit_answer", _params, socket) do
    %{current_question: question, selected_answer: answer, engine_state: state, stats: stats} =
      socket.assigns

    if answer == nil or question == nil do
      {:noreply, socket}
    else
      freeform? = question.question_type in [:short_answer, :free_response]

      if freeform? do
        user_role_id = socket.assigns.current_user["user_role_id"]

        grader =
          if Billing.subscription_has_scored_grading?(user_role_id),
            do: ScoredFreeformGrader,
            else: FreeformGrader

        task = Task.async(fn -> grader.grade(question, answer) end)

        {:noreply,
         assign(socket,
           grading: true,
           grading_task: task.ref,
           pending_grade_result: nil
         )}
      else
        is_correct = check_answer(question, answer)
        new_state = QuickTestEngine.mark_answered(state, question.id, is_correct)

        new_stats =
          if is_correct,
            do: %{stats | correct: stats.correct + 1},
            else: %{stats | incorrect: stats.incorrect + 1}

        new_streak =
          if is_correct,
            do: socket.assigns.session_streak + 1,
            else: 0

        # Defer DB insert until confidence is selected (Phase 2 — collect confidence first)
        socket =
          socket
          |> assign(
            engine_state: new_state,
            stats: new_stats,
            feedback: %{
              is_correct: is_correct,
              correct_answer: question.answer,
              grade_result: nil
            },
            pending_is_correct: is_correct,
            pending_answer: answer,
            card_phase: :feedback,
            session_streak: new_streak
          )

        socket =
          if is_correct do
            push_event(socket, "confetti_burst", %{})
          else
            push_event(socket, "play_sound", %{name: "sheep_wrong"})
          end

        {:noreply, socket}
      end
    end
  end

  def handle_event("confidence_selected", %{"confidence" => confidence_str}, socket) do
    %{current_question: question, pending_is_correct: is_correct, pending_answer: answer} =
      socket.assigns

    confidence = String.to_existing_atom(confidence_str)

    if question && not is_nil(is_correct) do
      record_attempt(socket, question, answer || "unknown", is_correct, confidence: confidence)
    end

    socket =
      socket
      |> assign(
        card_phase: :question,
        feedback: nil,
        selected_answer: nil,
        show_answer: false,
        pending_is_correct: nil,
        pending_answer: nil,
        current_question_videos: []
      )
      |> reset_tutor()
      |> advance_to_next_card()

    {:noreply, socket}
  end

  def handle_event("next_card", _params, socket) do
    socket =
      socket
      |> assign(
        card_phase: :question,
        feedback: nil,
        selected_answer: nil,
        show_answer: false,
        current_question_videos: []
      )
      |> reset_tutor()
      |> advance_to_next_card()

    {:noreply, socket}
  end

  def handle_event("restart", _params, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]

    state =
      QuickTestEngine.start_session(user_role_id, %{
        course_id: socket.assigns.selected_course_id,
        limit: @batch_size
      })

    socket =
      socket
      |> assign(
        engine_state: state,
        current_question: nil,
        selected_answer: nil,
        show_answer: false,
        feedback: nil,
        question_number: 0,
        total_questions: length(state.questions),
        session_complete: false,
        summary: nil,
        stats: %{correct: 0, incorrect: 0, skipped: 0},
        card_phase: :question,
        session_streak: 0
      )
      |> advance_to_next_card()

    {:noreply, socket}
  end

  def handle_event("dismiss_tutorial", _params, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    Tutorials.mark_seen(user_role_id, @tutorial_key)
    {:noreply, assign(socket, show_tutorial: false)}
  end

  def handle_event("replay_tutorial", _params, socket) do
    {:noreply, assign(socket, show_tutorial: true)}
  end

  def handle_event("keydown", %{"key" => key}, socket) do
    %{card_phase: phase, current_question: q, session_complete: done} = socket.assigns

    cond do
      done or is_nil(q) ->
        {:noreply, socket}

      phase == :question and key == "ArrowRight" ->
        handle_event("mark_i_know", %{}, socket)

      phase == :question and key == "ArrowLeft" ->
        handle_event("mark_dont_know", %{}, socket)

      phase == :question and key == "ArrowUp" ->
        handle_event("skip", %{}, socket)

      phase == :question and key in [" ", "Enter"] ->
        handle_event("show_answer_input", %{}, socket)

      phase == :reveal and key in [" ", "Enter", "ArrowRight"] ->
        handle_event("next_card", %{}, socket)

      phase == :answering and key == "Escape" ->
        handle_event("next_card", %{}, socket)

      true ->
        {:noreply, socket}
    end
  end

  # ── Tutor events ──

  def handle_event("open_tutor", _params, socket) do
    socket = ensure_tutor_session(socket)
    {:noreply, assign(socket, tutor_open: true)}
  end

  def handle_event("close_tutor", _params, socket) do
    {:noreply, assign(socket, tutor_open: false)}
  end

  def handle_event("tutor_quick_action", %{"action" => action}, socket) do
    socket = ensure_tutor_session(socket)
    question = socket.assigns.current_question

    if question && socket.assigns.tutor_session_id do
      user_label = tutor_action_label(action)

      socket =
        socket
        |> assign(tutor_loading: true, tutor_open: true)
        |> append_tutor_message("user", user_label)

      send(self(), {:tutor_quick_action, action, question})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("tutor_send", %{"message" => message}, socket) when byte_size(message) > 0 do
    socket = ensure_tutor_session(socket)

    if socket.assigns.tutor_session_id do
      socket =
        socket
        |> assign(tutor_loading: true, tutor_input: "")
        |> append_tutor_message("user", message)

      send(self(), {:tutor_send, message})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("tutor_send", _params, socket), do: {:noreply, socket}

  def handle_event("tutor_input", %{"message" => value}, socket) do
    {:noreply, assign(socket, tutor_input: value)}
  end

  # ── Freeform grading task results ──

  @impl true
  def handle_info({ref, {:ok, %{score: _score, is_correct: is_correct} = grade_result}}, socket)
      when socket.assigns.grading_task == ref do
    Process.demonitor(ref, [:flush])
    apply_freeform_grading_result(socket, is_correct, grade_result)
  end

  def handle_info({ref, {:ok, %{correct: is_correct, feedback: _ai_feedback}}}, socket)
      when socket.assigns.grading_task == ref do
    Process.demonitor(ref, [:flush])
    apply_freeform_grading_result(socket, is_correct, nil)
  end

  def handle_info({ref, {:error, _reason}}, socket)
      when socket.assigns.grading_task == ref do
    Process.demonitor(ref, [:flush])
    %{current_question: question, selected_answer: answer} = socket.assigns
    is_correct = check_answer(question, answer)
    apply_freeform_grading_result(socket, is_correct, nil)
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket)
      when socket.assigns.grading_task == ref do
    %{current_question: question, selected_answer: answer} = socket.assigns
    is_correct = check_answer(question, answer)
    apply_freeform_grading_result(socket, is_correct, nil)
  end

  def handle_info({:tutor_quick_action, action, question}, socket) do
    session_id = socket.assigns.tutor_session_id

    case Tutor.quick_action(session_id, action, question) do
      {:ok, response} ->
        {:noreply,
         socket
         |> assign(tutor_loading: false)
         |> append_tutor_message("assistant", response)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(tutor_loading: false)
         |> append_tutor_message(
           "assistant",
           "Sorry, I had trouble responding. Please try again."
         )}
    end
  end

  def handle_info({:tutor_send, message}, socket) do
    session_id = socket.assigns.tutor_session_id

    case Tutor.ask(session_id, message) do
      {:ok, response} ->
        {:noreply,
         socket
         |> assign(tutor_loading: false)
         |> append_tutor_message("assistant", response)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(tutor_loading: false)
         |> append_tutor_message(
           "assistant",
           "Sorry, I had trouble responding. Please try again."
         )}
    end
  end

  def handle_info({:tutor_response, _response}, socket), do: {:noreply, socket}

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Private helpers ──

  defp advance_to_next_card(socket) do
    state = socket.assigns.engine_state

    case QuickTestEngine.current_card(state) do
      {:card, question, new_state} ->
        question_stats = Questions.get_question_stats(question.id)

        assign(socket,
          engine_state: new_state,
          current_question: question,
          current_question_stats: question_stats,
          question_number: socket.assigns.question_number + 1
        )

      {:complete, new_state} ->
        summary = QuickTestEngine.summary(new_state)

        assign(socket,
          engine_state: new_state,
          current_question: nil,
          session_complete: true,
          summary: summary
        )
    end
  end

  defp check_answer(question, answer), do: FunSheep.Questions.Grading.correct?(question, answer)

  defp record_attempt(socket, question, answer_given, is_correct, opts) do
    user_role_id = socket.assigns.current_user["user_role_id"]

    if user_role_id do
      confidence = Keyword.get(opts, :confidence)
      grade_result = Keyword.get(opts, :grade_result)

      base_attrs = %{
        user_role_id: user_role_id,
        question_id: question.id,
        answer_given: answer_given,
        is_correct: is_correct,
        difficulty_at_attempt: to_string(question.difficulty),
        confidence: confidence
      }

      attrs =
        if grade_result do
          Map.merge(base_attrs, %{
            score: grade_result.score,
            score_max: grade_result.max_score,
            score_feedback: grade_result.feedback,
            grader_path: to_string(grade_result.grader_path)
          })
        else
          base_attrs
        end

      Questions.record_attempt_with_stats(attrs)
    end
  end

  defp apply_freeform_grading_result(socket, is_correct, grade_result) do
    %{current_question: question, selected_answer: answer, engine_state: state, stats: stats} =
      socket.assigns

    record_attempt(socket, question, answer, is_correct, grade_result: grade_result)
    new_state = QuickTestEngine.mark_answered(state, question.id, is_correct)

    new_stats =
      if is_correct,
        do: %{stats | correct: stats.correct + 1},
        else: %{stats | incorrect: stats.incorrect + 1}

    new_streak =
      if is_correct,
        do: socket.assigns.session_streak + 1,
        else: 0

    {:noreply,
     assign(socket,
       grading: false,
       grading_task: nil,
       pending_grade_result: grade_result,
       engine_state: new_state,
       stats: new_stats,
       feedback: %{
         is_correct: is_correct,
         correct_answer: question.answer,
         grade_result: grade_result
       },
       card_phase: :feedback,
       session_streak: new_streak
     )}
  end

  defp ensure_tutor_session(socket) do
    if socket.assigns.tutor_session_id do
      socket
    else
      question = socket.assigns.current_question
      user_role_id = socket.assigns.current_user["user_role_id"]

      if question && user_role_id do
        case Tutor.start_session(user_role_id, question.id, question.course_id) do
          {:ok, session_id} ->
            Phoenix.PubSub.subscribe(FunSheep.PubSub, Tutor.topic(session_id))
            assign(socket, tutor_session_id: session_id)

          {:error, _reason} ->
            socket
        end
      else
        socket
      end
    end
  end

  defp append_tutor_message(socket, role, content) do
    msg = %{role: role, content: content, id: System.unique_integer([:positive])}
    assign(socket, tutor_messages: socket.assigns.tutor_messages ++ [msg])
  end

  defp tutor_action_label("hint"), do: "Give me a hint"
  defp tutor_action_label("explain"), do: "Explain this concept"
  defp tutor_action_label("why_wrong"), do: "Why was I wrong?"
  defp tutor_action_label("step_by_step"), do: "Walk me through it step by step"
  defp tutor_action_label(action), do: action

  defp reset_tutor(socket) do
    if session_id = socket.assigns.tutor_session_id do
      Phoenix.PubSub.unsubscribe(FunSheep.PubSub, Tutor.topic(session_id))
      Tutor.stop_session(session_id)
    end

    assign(socket,
      tutor_session_id: nil,
      tutor_messages: [],
      tutor_loading: false,
      tutor_open: false,
      tutor_input: ""
    )
  end

  defp question_type_label(:multiple_choice), do: "MCQ"
  defp question_type_label(:true_false), do: "T/F"
  defp question_type_label(:short_answer), do: "Short"
  defp question_type_label(:free_response), do: "Free"
  defp question_type_label(_), do: "Q"

  defp course_name_for_question(question, courses) do
    Enum.find_value(courses, "Practice", fn c ->
      if c.id == question.course_id, do: c.name
    end)
  end

  defp progress_pct(question_number, total) when total > 0 do
    Float.round(question_number / total * 100, 1)
  end

  defp progress_pct(_, _), do: 0

  defp days_until(%Date{} = date) do
    Date.diff(date, Date.utc_today())
  end

  defp pill_label(test) do
    course_name = (test.course && test.course.name) || test.name || "Practice"
    "#{course_name} · #{format_days(days_until(test.test_date))}"
  end

  defp format_days(0), do: "today"
  defp format_days(1), do: "tomorrow"
  defp format_days(n) when n > 0, do: "#{n}d"
  defp format_days(_), do: "past"

  # ── Render ──

  @impl true
  def render(assigns) do
    ~H"""
    <div phx-window-keydown="keydown" id="quick-practice-root">
      <%!-- First-time tutorial overlay (shared across mobile + desktop) --%>
      <.tutorial_overlay :if={@show_tutorial} />

      <%!-- Full-screen mobile practice — hidden on desktop (lg+) --%>
      <div class="lg:hidden fixed inset-0 z-30 bg-[#F5F5F7] flex flex-col" style="top: 0;">
        <%!-- Minimal top bar --%>
        <div class="flex items-center justify-between px-4 py-3 bg-white/90 backdrop-blur-sm border-b border-gray-100 safe-area-top shrink-0">
          <.link navigate={~p"/dashboard"} class="text-[#8E8E93] touch-target p-1">
            <.icon name="hero-arrow-left" class="w-5 h-5" />
          </.link>

          <div class="flex items-center gap-2">
            <span class="text-sm font-bold text-gray-900">Practice</span>
            <span
              :if={@session_streak >= 3}
              class="inline-flex items-center gap-0.5 px-2 py-0.5 bg-orange-50 rounded-full text-xs font-bold text-orange-600 animate-bounce"
            >
              🔥 {@session_streak}
            </span>
          </div>

          <div class="flex items-center gap-1.5">
            <span class="text-xs font-medium text-[#8E8E93]">
              {@question_number}/{@total_questions}
            </span>
            <.help_button />
          </div>
        </div>

        <%!-- Upcoming tests pill row --%>
        <.tests_pill_row
          :if={@upcoming_tests != []}
          upcoming_tests={@upcoming_tests}
          selected_test_id={@selected_test_id}
          selected_course_id={@selected_course_id}
        />

        <%!-- Stats pills --%>
        <div
          :if={!@session_complete}
          class="flex items-center justify-center gap-3 px-4 py-2 shrink-0"
        >
          <span class="inline-flex items-center gap-1 text-xs font-bold text-[#4CD964]">
            <.icon name="hero-check-circle-mini" class="w-4 h-4" /> {@stats.correct}
          </span>
          <span class="inline-flex items-center gap-1 text-xs font-bold text-[#FF3B30]">
            <.icon name="hero-x-circle-mini" class="w-4 h-4" /> {@stats.incorrect}
          </span>
          <span class="inline-flex items-center gap-1 text-xs font-bold text-[#8E8E93]">
            <.icon name="hero-forward-mini" class="w-4 h-4" /> {@stats.skipped}
          </span>
        </div>

        <%!-- Progress bar with walking sheep mascot --%>
        <div :if={!@session_complete} class="px-4 shrink-0">
          <div
            id="quick-practice-progress-bar"
            phx-hook="SheepProgressBar"
            data-readiness={progress_pct(@question_number, @total_questions)}
            class="relative w-full bg-gray-200 rounded-full h-2 overflow-visible"
          >
            <div
              class="bg-[#4CD964] h-2 rounded-full transition-all duration-300"
              style={"width: #{progress_pct(@question_number, @total_questions)}%"}
            />
            <div
              data-sheep
              class="absolute top-1/2 -translate-y-1/2 pointer-events-none"
              style="will-change: transform; position: absolute;"
            >
              <FunSheepWeb.SheepMascot.sheep_icon size="sm" state="walk" />
            </div>
          </div>
        </div>

        <%!-- Main card area --%>
        <div class="flex-1 flex items-center justify-center px-4 py-4 overflow-hidden">
          <%!-- Empty state --%>
          <div :if={@total_questions == 0 && !@session_complete} class="text-center px-6">
            <div class="text-6xl mb-4">🐑</div>
            <h2 class="text-xl font-bold text-gray-900 mb-2">No Questions Yet</h2>
            <p class="text-sm text-[#8E8E93] mb-6">
              Add courses and questions to start practicing!
            </p>
            <.link
              navigate={~p"/courses"}
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors inline-block"
            >
              Browse Courses
            </.link>
          </div>

          <%!-- Swipeable card --%>
          <div
            :if={@current_question && !@session_complete && @card_phase == :question}
            id={"card-#{@current_question.id}"}
            phx-hook="SwipeCard"
            class="relative w-full max-w-sm bg-white rounded-2xl shadow-lg cursor-grab active:cursor-grabbing select-none"
            style="touch-action: none;"
          >
            <%!-- Swipe overlays --%>
            <div
              data-swipe-right
              class="absolute inset-0 rounded-2xl border-4 border-[#4CD964] bg-[#4CD964]/10 flex items-center justify-center z-10 pointer-events-none"
              style="opacity: 0;"
            >
              <span class="text-5xl font-black text-[#4CD964] rotate-[-15deg]">KNOW IT</span>
            </div>
            <div
              data-swipe-left
              class="absolute inset-0 rounded-2xl border-4 border-[#FF3B30] bg-[#FF3B30]/10 flex items-center justify-center z-10 pointer-events-none"
              style="opacity: 0;"
            >
              <span class="text-5xl font-black text-[#FF3B30] rotate-[15deg]">LEARN</span>
            </div>
            <div
              data-swipe-up
              class="absolute inset-0 rounded-2xl border-4 border-[#8E8E93] bg-gray-100/50 flex items-center justify-center z-10 pointer-events-none"
              style="opacity: 0;"
            >
              <span class="text-4xl font-black text-[#8E8E93]">SKIP</span>
            </div>

            <%!-- Card content --%>
            <div class="p-5 flex flex-col min-h-[320px]">
              <%!-- Tags --%>
              <div class="flex items-center gap-2 mb-4 flex-wrap">
                <span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-[#F5F5F7] text-[#8E8E93] uppercase tracking-wide">
                  {course_name_for_question(@current_question, @courses)}
                </span>
                <span
                  :if={@current_question.chapter}
                  class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-blue-50 text-[#007AFF]"
                >
                  {String.slice(@current_question.chapter.name || "", 0..25)}
                </span>
                <span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-purple-50 text-purple-600">
                  {question_type_label(@current_question.question_type)}
                </span>
              </div>

              <%!-- Question text --%>
              <div class="flex-1 flex items-center justify-center py-4">
                <p class="text-lg font-semibold text-gray-900 text-center leading-relaxed">
                  {@current_question.content}
                </p>
              </div>

              <%!-- MCQ options preview (read-only on swipe card) --%>
              <div
                :if={@current_question.question_type == :multiple_choice && @current_question.options}
                class="space-y-2 mt-2"
              >
                <%= for {key, value} <- Enum.sort_by(@current_question.options || %{}, fn {k, _} -> k end) do %>
                  <div class="flex items-start gap-2 px-3 py-2 bg-[#F5F5F7] rounded-xl text-sm">
                    <span class="font-bold text-[#8E8E93] shrink-0">{key}.</span>
                    <span class="text-gray-800">{value}</span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Answer input phase --%>
          <div
            :if={@current_question && !@session_complete && @card_phase == :answering}
            class="w-full max-w-sm bg-white rounded-2xl shadow-lg p-5"
          >
            <p class="text-base font-semibold text-gray-900 mb-4 text-center">
              {@current_question.content}
            </p>

            <%= case @current_question.question_type do %>
              <% :multiple_choice -> %>
                <div class="space-y-2">
                  <%= for {key, value} <- Enum.sort_by(@current_question.options || %{}, fn {k, _} -> k end) do %>
                    <button
                      type="button"
                      phx-click="select_answer"
                      phx-value-answer={key}
                      class={[
                        "w-full text-left p-3 rounded-xl border-2 transition-colors text-sm touch-target",
                        if(@selected_answer == key,
                          do: "border-[#4CD964] bg-[#E8F8EB]",
                          else: "border-[#E5E5EA] active:border-[#4CD964]"
                        )
                      ]}
                    >
                      <span class="font-bold text-[#1C1C1E]">{key}.</span>
                      <span class="ml-2 text-[#1C1C1E]">{value}</span>
                    </button>
                  <% end %>
                </div>
              <% :true_false -> %>
                <div class="flex gap-3">
                  <button
                    :for={value <- ["True", "False"]}
                    phx-click="select_answer"
                    phx-value-answer={value}
                    class={[
                      "flex-1 p-3 rounded-xl border-2 text-center font-medium text-sm touch-target transition-colors",
                      if(@selected_answer == value,
                        do: "border-[#4CD964] bg-[#E8F8EB] text-[#4CD964]",
                        else: "border-[#E5E5EA] text-[#1C1C1E] active:border-[#4CD964]"
                      )
                    ]}
                  >
                    {value}
                  </button>
                </div>
              <% _other -> %>
                <form phx-change="update_text_answer">
                  <textarea
                    name="answer"
                    placeholder="Type your answer..."
                    rows="3"
                    class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-xl outline-none transition-colors resize-none text-sm"
                  >{@selected_answer}</textarea>
                </form>
            <% end %>

            <div class="flex gap-3 mt-4">
              <button
                phx-click="next_card"
                class="flex-1 py-3 border border-[#E5E5EA] text-[#8E8E93] font-medium rounded-full touch-target transition-colors"
              >
                Cancel
              </button>
              <button
                phx-click="submit_answer"
                disabled={@selected_answer == nil}
                class={[
                  "flex-1 py-3 font-medium rounded-full shadow-md touch-target transition-colors",
                  if(@selected_answer,
                    do: "bg-[#4CD964] hover:bg-[#3DBF55] text-white",
                    else: "bg-[#E5E5EA] text-[#8E8E93] cursor-not-allowed"
                  )
                ]}
              >
                Submit
              </button>
            </div>
          </div>

          <%!-- Grading spinner (freeform async grading) --%>
          <div
            :if={@current_question && !@session_complete && @grading}
            class="w-full max-w-sm bg-white rounded-2xl shadow-lg p-5 flex flex-col items-center gap-3"
          >
            <div class="w-6 h-6 border-2 border-[#4CD964] border-t-transparent rounded-full animate-spin" />
            <p class="text-sm text-[#8E8E93]">Grading your answer...</p>
          </div>

          <%!-- Feedback phase (after answering or "don't know") --%>
          <div
            :if={
              @current_question && !@session_complete && @card_phase in [:feedback, :reveal] &&
                !@grading
            }
            id="quick-practice-confetti"
            phx-hook="ConfettiBurst"
            class="relative w-full max-w-sm bg-white rounded-2xl shadow-lg p-5 overflow-hidden"
          >
            <%!-- Result banner --%>
            <div
              :if={@card_phase == :feedback && @feedback}
              class={[
                "flex items-center gap-2 px-4 py-3 rounded-xl mb-4",
                if(@feedback.is_correct, do: "bg-[#E8F8EB]", else: "bg-red-50")
              ]}
            >
              <.icon
                name={if(@feedback.is_correct, do: "hero-check-circle", else: "hero-x-circle")}
                class={[
                  "w-6 h-6",
                  if(@feedback.is_correct, do: "text-[#4CD964]", else: "text-[#FF3B30]")
                ]}
              />
              <span class={[
                "font-bold text-sm",
                if(@feedback.is_correct, do: "text-[#4CD964]", else: "text-[#FF3B30]")
              ]}>
                {if @feedback.is_correct, do: "Correct!", else: "Not quite"}
              </span>
            </div>

            <div
              :if={@card_phase == :reveal}
              class="flex items-center gap-2 px-4 py-3 rounded-xl mb-4 bg-yellow-50"
            >
              <.icon name="hero-light-bulb" class="w-6 h-6 text-yellow-500" />
              <span class="font-bold text-sm text-yellow-700">Here's the answer</span>
            </div>

            <%!-- Question recap --%>
            <p class="text-sm text-[#8E8E93] mb-3 text-center">{@current_question.content}</p>

            <%!-- Rubric score badge — shown for premium users with scored grading --%>
            <.practice_score_badge
              :if={@feedback && @feedback[:grade_result]}
              grade_result={@feedback.grade_result}
            />

            <%!-- Free-user upsell for freeform questions --%>
            <div
              :if={
                @feedback && is_nil(@feedback[:grade_result]) &&
                  @current_question.question_type in [:short_answer, :free_response]
              }
              class="text-xs text-[#8E8E93] text-center mb-3"
            >
              <.link navigate={~p"/subscription"} class="text-[#4CD964] hover:underline">
                Upgrade to Premium for rubric scoring →
              </.link>
            </div>

            <%!-- Correct answer --%>
            <div class="bg-[#F5F5F7] rounded-xl p-4 mb-4 text-center">
              <p class="text-xs text-[#8E8E93] mb-1 uppercase tracking-wide font-medium">Answer</p>
              <p class="text-lg font-bold text-gray-900">
                {if @feedback, do: @feedback.correct_answer, else: @current_question.answer}
              </p>
            </div>

            <%!-- Community stats --%>
            <div
              :if={assigns[:current_question_stats] && @current_question_stats.total_attempts > 0}
              class="flex items-center justify-center gap-2 text-xs text-[#8E8E93] mb-4"
            >
              <.icon name="hero-users" class="w-4 h-4" />
              <span>
                <span class="font-bold">
                  {trunc(
                    if @current_question_stats.total_attempts > 0,
                      do:
                        @current_question_stats.correct_attempts /
                          @current_question_stats.total_attempts * 100,
                      else: 0
                  )}%
                </span>
                got this right
              </span>
            </div>

            <%!-- Video lessons (reveal phase only) --%>
            <.skill_videos :if={@card_phase == :reveal} videos={@current_question_videos} />

            <%!-- Tutor quick actions --%>
            <div class="flex items-center justify-center gap-2 flex-wrap mb-4">
              <button
                :if={@card_phase == :feedback && @feedback && !@feedback.is_correct}
                phx-click="tutor_quick_action"
                phx-value-action="why_wrong"
                class="inline-flex items-center gap-1 px-3 py-2 bg-white border border-[#E5E5EA] active:border-[#FF3B30] text-xs text-[#1C1C1E] rounded-full transition-colors touch-target"
              >
                <.icon name="hero-question-mark-circle" class="w-3.5 h-3.5 text-[#FF3B30]" />
                Why wrong?
              </button>
              <button
                phx-click="tutor_quick_action"
                phx-value-action="explain"
                class="inline-flex items-center gap-1 px-3 py-2 bg-white border border-[#E5E5EA] active:border-[#007AFF] text-xs text-[#1C1C1E] rounded-full transition-colors touch-target"
              >
                <.icon name="hero-academic-cap" class="w-3.5 h-3.5 text-[#007AFF]" /> Explain
              </button>
              <button
                phx-click="open_tutor"
                class="inline-flex items-center gap-1 px-3 py-2 bg-[#4CD964] active:bg-[#3DBF55] text-xs text-white font-medium rounded-full shadow-sm transition-colors touch-target"
              >
                <.icon name="hero-chat-bubble-left-right" class="w-3.5 h-3.5" /> Ask Tutor
              </button>
            </div>

            <%!-- Confidence buttons (feedback phase only — how well did you know it?) --%>
            <div :if={@card_phase == :feedback} class="mt-1">
              <p class="text-xs text-[#8E8E93] text-center mb-3 font-medium">
                How well did you know this?
              </p>
              <div class="flex gap-2">
                <button
                  phx-click="confidence_selected"
                  phx-value-confidence="dont_know"
                  class="flex-1 py-2.5 bg-gray-100 active:bg-gray-200 text-gray-600 text-xs font-semibold rounded-full transition-colors touch-target"
                >
                  I Don't Know
                </button>
                <button
                  phx-click="confidence_selected"
                  phx-value-confidence="not_sure"
                  class="flex-1 py-2.5 bg-yellow-50 active:bg-yellow-100 text-yellow-700 text-xs font-semibold rounded-full transition-colors touch-target"
                >
                  Not Sure
                </button>
                <button
                  phx-click="confidence_selected"
                  phx-value-confidence="i_know"
                  class="flex-1 py-2.5 bg-[#4CD964] active:bg-[#3DBF55] text-white text-xs font-bold rounded-full shadow-sm transition-colors touch-target"
                >
                  I Know
                </button>
              </div>
            </div>

            <%!-- Next button (reveal phase only — confidence already recorded at mark_not_sure/dont_know) --%>
            <button
              :if={@card_phase == :reveal}
              phx-click="next_card"
              class="w-full py-3 bg-[#4CD964] active:bg-[#3DBF55] text-white font-bold rounded-full shadow-md touch-target transition-colors"
            >
              Next Card
            </button>
          </div>

          <%!-- Session complete --%>
          <div
            :if={@session_complete && @summary}
            class="w-full max-w-sm bg-white rounded-2xl shadow-lg p-6 text-center"
          >
            <div class="text-5xl mb-3">🎉</div>
            <h2 class="text-2xl font-extrabold text-gray-900 mb-1">Session Done!</h2>
            <p class="text-sm text-[#8E8E93] mb-6">{@summary.total} cards reviewed</p>

            <div class="bg-[#F5F5F7] rounded-xl p-5 mb-5">
              <p class="text-4xl font-extrabold text-[#4CD964]">{@summary.score}%</p>
              <p class="text-xs text-[#8E8E93] mt-1">Score</p>
            </div>

            <div class="grid grid-cols-2 gap-2 mb-6">
              <div class="bg-[#E8F8EB] rounded-xl p-3">
                <p class="text-xl font-bold text-[#4CD964]">
                  {@summary.known + @summary.answered_correct}
                </p>
                <p class="text-[10px] text-[#8E8E93] font-medium">Got Right</p>
              </div>
              <div class="bg-red-50 rounded-xl p-3">
                <p class="text-xl font-bold text-[#FF3B30]">
                  {@summary.unknown + @summary.answered_wrong}
                </p>
                <p class="text-[10px] text-[#8E8E93] font-medium">Need Review</p>
              </div>
            </div>

            <div class="flex flex-col gap-3">
              <button
                phx-click="restart"
                class="w-full py-3 bg-[#4CD964] active:bg-[#3DBF55] text-white font-bold rounded-full shadow-md touch-target transition-colors"
              >
                Keep Practicing
              </button>
              <.link
                navigate={~p"/dashboard"}
                class="w-full py-3 border border-[#E5E5EA] text-[#1C1C1E] font-medium rounded-full text-center touch-target transition-colors active:bg-gray-50"
              >
                Back to Dashboard
              </.link>
            </div>
          </div>
        </div>

        <%!-- Bottom action buttons (accessibility fallback, only during swipe phase) --%>
        <div
          :if={@current_question && !@session_complete && @card_phase == :question}
          class="px-4 pb-4 pt-2 shrink-0 safe-area-bottom"
        >
          <%!-- 3-confidence row: Don't Know | Tap to Answer | Not Sure | I Know | Skip --%>
          <div class="flex items-center justify-center gap-3 max-w-sm mx-auto">
            <%!-- I Don't Know --%>
            <button
              phx-click="mark_dont_know"
              class="flex flex-col items-center gap-1 touch-target"
              aria-label="I don't know"
            >
              <span class="w-12 h-12 rounded-full bg-red-50 active:bg-red-100 flex items-center justify-center shadow-md transition-colors">
                <.icon name="hero-x-mark" class="w-6 h-6 text-[#FF3B30]" />
              </span>
              <span class="text-[9px] font-bold text-[#FF3B30] tracking-wide">NO IDEA</span>
            </button>

            <%!-- Not Sure --%>
            <button
              phx-click="mark_not_sure"
              class="flex flex-col items-center gap-1 touch-target"
              aria-label="Not sure"
            >
              <span class="w-12 h-12 rounded-full bg-yellow-50 active:bg-yellow-100 flex items-center justify-center shadow-md transition-colors">
                <.icon name="hero-question-mark-circle" class="w-6 h-6 text-yellow-500" />
              </span>
              <span class="text-[9px] font-bold text-yellow-600 tracking-wide">NOT SURE</span>
            </button>

            <%!-- Tap to Answer --%>
            <button
              phx-click="show_answer_input"
              class="flex flex-col items-center gap-1 touch-target"
              aria-label="Tap to answer"
            >
              <span class="w-16 h-16 rounded-full bg-[#007AFF] active:bg-[#0066DD] flex items-center justify-center shadow-lg transition-colors">
                <.icon name="hero-cursor-arrow-rays" class="w-8 h-8 text-white" />
              </span>
              <span class="text-[9px] font-bold text-[#007AFF] tracking-wide">ANSWER</span>
            </button>

            <%!-- I Know --%>
            <button
              phx-click="mark_i_know"
              class="flex flex-col items-center gap-1 touch-target"
              aria-label="I know this"
            >
              <span class="w-12 h-12 rounded-full bg-[#E8F8EB] active:bg-[#D0F0D8] flex items-center justify-center shadow-md transition-colors">
                <.icon name="hero-check" class="w-6 h-6 text-[#4CD964]" />
              </span>
              <span class="text-[9px] font-bold text-[#4CD964] tracking-wide">I KNOW</span>
            </button>

            <%!-- Skip --%>
            <button
              phx-click="skip"
              class="flex flex-col items-center gap-1 touch-target"
              aria-label="Skip"
            >
              <span class="w-10 h-10 rounded-full bg-[#F5F5F7] active:bg-gray-200 flex items-center justify-center transition-colors">
                <.icon name="hero-forward" class="w-5 h-5 text-[#8E8E93]" />
              </span>
            </button>
          </div>
        </div>

        <%!-- Tutor Chat Panel (bottom sheet) --%>
        <div
          :if={@tutor_open}
          class="fixed inset-x-0 bottom-0 z-50 bg-white border-t border-[#E5E5EA] shadow-xl rounded-t-2xl max-h-[60vh] flex flex-col safe-area-bottom"
          id="tutor-panel"
          phx-hook="ScrollBottom"
        >
          <div class="flex items-center justify-between px-4 py-3 border-b border-[#E5E5EA] shrink-0">
            <div class="flex items-center gap-2">
              <.icon name="hero-academic-cap" class="w-5 h-5 text-[#4CD964]" />
              <span class="font-bold text-sm text-gray-900">AI Tutor</span>
            </div>
            <button
              phx-click="close_tutor"
              class="p-2 text-[#8E8E93] touch-target"
              aria-label="Close tutor"
            >
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>

          <div class="flex-1 overflow-y-auto px-4 py-3 space-y-3" id="tutor-messages">
            <div :if={@tutor_messages == []} class="text-center text-sm text-[#8E8E93] py-6">
              Ask me anything about this question!
            </div>

            <div
              :for={msg <- @tutor_messages}
              class={["flex", if(msg.role == "user", do: "justify-end", else: "justify-start")]}
            >
              <div class={[
                "max-w-[85%] px-3 py-2.5 rounded-2xl text-sm leading-relaxed",
                if(msg.role == "user",
                  do: "bg-[#4CD964] text-white",
                  else: "bg-[#F5F5F7] text-[#1C1C1E]"
                )
              ]}>
                <.render_tutor_markdown content={msg.content} />
              </div>
            </div>

            <div :if={@tutor_loading} class="flex justify-start">
              <div class="bg-[#F5F5F7] px-4 py-3 rounded-2xl">
                <div class="flex gap-1">
                  <div
                    class="w-2 h-2 bg-[#8E8E93] rounded-full animate-bounce"
                    style="animation-delay: 0ms"
                  />
                  <div
                    class="w-2 h-2 bg-[#8E8E93] rounded-full animate-bounce"
                    style="animation-delay: 150ms"
                  />
                  <div
                    class="w-2 h-2 bg-[#8E8E93] rounded-full animate-bounce"
                    style="animation-delay: 300ms"
                  />
                </div>
              </div>
            </div>
          </div>

          <div class="px-4 py-3 border-t border-[#E5E5EA] shrink-0">
            <form phx-submit="tutor_send" class="flex gap-2">
              <input
                type="text"
                name="message"
                value={@tutor_input}
                phx-change="tutor_input"
                placeholder="Ask about this question..."
                autocomplete="off"
                class="flex-1 px-4 py-2.5 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none text-sm transition-colors"
              />
              <button
                type="submit"
                disabled={@tutor_loading || @tutor_input == ""}
                class={[
                  "p-2.5 rounded-full transition-colors touch-target",
                  if(@tutor_loading || @tutor_input == "",
                    do: "bg-[#E5E5EA] text-[#8E8E93]",
                    else: "bg-[#4CD964] active:bg-[#3DBF55] text-white shadow-md"
                  )
                ]}
                aria-label="Send message"
              >
                <.icon name="hero-paper-airplane" class="w-5 h-5" />
              </button>
            </form>
          </div>
        </div>
      </div>

      <%!-- Desktop practice layout (lg+) --%>
      <div class="hidden lg:flex flex-col items-center min-h-[calc(100vh-4rem)] bg-[#F5F5F7] px-6 py-8">
        <%!-- Header: title + streak + help --%>
        <div class="w-full max-w-2xl flex items-center justify-between mb-4">
          <div class="flex items-center gap-3">
            <h1 class="text-2xl font-bold text-gray-900">Practice</h1>
            <span
              :if={@session_streak >= 3}
              class="inline-flex items-center gap-0.5 px-2.5 py-1 bg-orange-50 rounded-full text-sm font-bold text-orange-600"
            >
              🔥 {@session_streak}
            </span>
          </div>
          <div class="flex items-center gap-3">
            <span class="text-sm font-medium text-[#8E8E93]">
              {@question_number}/{@total_questions}
            </span>
            <.help_button />
          </div>
        </div>

        <%!-- Upcoming tests pill row (desktop) --%>
        <.tests_pill_row
          :if={@upcoming_tests != []}
          upcoming_tests={@upcoming_tests}
          selected_test_id={@selected_test_id}
          selected_course_id={@selected_course_id}
          class="mb-4"
        />

        <%!-- Stats pills --%>
        <div :if={!@session_complete} class="flex items-center justify-center gap-4 mb-3">
          <span class="inline-flex items-center gap-1 text-sm font-bold text-[#4CD964]">
            <.icon name="hero-check-circle-mini" class="w-4 h-4" /> {@stats.correct}
          </span>
          <span class="inline-flex items-center gap-1 text-sm font-bold text-[#FF3B30]">
            <.icon name="hero-x-circle-mini" class="w-4 h-4" /> {@stats.incorrect}
          </span>
          <span class="inline-flex items-center gap-1 text-sm font-bold text-[#8E8E93]">
            <.icon name="hero-forward-mini" class="w-4 h-4" /> {@stats.skipped}
          </span>
        </div>

        <%!-- Progress bar --%>
        <div :if={!@session_complete} class="w-full max-w-2xl mb-6">
          <div class="w-full bg-gray-200 rounded-full h-1.5">
            <div
              class="bg-[#4CD964] h-1.5 rounded-full transition-all duration-300"
              style={"width: #{progress_pct(@question_number, @total_questions)}%"}
            />
          </div>
        </div>

        <%!-- Card area --%>
        <div class="w-full max-w-2xl flex-1 flex flex-col items-center justify-center">
          <%!-- Empty state --%>
          <div :if={@total_questions == 0 && !@session_complete} class="text-center py-16">
            <div class="text-7xl mb-4">🐑</div>
            <h2 class="text-2xl font-bold text-gray-900 mb-2">No Questions Yet</h2>
            <p class="text-base text-[#8E8E93] mb-6">
              Add courses and questions to start practicing.
            </p>
            <.link
              navigate={~p"/courses"}
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors inline-block"
            >
              Browse Courses
            </.link>
          </div>

          <%!-- Question card --%>
          <div
            :if={@current_question && !@session_complete && @card_phase == :question}
            class="w-full bg-white rounded-2xl shadow-lg p-8"
          >
            <div class="flex items-center gap-2 mb-4 flex-wrap">
              <span class="px-3 py-1 rounded-full text-xs font-bold bg-[#F5F5F7] text-[#8E8E93] uppercase tracking-wide">
                {course_name_for_question(@current_question, @courses)}
              </span>
              <span
                :if={@current_question.chapter}
                class="px-3 py-1 rounded-full text-xs font-bold bg-blue-50 text-[#007AFF]"
              >
                {String.slice(@current_question.chapter.name || "", 0..40)}
              </span>
              <span class="px-3 py-1 rounded-full text-xs font-bold bg-purple-50 text-purple-600">
                {question_type_label(@current_question.question_type)}
              </span>
            </div>

            <p class="text-xl font-semibold text-gray-900 leading-relaxed mb-6">
              {@current_question.content}
            </p>

            <div
              :if={@current_question.question_type == :multiple_choice && @current_question.options}
              class="space-y-2 mb-2"
            >
              <%= for {key, value} <- Enum.sort_by(@current_question.options || %{}, fn {k, _} -> k end) do %>
                <div class="flex items-start gap-2 px-4 py-3 bg-[#F5F5F7] rounded-xl text-base">
                  <span class="font-bold text-[#8E8E93] shrink-0">{key}.</span>
                  <span class="text-gray-800">{value}</span>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Answer input phase (desktop) --%>
          <div
            :if={@current_question && !@session_complete && @card_phase == :answering}
            class="w-full bg-white rounded-2xl shadow-lg p-8"
          >
            <p class="text-xl font-semibold text-gray-900 mb-6">
              {@current_question.content}
            </p>

            <%= case @current_question.question_type do %>
              <% :multiple_choice -> %>
                <div class="space-y-2">
                  <%= for {key, value} <- Enum.sort_by(@current_question.options || %{}, fn {k, _} -> k end) do %>
                    <button
                      type="button"
                      phx-click="select_answer"
                      phx-value-answer={key}
                      class={[
                        "w-full text-left px-4 py-3 rounded-xl border-2 transition-colors text-base",
                        if(@selected_answer == key,
                          do: "border-[#4CD964] bg-[#E8F8EB]",
                          else: "border-[#E5E5EA] hover:border-[#4CD964]"
                        )
                      ]}
                    >
                      <span class="font-bold text-[#1C1C1E]">{key}.</span>
                      <span class="ml-2 text-[#1C1C1E]">{value}</span>
                    </button>
                  <% end %>
                </div>
              <% :true_false -> %>
                <div class="flex gap-3">
                  <button
                    :for={value <- ["True", "False"]}
                    phx-click="select_answer"
                    phx-value-answer={value}
                    class={[
                      "flex-1 p-4 rounded-xl border-2 text-center font-medium text-base transition-colors",
                      if(@selected_answer == value,
                        do: "border-[#4CD964] bg-[#E8F8EB] text-[#4CD964]",
                        else: "border-[#E5E5EA] text-[#1C1C1E] hover:border-[#4CD964]"
                      )
                    ]}
                  >
                    {value}
                  </button>
                </div>
              <% _other -> %>
                <form phx-change="update_text_answer">
                  <textarea
                    name="answer"
                    placeholder="Type your answer..."
                    rows="4"
                    class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-xl outline-none transition-colors resize-none text-base"
                  >{@selected_answer}</textarea>
                </form>
            <% end %>

            <div class="flex gap-3 mt-6">
              <button
                phx-click="next_card"
                class="flex-1 py-3 border border-[#E5E5EA] text-[#8E8E93] font-medium rounded-full hover:bg-gray-50 transition-colors"
              >
                Cancel (Esc)
              </button>
              <button
                phx-click="submit_answer"
                disabled={@selected_answer == nil}
                class={[
                  "flex-1 py-3 font-medium rounded-full shadow-md transition-colors",
                  if(@selected_answer,
                    do: "bg-[#4CD964] hover:bg-[#3DBF55] text-white",
                    else: "bg-[#E5E5EA] text-[#8E8E93] cursor-not-allowed"
                  )
                ]}
              >
                Submit
              </button>
            </div>
          </div>

          <%!-- Grading spinner (desktop, freeform async grading) --%>
          <div
            :if={@current_question && !@session_complete && @grading}
            class="w-full bg-white rounded-2xl shadow-lg p-8 flex flex-col items-center gap-3"
          >
            <div class="w-8 h-8 border-2 border-[#4CD964] border-t-transparent rounded-full animate-spin" />
            <p class="text-base text-[#8E8E93]">Grading your answer...</p>
          </div>

          <%!-- Feedback phase (desktop) --%>
          <div
            :if={
              @current_question && !@session_complete && @card_phase in [:feedback, :reveal] &&
                !@grading
            }
            class="w-full bg-white rounded-2xl shadow-lg p-8"
          >
            <div
              :if={@card_phase == :feedback && @feedback}
              class={[
                "flex items-center gap-2 px-4 py-3 rounded-xl mb-4",
                if(@feedback.is_correct, do: "bg-[#E8F8EB]", else: "bg-red-50")
              ]}
            >
              <.icon
                name={if(@feedback.is_correct, do: "hero-check-circle", else: "hero-x-circle")}
                class={[
                  "w-6 h-6",
                  if(@feedback.is_correct, do: "text-[#4CD964]", else: "text-[#FF3B30]")
                ]}
              />
              <span class={[
                "font-bold",
                if(@feedback.is_correct, do: "text-[#4CD964]", else: "text-[#FF3B30]")
              ]}>
                {if @feedback.is_correct, do: "Correct!", else: "Not quite"}
              </span>
            </div>

            <div
              :if={@card_phase == :reveal}
              class="flex items-center gap-2 px-4 py-3 rounded-xl mb-4 bg-yellow-50"
            >
              <.icon name="hero-light-bulb" class="w-6 h-6 text-yellow-500" />
              <span class="font-bold text-yellow-700">Here's the answer</span>
            </div>

            <p class="text-base text-[#8E8E93] mb-4">{@current_question.content}</p>

            <%!-- Rubric score badge (desktop) --%>
            <.practice_score_badge
              :if={@feedback && @feedback[:grade_result]}
              grade_result={@feedback.grade_result}
            />

            <%!-- Free-user upsell for freeform questions (desktop) --%>
            <div
              :if={
                @feedback && is_nil(@feedback[:grade_result]) &&
                  @current_question.question_type in [:short_answer, :free_response]
              }
              class="text-sm text-[#8E8E93] mb-4"
            >
              <.link navigate={~p"/subscription"} class="text-[#4CD964] hover:underline">
                Upgrade to Premium for rubric scoring →
              </.link>
            </div>

            <div class="bg-[#F5F5F7] rounded-xl p-5 mb-4">
              <p class="text-xs text-[#8E8E93] mb-1 uppercase tracking-wide font-medium">Answer</p>
              <p class="text-xl font-bold text-gray-900">
                {if @feedback, do: @feedback.correct_answer, else: @current_question.answer}
              </p>
            </div>

            <%!-- Video lessons (reveal phase only, desktop) --%>
            <.skill_videos :if={@card_phase == :reveal} videos={@current_question_videos} />

            <div class="flex items-center gap-2 flex-wrap mb-4">
              <button
                :if={@card_phase == :feedback && @feedback && !@feedback.is_correct}
                phx-click="tutor_quick_action"
                phx-value-action="why_wrong"
                class="inline-flex items-center gap-1 px-4 py-2 bg-white border border-[#E5E5EA] hover:border-[#FF3B30] text-sm text-[#1C1C1E] rounded-full transition-colors"
              >
                <.icon name="hero-question-mark-circle" class="w-4 h-4 text-[#FF3B30]" /> Why wrong?
              </button>
              <button
                phx-click="tutor_quick_action"
                phx-value-action="explain"
                class="inline-flex items-center gap-1 px-4 py-2 bg-white border border-[#E5E5EA] hover:border-[#007AFF] text-sm text-[#1C1C1E] rounded-full transition-colors"
              >
                <.icon name="hero-academic-cap" class="w-4 h-4 text-[#007AFF]" /> Explain
              </button>
              <button
                phx-click="open_tutor"
                class="inline-flex items-center gap-1 px-4 py-2 bg-[#4CD964] hover:bg-[#3DBF55] text-sm text-white font-medium rounded-full shadow-sm transition-colors"
              >
                <.icon name="hero-chat-bubble-left-right" class="w-4 h-4" /> Ask Tutor
              </button>
            </div>

            <%!-- Confidence buttons (feedback phase only) --%>
            <div :if={@card_phase == :feedback} class="mt-1">
              <p class="text-sm text-[#8E8E93] text-center mb-3 font-medium">
                How well did you know this?
              </p>
              <div class="flex gap-3">
                <button
                  phx-click="confidence_selected"
                  phx-value-confidence="dont_know"
                  class="flex-1 py-3 bg-gray-100 hover:bg-gray-200 text-gray-600 text-sm font-semibold rounded-full transition-colors"
                >
                  I Don't Know
                </button>
                <button
                  phx-click="confidence_selected"
                  phx-value-confidence="not_sure"
                  class="flex-1 py-3 bg-yellow-50 hover:bg-yellow-100 text-yellow-700 text-sm font-semibold rounded-full transition-colors"
                >
                  Not Sure
                </button>
                <button
                  phx-click="confidence_selected"
                  phx-value-confidence="i_know"
                  class="flex-1 py-3 bg-[#4CD964] hover:bg-[#3DBF55] text-white text-sm font-bold rounded-full shadow-sm transition-colors"
                >
                  I Know (→)
                </button>
              </div>
            </div>

            <%!-- Next button (reveal phase only) --%>
            <button
              :if={@card_phase == :reveal}
              phx-click="next_card"
              class="w-full py-3 bg-[#4CD964] hover:bg-[#3DBF55] text-white font-bold rounded-full shadow-md transition-colors"
            >
              Next Card (→)
            </button>
          </div>

          <%!-- Session complete (desktop) --%>
          <div
            :if={@session_complete && @summary}
            class="w-full bg-white rounded-2xl shadow-lg p-8 text-center"
          >
            <div class="text-6xl mb-3">🎉</div>
            <h2 class="text-3xl font-extrabold text-gray-900 mb-1">Session Done!</h2>
            <p class="text-base text-[#8E8E93] mb-6">{@summary.total} cards reviewed</p>

            <div class="bg-[#F5F5F7] rounded-xl p-6 mb-6">
              <p class="text-5xl font-extrabold text-[#4CD964]">{@summary.score}%</p>
              <p class="text-sm text-[#8E8E93] mt-1">Score</p>
            </div>

            <div class="grid grid-cols-2 gap-3 mb-6">
              <div class="bg-[#E8F8EB] rounded-xl p-4">
                <p class="text-2xl font-bold text-[#4CD964]">
                  {@summary.known + @summary.answered_correct}
                </p>
                <p class="text-xs text-[#8E8E93] font-medium">Got Right</p>
              </div>
              <div class="bg-red-50 rounded-xl p-4">
                <p class="text-2xl font-bold text-[#FF3B30]">
                  {@summary.unknown + @summary.answered_wrong}
                </p>
                <p class="text-xs text-[#8E8E93] font-medium">Need Review</p>
              </div>
            </div>

            <div class="flex gap-3">
              <button
                phx-click="restart"
                class="flex-1 py-3 bg-[#4CD964] hover:bg-[#3DBF55] text-white font-bold rounded-full shadow-md transition-colors"
              >
                Keep Practicing
              </button>
              <.link
                navigate={~p"/dashboard"}
                class="flex-1 py-3 border border-[#E5E5EA] text-[#1C1C1E] font-medium rounded-full text-center hover:bg-gray-50 transition-colors"
              >
                Dashboard
              </.link>
            </div>
          </div>
        </div>

        <%!-- Desktop bottom action buttons + keyboard hint --%>
        <div
          :if={@current_question && !@session_complete && @card_phase == :question}
          class="w-full max-w-2xl mt-6 flex flex-col items-center gap-3"
        >
          <%!-- 3-confidence row: I Don't Know | Not Sure | Answer | I Know | Skip --%>
          <div class="flex items-center justify-center gap-4">
            <button
              phx-click="mark_dont_know"
              class="flex flex-col items-center gap-1"
              aria-label="I don't know"
            >
              <span class="w-14 h-14 rounded-full bg-red-50 hover:bg-red-100 flex items-center justify-center shadow-md transition-colors">
                <.icon name="hero-x-mark" class="w-7 h-7 text-[#FF3B30]" />
              </span>
              <span class="text-[10px] font-bold text-[#FF3B30] tracking-wide">NO IDEA (←)</span>
            </button>

            <button
              phx-click="mark_not_sure"
              class="flex flex-col items-center gap-1"
              aria-label="Not sure"
            >
              <span class="w-12 h-12 rounded-full bg-yellow-50 hover:bg-yellow-100 flex items-center justify-center shadow-md transition-colors">
                <.icon name="hero-question-mark-circle" class="w-6 h-6 text-yellow-500" />
              </span>
              <span class="text-[10px] font-bold text-yellow-600 tracking-wide">NOT SURE</span>
            </button>

            <button
              phx-click="show_answer_input"
              class="flex flex-col items-center gap-1"
              aria-label="Tap to answer"
            >
              <span class="w-16 h-16 rounded-full bg-[#007AFF] hover:bg-[#0066DD] flex items-center justify-center shadow-lg transition-colors">
                <.icon name="hero-cursor-arrow-rays" class="w-8 h-8 text-white" />
              </span>
              <span class="text-[10px] font-bold text-[#007AFF] tracking-wide">ANSWER (Space)</span>
            </button>

            <button
              phx-click="mark_i_know"
              class="flex flex-col items-center gap-1"
              aria-label="I know this"
            >
              <span class="w-14 h-14 rounded-full bg-[#E8F8EB] hover:bg-[#D0F0D8] flex items-center justify-center shadow-md transition-colors">
                <.icon name="hero-check" class="w-7 h-7 text-[#4CD964]" />
              </span>
              <span class="text-[10px] font-bold text-[#4CD964] tracking-wide">I KNOW (→)</span>
            </button>

            <button
              phx-click="skip"
              class="flex flex-col items-center gap-1"
              aria-label="Skip"
            >
              <span class="w-12 h-12 rounded-full bg-[#F5F5F7] hover:bg-gray-200 flex items-center justify-center transition-colors">
                <.icon name="hero-forward" class="w-5 h-5 text-[#8E8E93]" />
              </span>
              <span class="text-[10px] font-bold text-[#8E8E93] tracking-wide">SKIP (↑)</span>
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Function components ──

  attr :upcoming_tests, :list, required: true
  attr :selected_test_id, :any, required: true
  attr :selected_course_id, :any, required: true
  attr :class, :string, default: ""

  defp tests_pill_row(assigns) do
    ~H"""
    <div class={["w-full overflow-x-auto scrollbar-hide px-4 py-2 shrink-0", @class]}>
      <div class="flex items-center gap-2 min-w-max lg:justify-center">
        <.link
          :for={test <- @upcoming_tests}
          patch={~p"/practice?test_id=#{test.id}"}
          class={[
            "inline-flex items-center gap-1 px-3 py-1.5 rounded-full text-xs font-bold whitespace-nowrap transition-colors shrink-0",
            if(test.id == @selected_test_id,
              do: "bg-[#4CD964] text-white shadow-sm",
              else: "bg-white border border-[#E5E5EA] text-[#1C1C1E] hover:border-[#4CD964]"
            )
          ]}
        >
          {pill_label(test)}
        </.link>
      </div>
    </div>
    """
  end

  defp help_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="replay_tutorial"
      class="w-6 h-6 rounded-full border border-[#E5E5EA] text-[#8E8E93] hover:text-[#4CD964] hover:border-[#4CD964] flex items-center justify-center text-[11px] font-bold transition-colors"
      aria-label="Show tutorial"
      title="Show tutorial"
    >
      ?
    </button>
    """
  end

  defp tutorial_overlay(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-[60] bg-black/70 backdrop-blur-sm flex items-center justify-center p-4"
      phx-click="dismiss_tutorial"
    >
      <div
        class="w-full max-w-md bg-white rounded-2xl shadow-2xl p-6 space-y-4"
        onclick="event.stopPropagation()"
      >
        <div class="flex items-center justify-between">
          <h2 class="text-xl font-extrabold text-gray-900">How Practice works</h2>
          <button
            type="button"
            phx-click="dismiss_tutorial"
            class="p-1 text-[#8E8E93] hover:text-gray-700"
            aria-label="Close tutorial"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <p class="text-sm text-[#8E8E93]">
          Swipe (on mobile) or use keyboard arrows (on desktop) to rate each card.
        </p>

        <ul class="space-y-3">
          <li class="flex items-center gap-3 p-3 bg-[#E8F8EB] rounded-xl">
            <span class="text-2xl animate-swipe-right">👉</span>
            <div class="flex-1">
              <p class="font-bold text-[#4CD964]">Swipe right / →</p>
              <p class="text-xs text-gray-700">I know this</p>
            </div>
          </li>
          <li class="flex items-center gap-3 p-3 bg-red-50 rounded-xl">
            <span class="text-2xl animate-swipe-left">👈</span>
            <div class="flex-1">
              <p class="font-bold text-[#FF3B30]">Swipe left / ←</p>
              <p class="text-xs text-gray-700">I need to learn this</p>
            </div>
          </li>
          <li class="flex items-center gap-3 p-3 bg-gray-50 rounded-xl">
            <span class="text-2xl animate-swipe-up">👆</span>
            <div class="flex-1">
              <p class="font-bold text-[#8E8E93]">Swipe up / ↑</p>
              <p class="text-xs text-gray-700">Skip for now</p>
            </div>
          </li>
          <li class="flex items-center gap-3 p-3 bg-blue-50 rounded-xl">
            <span class="text-2xl">☝️</span>
            <div class="flex-1">
              <p class="font-bold text-[#007AFF]">Tap / Space</p>
              <p class="text-xs text-gray-700">Answer the question</p>
            </div>
          </li>
        </ul>

        <button
          type="button"
          phx-click="dismiss_tutorial"
          class="w-full py-3 bg-[#4CD964] hover:bg-[#3DBF55] text-white font-bold rounded-full shadow-md transition-colors"
        >
          Got it!
        </button>
      </div>
    </div>
    """
  end

  # ── Score badge component ──

  attr :grade_result, :map, required: true

  defp practice_score_badge(assigns) do
    score = assigns.grade_result.score

    {color, label} =
      cond do
        score <= 4 -> {"#FF3B30", practice_score_label(score)}
        score <= 6 -> {"#FFCC00", practice_score_label(score)}
        true -> {"#4CD964", practice_score_label(score)}
      end

    assigns =
      assign(assigns,
        score_color: color,
        score_label: label
      )

    ~H"""
    <div class="rounded-2xl border border-[#E5E5EA] p-3 mb-4">
      <div class="text-xl font-bold" style={"color: #{@score_color};"}>
        {@grade_result.score} / {@grade_result.max_score} · {@score_label}
      </div>
      <p :if={@grade_result.feedback} class="text-sm text-gray-700 mt-1">
        {@grade_result.feedback}
      </p>
      <p :if={@grade_result.improvement_hint} class="text-xs text-[#8E8E93] mt-2">
        💡 {@grade_result.improvement_hint}
      </p>
    </div>
    """
  end

  defp practice_score_label(score) when score == 0, do: "No Credit"
  defp practice_score_label(score) when score in 1..3, do: "Minimal"
  defp practice_score_label(score) when score in 4..6, do: "Partial Credit"
  defp practice_score_label(score) when score in 7..8, do: "Mostly Correct"
  defp practice_score_label(score) when score in 9..10, do: "Full Credit"
  defp practice_score_label(_), do: "Scored"

  # ── Inline video reference chips ──

  defp skill_videos(%{videos: []} = assigns), do: ~H""

  defp skill_videos(assigns) do
    ~H"""
    <div class="mt-3 p-3 rounded-2xl bg-blue-50 border border-blue-100">
      <p class="text-xs font-bold text-[#007AFF] uppercase tracking-wider mb-2 flex items-center gap-1.5">
        <.icon name="hero-video-camera" class="w-4 h-4" /> Watch & Learn
      </p>
      <ul class="space-y-1.5">
        <li :for={video <- @videos}>
          <.link
            href={video.url}
            target="_blank"
            rel="noopener"
            class="text-sm text-[#007AFF] hover:underline inline-flex items-center gap-1"
          >
            <.icon name="hero-play-circle" class="w-4 h-4 shrink-0" />
            <span class="truncate">{video.title}</span>
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  # ── Tutor markdown renderer ──

  attr :content, :string, required: true

  defp render_tutor_markdown(assigns) do
    html =
      assigns.content
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()
      |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
      |> String.replace("\n", "<br/>")

    assigns = assign(assigns, :html, html)

    ~H"""
    <span>{Phoenix.HTML.raw(@html)}</span>
    """
  end
end
