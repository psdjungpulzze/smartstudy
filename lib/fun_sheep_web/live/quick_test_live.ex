defmodule FunSheepWeb.QuickTestLive do
  use FunSheepWeb, :live_view

  import FunSheepWeb.BillingComponents

  alias FunSheep.{Billing, Content, Courses, Engagement, Gamification, Questions, Tutor}
  alias FunSheep.Assessments.QuickTestEngine
  alias FunSheep.Gamification.FpEconomy

  @xp_per_correct FpEconomy.xp_per_correct()

  @impl true
  def mount(%{"course_id" => course_id}, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    role = socket.assigns.current_user["role"]
    course = Courses.get_course!(course_id)

    case Billing.check_test_allowance(user_role_id, role) do
      :ok ->
        Billing.record_test_usage(user_role_id, "quick_test", course_id)

        state = QuickTestEngine.start_session(user_role_id, %{course_id: course_id})
        total_questions = length(state.questions)

        socket =
          socket
          |> assign(
            page_title: "Quick Test - #{course.name}",
            course: course,
            course_id: course_id,
            billing_blocked: false,
            billing_stats: nil,
            engine_state: state,
            current_question: nil,
            selected_answer: nil,
            show_explanation: false,
            show_answer_input: false,
            feedback: nil,
            question_number: 0,
            total_questions: total_questions,
            test_complete: false,
            summary: nil,
            stats: %{correct: 0, incorrect: 0, skipped: 0},
            pending_is_correct: nil,
            pending_answer: nil,
            # Remediation videos for current skill (I-14). Populated only on
            # wrong-answer / "I don't know" events.
            current_question_videos: [],
            # Tutor state
            tutor_open: false,
            tutor_session_id: nil,
            tutor_messages: [],
            tutor_loading: false,
            tutor_input: ""
          )
          |> advance_to_next_card()

        {:ok, socket}

      {:error, :limit_reached, _info} ->
        billing_stats = Billing.usage_stats(user_role_id)

        socket =
          socket
          |> assign(
            page_title: "Quick Test - #{course.name}",
            course: course,
            course_id: course_id,
            billing_blocked: true,
            billing_stats: billing_stats,
            engine_state: nil,
            current_question: nil,
            selected_answer: nil,
            show_explanation: false,
            show_answer_input: false,
            feedback: nil,
            question_number: 0,
            total_questions: 0,
            test_complete: false,
            summary: nil,
            stats: %{correct: 0, incorrect: 0, skipped: 0},
            current_question_videos: [],
            tutor_open: false,
            tutor_session_id: nil,
            tutor_messages: [],
            tutor_loading: false,
            tutor_input: ""
          )

        {:ok, socket}
    end
  end

  @impl true
  # Confidence-based flashcard handlers (I-17)

  def handle_event("mark_i_know", _params, socket) do
    %{current_question: question, engine_state: state, stats: stats} = socket.assigns

    if question do
      record_attempt(socket, question, "known", true, :i_know)
      new_state = QuickTestEngine.mark_known(state, question.id)

      socket =
        socket
        |> assign(
          engine_state: new_state,
          stats: %{stats | correct: stats.correct + 1},
          show_explanation: false,
          show_answer_input: false,
          feedback: nil,
          selected_answer: nil
        )
        |> advance_to_next_card()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("mark_not_sure", _params, socket) do
    %{current_question: question, engine_state: state, stats: stats} = socket.assigns

    if question do
      record_attempt(socket, question, "not_sure", false, :not_sure)
      new_state = QuickTestEngine.mark_unknown(state, question.id)

      {:noreply,
       assign(socket,
         engine_state: new_state,
         show_explanation: true,
         stats: %{stats | incorrect: stats.incorrect + 1},
         current_question_videos: Content.list_videos_for_section(question.section_id)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("mark_dont_know", _params, socket) do
    %{current_question: question, engine_state: state, stats: stats} = socket.assigns

    if question do
      record_attempt(socket, question, "dont_know", false, :dont_know)
      new_state = QuickTestEngine.mark_unknown(state, question.id)

      {:noreply,
       assign(socket,
         engine_state: new_state,
         show_explanation: true,
         stats: %{stats | incorrect: stats.incorrect + 1},
         current_question_videos: Content.list_videos_for_section(question.section_id)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("dismiss_explanation", _params, socket) do
    socket =
      socket
      |> assign(
        show_explanation: false,
        show_answer_input: false,
        feedback: nil,
        selected_answer: nil
      )
      |> reset_tutor()
      |> advance_to_next_card()

    {:noreply, socket}
  end

  def handle_event("show_answer_input", _params, socket) do
    {:noreply, assign(socket, show_answer_input: true)}
  end

  def handle_event("select_answer", %{"answer" => answer}, socket) do
    {:noreply, assign(socket, selected_answer: answer)}
  end

  def handle_event("update_text_answer", %{"answer" => answer}, socket) do
    {:noreply, assign(socket, selected_answer: answer)}
  end

  def handle_event("submit_answer", _params, socket) do
    %{
      current_question: question,
      selected_answer: answer,
      engine_state: state,
      stats: stats
    } = socket.assigns

    if answer == nil or question == nil do
      {:noreply, socket}
    else
      is_correct = check_answer(question, answer)
      new_state = QuickTestEngine.mark_answered(state, question.id, is_correct)

      new_stats =
        if is_correct do
          %{stats | correct: stats.correct + 1}
        else
          %{stats | incorrect: stats.incorrect + 1}
        end

      videos =
        if is_correct,
          do: [],
          else: Content.list_videos_for_section(question.section_id)

      # Defer DB insert until confidence is selected
      {:noreply,
       assign(socket,
         engine_state: new_state,
         stats: new_stats,
         feedback: %{is_correct: is_correct, correct_answer: question.answer},
         pending_is_correct: is_correct,
         pending_answer: answer,
         current_question_videos: videos
       )}
    end
  end

  def handle_event("confidence_selected", %{"confidence" => confidence_str}, socket) do
    %{current_question: question, pending_is_correct: is_correct, pending_answer: answer} =
      socket.assigns

    confidence = String.to_existing_atom(confidence_str)

    if question && not is_nil(is_correct) do
      record_attempt(socket, question, answer || "unknown", is_correct, confidence)
    end

    socket =
      socket
      |> assign(
        show_answer_input: false,
        feedback: nil,
        selected_answer: nil,
        show_explanation: false,
        pending_is_correct: nil,
        pending_answer: nil
      )
      |> reset_tutor()
      |> advance_to_next_card()

    {:noreply, socket}
  end

  def handle_event("next_after_answer", _params, socket) do
    socket =
      socket
      |> assign(
        show_answer_input: false,
        feedback: nil,
        selected_answer: nil,
        show_explanation: false
      )
      |> reset_tutor()
      |> advance_to_next_card()

    {:noreply, socket}
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
          show_explanation: false,
          show_answer_input: false,
          feedback: nil,
          selected_answer: nil
        )
        |> advance_to_next_card()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("restart", _params, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]

    state = QuickTestEngine.start_session(user_role_id, %{course_id: socket.assigns.course_id})
    total_questions = length(state.questions)

    socket =
      socket
      |> assign(
        engine_state: state,
        current_question: nil,
        selected_answer: nil,
        show_explanation: false,
        show_answer_input: false,
        feedback: nil,
        question_number: 0,
        total_questions: total_questions,
        test_complete: false,
        summary: nil,
        stats: %{correct: 0, incorrect: 0, skipped: 0}
      )
      |> advance_to_next_card()

    {:noreply, socket}
  end

  # --- Tutor events ---

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

  @impl true
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

  def handle_info({:tutor_response, _response}, socket) do
    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp ensure_tutor_session(socket) do
    if socket.assigns.tutor_session_id do
      socket
    else
      question = socket.assigns.current_question
      user_role_id = socket.assigns.current_user["user_role_id"]
      course_id = socket.assigns.course_id

      if question && user_role_id do
        case Tutor.start_session(user_role_id, question.id, course_id) do
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

  defp tutor_action_label(action) do
    case action do
      "hint" -> "Give me a hint"
      "explain" -> "Explain this concept"
      "why_wrong" -> "Why was I wrong?"
      "step_by_step" -> "Walk me through it step by step"
      "similar" -> "Give me a similar question"
      _ -> action
    end
  end

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

  defp advance_to_next_card(socket) do
    state = socket.assigns.engine_state

    case QuickTestEngine.current_card(state) do
      {:card, question, new_state} ->
        question_stats = Questions.get_question_stats(question.id)

        assign(socket,
          engine_state: new_state,
          current_question: question,
          current_question_stats: question_stats,
          current_question_videos: [],
          question_number: socket.assigns.question_number + 1
        )

      {:complete, new_state} ->
        summary = QuickTestEngine.summary(new_state)
        finalize_session(socket)

        assign(socket,
          engine_state: new_state,
          current_question: nil,
          test_complete: true,
          summary: summary
        )
    end
  end

  defp finalize_session(socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    course_id = socket.assigns.course_id

    if user_role_id && course_id do
      Engagement.after_session(user_role_id, course_id)
    end

    :ok
  end

  defp check_answer(question, answer), do: FunSheep.Questions.Grading.correct?(question, answer)

  defp record_attempt(socket, question, answer_given, is_correct, confidence) do
    user_role_id = socket.assigns.current_user["user_role_id"]

    if user_role_id do
      Questions.record_attempt_with_stats(%{
        user_role_id: user_role_id,
        question_id: question.id,
        answer_given: answer_given,
        is_correct: is_correct,
        difficulty_at_attempt: to_string(question.difficulty),
        confidence: confidence
      })

      if is_correct do
        Gamification.award_xp(user_role_id, @xp_per_correct, "quick_test", source_id: question.id)
      end

      Gamification.record_activity(user_role_id)
    end
  end

  defp question_type_label(type) do
    case type do
      :multiple_choice -> "MCQ"
      :true_false -> "True/False"
      :short_answer -> "Short Answer"
      :free_response -> "Free Response"
      _ -> "Question"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto pb-20">
      <%!-- Billing limit reached --%>
      <.billing_wall
        :if={@billing_blocked}
        course_id={@course_id}
        course_name={@course.name}
        stats={@billing_stats}
      />

      <div :if={!@billing_blocked}>
        <%!-- Header with stats --%>
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-4">
            <button
              type="button"
              onclick="history.back()"
              class="text-[#8E8E93] hover:text-[#1C1C1E] transition-colors cursor-pointer"
              aria-label="Go back"
            >
              <.icon name="hero-arrow-left" class="w-6 h-6" />
            </button>
            <div>
              <h1 class="text-2xl font-bold text-[#1C1C1E]">Quick Test</h1>
              <p class="text-sm text-[#8E8E93]">{@course.name}</p>
            </div>
          </div>

          <div :if={!@test_complete} class="text-sm text-[#8E8E93]">
            {@question_number} / {@total_questions}
          </div>
        </div>

        <%!-- Stats bar --%>
        <div :if={!@test_complete} class="flex items-center gap-4 mb-4 text-sm">
          <span class="text-[#4CD964] font-medium">
            <.icon name="hero-check" class="w-4 h-4 inline" /> {@stats.correct}
          </span>
          <span class="text-[#FF3B30] font-medium">
            <.icon name="hero-x-mark" class="w-4 h-4 inline" /> {@stats.incorrect}
          </span>
          <span class="text-[#8E8E93] font-medium">
            <.icon name="hero-arrow-right" class="w-4 h-4 inline" /> {@stats.skipped}
          </span>
        </div>

        <%!-- No questions state --%>
        <div
          :if={@total_questions == 0 and !@test_complete}
          class="bg-white rounded-2xl shadow-md p-8 text-center"
        >
          <.icon name="hero-academic-cap" class="w-16 h-16 text-[#4CD964] mx-auto mb-4" />
          <h2 class="text-xl font-bold text-[#1C1C1E] mb-2">No Questions Available</h2>
          <p class="text-[#8E8E93] mb-6">
            Add some courses and questions to start your quick test session.
          </p>
          <.link
            navigate={~p"/courses/#{@course_id}"}
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Go to Course Page
          </.link>
        </div>

        <%!-- Card --%>
        <div :if={@current_question && !@test_complete} class="relative">
          <%!-- Skip button --%>
          <button
            phx-click="skip"
            class="absolute top-4 right-4 text-[#8E8E93] hover:text-[#1C1C1E] transition-colors z-10"
            title="Skip"
          >
            <.icon name="hero-forward" class="w-5 h-5" />
          </button>

          <div class="bg-white rounded-2xl shadow-lg p-5 sm:p-8 min-h-[220px] sm:min-h-[300px] flex flex-col">
            <%!-- Tags --%>
            <div class="flex items-center gap-2 mb-6">
              <span
                :if={@current_question.chapter}
                class="px-3 py-1 rounded-full text-xs font-medium bg-[#F5F5F7] text-[#8E8E93]"
              >
                {@current_question.chapter.name}
              </span>
              <span class="px-3 py-1 rounded-full text-xs font-medium bg-blue-50 text-[#007AFF]">
                {question_type_label(@current_question.question_type)}
              </span>
            </div>

            <%!-- Question content --%>
            <div class="flex-1 flex items-center justify-center mb-6">
              <p class="text-lg text-[#1C1C1E] font-medium leading-relaxed text-center">
                {@current_question.content}
              </p>
            </div>

            <%!-- MCQ options (shown when answering) --%>
            <div :if={@show_answer_input} class="mb-6">
              <%= case @current_question.question_type do %>
                <% :multiple_choice -> %>
                  <.render_mcq_options
                    question={@current_question}
                    selected_answer={@selected_answer}
                    feedback={@feedback}
                  />
                <% :true_false -> %>
                  <.render_true_false
                    selected_answer={@selected_answer}
                    feedback={@feedback}
                  />
                <% _other -> %>
                  <.render_text_input
                    selected_answer={@selected_answer}
                    feedback={@feedback}
                  />
              <% end %>

              <%!-- Submit / Next after answer --%>
              <div :if={@feedback == nil} class="flex justify-center mt-4">
                <button
                  phx-click="submit_answer"
                  disabled={@selected_answer == nil}
                  class={[
                    "font-medium px-6 py-2 rounded-full shadow-md transition-colors",
                    if(@selected_answer,
                      do: "bg-[#4CD964] hover:bg-[#3DBF55] text-white",
                      else: "bg-[#E5E5EA] text-[#8E8E93] cursor-not-allowed"
                    )
                  ]}
                >
                  Submit
                </button>
              </div>

              <div :if={@feedback} class="mt-4">
                <div class={[
                  "p-3 rounded-xl flex items-center gap-3 mb-4",
                  if(@feedback.is_correct, do: "bg-[#E8F8EB]", else: "bg-red-50")
                ]}>
                  <.icon
                    name={if(@feedback.is_correct, do: "hero-check-circle", else: "hero-x-circle")}
                    class={[
                      "w-5 h-5",
                      if(@feedback.is_correct, do: "text-[#4CD964]", else: "text-[#FF3B30]")
                    ]}
                  />
                  <p class={[
                    "font-medium text-sm",
                    if(@feedback.is_correct, do: "text-[#4CD964]", else: "text-[#FF3B30]")
                  ]}>
                    {if @feedback.is_correct,
                      do: "Correct!",
                      else: "Incorrect - Answer: #{@feedback.correct_answer}"}
                  </p>
                </div>
                <.render_community_stats
                  :if={assigns[:current_question_stats]}
                  stats={assigns[:current_question_stats]}
                />
                <.skill_videos :if={!@feedback.is_correct} videos={@current_question_videos} />
                <%!-- Tutor actions after answering --%>
                <div class="flex items-center gap-2 flex-wrap mb-3">
                  <button
                    :if={!@feedback.is_correct}
                    phx-click="tutor_quick_action"
                    phx-value-action="why_wrong"
                    class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-white border border-[#E5E5EA] hover:border-[#FF3B30] text-xs text-[#1C1C1E] rounded-full transition-colors"
                  >
                    <.icon name="hero-question-mark-circle" class="w-3.5 h-3.5 text-[#FF3B30]" />
                    Why wrong?
                  </button>
                  <button
                    phx-click="tutor_quick_action"
                    phx-value-action="explain"
                    class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-white border border-[#E5E5EA] hover:border-[#4CD964] text-xs text-[#1C1C1E] rounded-full transition-colors"
                  >
                    <.icon name="hero-academic-cap" class="w-3.5 h-3.5 text-[#007AFF]" /> Explain
                  </button>
                  <button
                    phx-click="open_tutor"
                    class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-[#4CD964] hover:bg-[#3DBF55] text-xs text-white font-medium rounded-full shadow-sm transition-colors"
                  >
                    <.icon name="hero-chat-bubble-left-right" class="w-3.5 h-3.5" /> Ask Tutor
                  </button>
                </div>
                <%!-- Confidence buttons — replace "Next Card" --%>
                <p class="text-xs text-[#8E8E93] text-center mb-2 font-medium">
                  How well did you know this?
                </p>
                <div class="flex gap-2">
                  <button
                    phx-click="confidence_selected"
                    phx-value-confidence="dont_know"
                    class="flex-1 py-2 bg-gray-100 hover:bg-gray-200 text-gray-600 text-xs font-semibold rounded-full transition-colors"
                  >
                    I Don't Know
                  </button>
                  <button
                    phx-click="confidence_selected"
                    phx-value-confidence="not_sure"
                    class="flex-1 py-2 bg-yellow-50 hover:bg-yellow-100 text-yellow-700 text-xs font-semibold rounded-full transition-colors"
                  >
                    Not Sure
                  </button>
                  <button
                    phx-click="confidence_selected"
                    phx-value-confidence="i_know"
                    class="flex-1 py-2 bg-[#4CD964] hover:bg-[#3DBF55] text-white text-xs font-bold rounded-full shadow-sm transition-colors"
                  >
                    I Know
                  </button>
                </div>
              </div>
            </div>

            <%!-- Explanation overlay (for "I Don't Know") --%>
            <div :if={@show_explanation} class="mb-6">
              <div class="bg-yellow-50 rounded-xl p-4 border border-yellow-200">
                <p class="text-sm font-medium text-yellow-800 mb-2">Correct Answer:</p>
                <p class="text-[#1C1C1E] font-medium">{@current_question.answer}</p>
              </div>
              <.render_community_stats
                :if={assigns[:current_question_stats]}
                stats={assigns[:current_question_stats]}
              />
              <.skill_videos videos={@current_question_videos} />
              <%!-- Tutor actions after "I Don't Know" --%>
              <div class="flex items-center gap-2 flex-wrap mt-3 mb-3">
                <button
                  phx-click="tutor_quick_action"
                  phx-value-action="explain"
                  class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-white border border-[#E5E5EA] hover:border-[#4CD964] text-xs text-[#1C1C1E] rounded-full transition-colors"
                >
                  <.icon name="hero-academic-cap" class="w-3.5 h-3.5 text-[#007AFF]" /> Explain
                </button>
                <button
                  phx-click="tutor_quick_action"
                  phx-value-action="step_by_step"
                  class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-white border border-[#E5E5EA] hover:border-[#4CD964] text-xs text-[#1C1C1E] rounded-full transition-colors"
                >
                  <.icon name="hero-list-bullet" class="w-3.5 h-3.5 text-[#8E8E93]" /> Step by step
                </button>
                <button
                  phx-click="open_tutor"
                  class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-[#4CD964] hover:bg-[#3DBF55] text-xs text-white font-medium rounded-full shadow-sm transition-colors"
                >
                  <.icon name="hero-chat-bubble-left-right" class="w-3.5 h-3.5" /> Ask Tutor
                </button>
              </div>
              <div class="flex justify-center">
                <button
                  phx-click="dismiss_explanation"
                  class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
                >
                  Got It
                </button>
              </div>
            </div>

            <%!-- Action buttons: 3-confidence + Answer (hidden during answer/explanation) --%>
            <div
              :if={!@show_answer_input and !@show_explanation}
              class="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-2 sm:gap-3 mt-auto"
            >
              <button
                phx-click="mark_dont_know"
                class="flex-1 bg-red-50 hover:bg-red-100 text-[#FF3B30] font-medium py-3 rounded-full transition-colors text-sm touch-target"
              >
                I Don't Know
              </button>
              <button
                phx-click="mark_not_sure"
                class="flex-1 bg-yellow-50 hover:bg-yellow-100 text-yellow-700 font-medium py-3 rounded-full transition-colors text-sm touch-target"
              >
                Not Sure
              </button>
              <button
                phx-click="show_answer_input"
                class="flex-1 bg-[#007AFF] hover:bg-[#0066DD] text-white font-medium py-3 rounded-full transition-colors text-sm touch-target"
              >
                Answer
              </button>
              <button
                phx-click="mark_i_know"
                class="flex-1 bg-[#E8F8EB] hover:bg-[#D0F0D8] text-[#4CD964] font-medium py-3 rounded-full transition-colors text-sm touch-target"
              >
                I Know This
              </button>
            </div>
          </div>
        </div>

        <%!-- Completion summary --%>
        <div :if={@test_complete && @summary} class="bg-white rounded-2xl shadow-md p-5 sm:p-8">
          <div class="text-center mb-6 sm:mb-8">
            <.icon
              name="hero-sparkles"
              class="w-12 h-12 sm:w-16 sm:h-16 text-[#4CD964] mx-auto mb-3 sm:mb-4"
            />
            <h2 class="text-xl sm:text-2xl font-bold text-[#1C1C1E]">Session Complete!</h2>
          </div>

          <div class="bg-[#F5F5F7] rounded-xl p-4 sm:p-6 mb-5 sm:mb-6">
            <div class="text-center">
              <p class="text-3xl sm:text-4xl font-bold text-[#4CD964]">{@summary.score}%</p>
              <p class="text-sm text-[#8E8E93] mt-1">
                {@summary.total} questions reviewed
              </p>
            </div>
          </div>

          <div class="grid grid-cols-2 gap-2 sm:gap-3 mb-6 sm:mb-8">
            <div class="bg-[#E8F8EB] rounded-xl p-3 text-center">
              <p class="text-xl font-bold text-[#4CD964]">{@summary.known}</p>
              <p class="text-xs text-[#8E8E93]">Already Knew</p>
            </div>
            <div class="bg-green-50 rounded-xl p-3 text-center">
              <p class="text-xl font-bold text-[#4CD964]">{@summary.answered_correct}</p>
              <p class="text-xs text-[#8E8E93]">Answered Correctly</p>
            </div>
            <div class="bg-red-50 rounded-xl p-3 text-center">
              <p class="text-xl font-bold text-[#FF3B30]">
                {@summary.unknown + @summary.answered_wrong}
              </p>
              <p class="text-xs text-[#8E8E93]">Need Review</p>
            </div>
            <div class="bg-[#F5F5F7] rounded-xl p-3 text-center">
              <p class="text-xl font-bold text-[#8E8E93]">{@summary.skipped}</p>
              <p class="text-xs text-[#8E8E93]">Skipped</p>
            </div>
          </div>

          <div class="flex flex-col sm:flex-row justify-center gap-3 sm:gap-4">
            <.link
              navigate={~p"/dashboard"}
              class="px-6 py-3 sm:py-2 border border-[#E5E5EA] text-[#1C1C1E] font-medium rounded-full hover:bg-[#F5F5F7] transition-colors text-center touch-target"
            >
              Back to Dashboard
            </.link>
            <button
              phx-click="restart"
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
            >
              Practice Again
            </button>
          </div>
        </div>

        <%!-- Tutor Chat Panel --%>
        <div
          :if={@tutor_open}
          class="fixed inset-x-0 bottom-0 z-40 bg-white border-t border-[#E5E5EA] shadow-xl rounded-t-2xl max-h-[60vh] flex flex-col"
          id="tutor-panel"
          phx-hook="ScrollBottom"
        >
          <div class="flex items-center justify-between px-6 py-3 border-b border-[#E5E5EA] shrink-0">
            <div class="flex items-center gap-2">
              <.icon name="hero-academic-cap" class="w-5 h-5 text-[#4CD964]" />
              <span class="font-medium text-[#1C1C1E]">AI Tutor</span>
              <span class="text-xs text-[#8E8E93]">
                — {if @current_question && @current_question.chapter,
                  do: @current_question.chapter.name,
                  else: @course.name}
              </span>
            </div>
            <button
              phx-click="close_tutor"
              class="p-1 text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
              aria-label="Close tutor"
            >
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>

          <div class="flex-1 overflow-y-auto px-6 py-4 space-y-4" id="tutor-messages">
            <div
              :if={@tutor_messages == []}
              class="text-center text-sm text-[#8E8E93] py-8"
            >
              Ask me anything about this question! I'm here to help you understand.
            </div>

            <div
              :for={msg <- @tutor_messages}
              class={[
                "flex",
                if(msg.role == "user", do: "justify-end", else: "justify-start")
              ]}
            >
              <div class={[
                "max-w-[80%] px-4 py-3 rounded-2xl text-sm leading-relaxed",
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
                  >
                  </div>
                  <div
                    class="w-2 h-2 bg-[#8E8E93] rounded-full animate-bounce"
                    style="animation-delay: 150ms"
                  >
                  </div>
                  <div
                    class="w-2 h-2 bg-[#8E8E93] rounded-full animate-bounce"
                    style="animation-delay: 300ms"
                  >
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div class="px-6 py-3 border-t border-[#E5E5EA] shrink-0">
            <form phx-submit="tutor_send" class="flex gap-2">
              <input
                type="text"
                name="message"
                value={@tutor_input}
                phx-change="tutor_input"
                placeholder="Ask about this question..."
                autocomplete="off"
                class="flex-1 px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none text-sm transition-colors"
              />
              <button
                type="submit"
                disabled={@tutor_loading || @tutor_input == ""}
                class={[
                  "p-2 rounded-full transition-colors",
                  if(@tutor_loading || @tutor_input == "",
                    do: "bg-[#E5E5EA] text-[#8E8E93] cursor-not-allowed",
                    else: "bg-[#4CD964] hover:bg-[#3DBF55] text-white shadow-md"
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
    </div>
    """
  end

  # --- Tutor markdown renderer ---

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

  # Shared answer input components

  attr :question, :map, required: true
  attr :selected_answer, :string, default: nil
  attr :feedback, :map, default: nil

  defp render_mcq_options(assigns) do
    options = assigns.question.options || %{}

    sorted_options =
      options
      |> Enum.sort_by(fn {k, _v} -> k end)
      |> Enum.map(fn {key, value} -> %{key: key, value: value} end)

    assigns = assign(assigns, sorted_options: sorted_options)

    ~H"""
    <div class="space-y-2">
      <button
        :for={opt <- @sorted_options}
        type="button"
        phx-click="select_answer"
        phx-value-answer={opt.key}
        disabled={@feedback != nil}
        class={[
          "w-full text-left p-3 rounded-xl border-2 transition-colors text-sm",
          cond do
            @feedback != nil and opt.key == @feedback.correct_answer ->
              "border-[#4CD964] bg-[#E8F8EB]"

            @feedback != nil and opt.key == @selected_answer and not @feedback.is_correct ->
              "border-[#FF3B30] bg-red-50"

            @selected_answer == opt.key ->
              "border-[#4CD964] bg-[#E8F8EB]"

            true ->
              "border-[#E5E5EA] hover:border-[#4CD964] hover:bg-[#F5F5F7]"
          end
        ]}
      >
        <span class="font-medium text-[#1C1C1E]">{opt.key}.</span>
        <span class="ml-2 text-[#1C1C1E]">{opt.value}</span>
      </button>
    </div>
    """
  end

  attr :selected_answer, :string, default: nil
  attr :feedback, :map, default: nil

  defp render_true_false(assigns) do
    ~H"""
    <div class="flex gap-3">
      <button
        :for={value <- ["True", "False"]}
        type="button"
        phx-click="select_answer"
        phx-value-answer={value}
        disabled={@feedback != nil}
        class={[
          "flex-1 p-3 rounded-xl border-2 text-center font-medium transition-colors text-sm",
          cond do
            @feedback != nil and String.downcase(value) == String.downcase(@feedback.correct_answer) ->
              "border-[#4CD964] bg-[#E8F8EB] text-[#4CD964]"

            @feedback != nil and @selected_answer == value and not @feedback.is_correct ->
              "border-[#FF3B30] bg-red-50 text-[#FF3B30]"

            @selected_answer == value ->
              "border-[#4CD964] bg-[#E8F8EB] text-[#4CD964]"

            true ->
              "border-[#E5E5EA] hover:border-[#4CD964] text-[#1C1C1E]"
          end
        ]}
      >
        {value}
      </button>
    </div>
    """
  end

  attr :selected_answer, :string, default: nil
  attr :feedback, :map, default: nil

  defp render_text_input(assigns) do
    ~H"""
    <div>
      <form phx-change="update_text_answer">
        <textarea
          name="answer"
          placeholder="Type your answer..."
          disabled={@feedback != nil}
          rows="3"
          class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-xl outline-none transition-colors resize-none text-sm"
        >{@selected_answer}</textarea>
      </form>
    </div>
    """
  end

  attr :stats, :map, required: true

  defp render_community_stats(assigns) do
    correct_pct =
      if assigns.stats.total_attempts > 0 do
        Float.round(assigns.stats.correct_attempts / assigns.stats.total_attempts * 100, 0)
      else
        0
      end

    assigns = assign(assigns, correct_pct: correct_pct)

    ~H"""
    <div class="mt-3 flex items-center gap-2 text-xs text-[#8E8E93]">
      <.icon name="hero-users" class="w-4 h-4" />
      <span>
        <span class="font-medium">{trunc(@correct_pct)}%</span>
        of students got this right
        <span class="text-[#C7C7CC]">({@stats.total_attempts} attempts)</span>
      </span>
    </div>
    """
  end

  # Remediation videos surfaced on wrong-answer / "I don't know" (I-14).
  # Renders nothing when the list is empty — never fabricate (I-16).
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
end
