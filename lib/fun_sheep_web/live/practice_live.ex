defmodule FunSheepWeb.PracticeLive do
  use FunSheepWeb, :live_view

  alias FunSheep.{Assessments, Courses, Engagement, Gamification, Questions, Tutor}
  alias FunSheep.Assessments.{PracticeEngine, ScopeReadiness}
  alias FunSheep.Gamification.FpEconomy

  @xp_per_correct FpEconomy.xp_per_correct()

  @impl true
  def mount(%{"course_id" => course_id} = params, _session, socket) do
    course = Courses.get_course_with_chapters!(course_id)
    user_role_id = socket.assigns.current_user["user_role_id"]

    # When the student arrives with a `schedule_id` (e.g. from the diagnostic
    # summary "Practice Weak Topics" CTA), scope to that test's chapters and
    # format. Otherwise fall back to the format from the user's existing
    # test schedules for this course, so question_types are always respected.
    {schedule, scope_opts} = resolve_schedule_scope(params, user_role_id, course_id)
    question_types = Map.get(scope_opts, :question_types, [])

    state = PracticeEngine.start_practice(user_role_id, course_id, scope_opts)
    total_questions = length(state.questions)

    socket =
      socket
      |> assign(
        page_title: "Practice: #{course.name}",
        course: course,
        chapters: course.chapters,
        selected_chapter_id: nil,
        test_schedule: schedule,
        question_types: question_types,
        engine_state: state,
        current_question: nil,
        selected_answer: nil,
        feedback: nil,
        question_number: 0,
        total_questions: total_questions,
        practice_complete: false,
        summary: nil,
        start_time: System.monotonic_time(:second),
        question_flagged: false,
        # Tutor state
        tutor_open: false,
        tutor_session_id: nil,
        tutor_messages: [],
        tutor_loading: false,
        tutor_input: ""
      )
      |> maybe_advance_to_next()

    {:ok, socket}
  end

  defp resolve_schedule_scope(%{"schedule_id" => schedule_id}, _user_role_id, _course_id)
       when is_binary(schedule_id) and schedule_id != "" do
    case Assessments.get_test_schedule_with_course!(schedule_id) do
      %{} = schedule ->
        chapter_ids = ScopeReadiness.scope_chapter_ids(schedule)
        question_types = format_question_types(schedule.format_template)

        {schedule,
         %{
           test_schedule_id: schedule.id,
           chapter_ids: chapter_ids,
           question_types: question_types
         }}
    end
  rescue
    Ecto.NoResultsError -> {nil, %{question_types: ["multiple_choice"]}}
  end

  defp resolve_schedule_scope(_params, user_role_id, course_id) do
    question_types = load_course_question_types(user_role_id, course_id)
    {nil, %{question_types: question_types}}
  end

  defp load_course_question_types(user_role_id, course_id) do
    today = Date.utc_today()

    schedules =
      Assessments.list_test_schedules_for_course_with_format(user_role_id, course_id)

    # Prefer the soonest upcoming schedule with a format template; fall back
    # to the most recent past one. If none have a format, default to MC-only.
    template =
      schedules
      |> Enum.filter(&(&1.format_template != nil))
      |> then(fn with_format ->
        Enum.find(with_format, &(Date.compare(&1.test_date, today) != :lt)) ||
          List.last(with_format)
      end)
      |> then(fn
        nil -> nil
        %{format_template: ft} -> ft
      end)

    format_question_types(template)
  end

  defp format_question_types(format_template) do
    FunSheep.Assessments.Engine.format_question_types(format_template)
  end

  @impl true
  def handle_event("filter_chapter", %{"chapter_id" => chapter_id}, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    course_id = socket.assigns.course.id

    opts =
      if chapter_id == "" do
        %{question_types: socket.assigns.question_types}
      else
        %{chapter_id: chapter_id, question_types: socket.assigns.question_types}
      end

    state = PracticeEngine.start_practice(user_role_id, course_id, opts)
    total_questions = length(state.questions)

    socket =
      socket
      |> assign(
        selected_chapter_id: if(chapter_id == "", do: nil, else: chapter_id),
        engine_state: state,
        current_question: nil,
        selected_answer: nil,
        feedback: nil,
        question_number: 0,
        total_questions: total_questions,
        practice_complete: false,
        summary: nil,
        start_time: System.monotonic_time(:second)
      )
      |> maybe_advance_to_next()

    {:noreply, socket}
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
      start_time: start_time
    } = socket.assigns

    if answer == nil or question == nil do
      {:noreply, socket}
    else
      is_correct = check_answer(question, answer)
      time_taken = System.monotonic_time(:second) - start_time

      # Record the attempt in the database
      user_role_id = socket.assigns.current_user["user_role_id"]

      if user_role_id do
        Questions.record_attempt_with_stats(%{
          user_role_id: user_role_id,
          question_id: question.id,
          answer_given: answer,
          is_correct: is_correct,
          time_taken_seconds: max(time_taken, 0),
          difficulty_at_attempt: to_string(question.difficulty)
        })

        if is_correct do
          Gamification.award_xp(user_role_id, @xp_per_correct, "practice", source_id: question.id)
        end

        Gamification.record_activity(user_role_id)
      end

      new_state = PracticeEngine.record_answer(state, question.id, answer, is_correct)

      socket =
        assign(socket,
          engine_state: new_state,
          feedback: %{
            is_correct: is_correct,
            correct_answer: question.answer,
            explanation: question.explanation
          }
        )

      socket =
        if is_correct, do: socket, else: push_event(socket, "play_sound", %{name: "sheep_wrong"})

      {:noreply, socket}
    end
  end

  def handle_event("next_question", _params, socket) do
    socket =
      socket
      |> assign(feedback: nil, selected_answer: nil, question_flagged: false)
      |> reset_tutor()
      |> advance_to_next()

    {:noreply, socket}
  end

  def handle_event("practice_again", _params, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    course_id = socket.assigns.course.id

    opts =
      case socket.assigns.selected_chapter_id do
        nil -> %{question_types: socket.assigns.question_types}
        chapter_id -> %{chapter_id: chapter_id, question_types: socket.assigns.question_types}
      end

    state = PracticeEngine.start_practice(user_role_id, course_id, opts)
    total_questions = length(state.questions)

    socket =
      socket
      |> assign(
        engine_state: state,
        current_question: nil,
        selected_answer: nil,
        feedback: nil,
        question_number: 0,
        total_questions: total_questions,
        practice_complete: false,
        summary: nil,
        start_time: System.monotonic_time(:second),
        question_flagged: false
      )
      |> maybe_advance_to_next()

    {:noreply, socket}
  end

  def handle_event("flag_question", %{"reason" => reason_str}, socket) do
    question = socket.assigns.current_question
    user_role_id = socket.assigns.current_user["user_role_id"]

    if question && user_role_id do
      reason = if reason_str == "", do: nil, else: String.to_existing_atom(reason_str)
      Questions.flag_question(user_role_id, question.id, reason)
      {:noreply, assign(socket, question_flagged: true)}
    else
      {:noreply, socket}
    end
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
    # PubSub broadcast — already handled inline above in mock/poll mode
    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp ensure_tutor_session(socket) do
    if socket.assigns.tutor_session_id do
      socket
    else
      question = socket.assigns.current_question
      user_role_id = socket.assigns.current_user["user_role_id"]
      course_id = socket.assigns.course.id

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

  # Reset tutor when advancing to a new question
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

  # Only advance if there are questions; otherwise leave socket as-is
  # so the "No Weak Questions" empty state renders.
  defp maybe_advance_to_next(socket) do
    if socket.assigns.total_questions > 0 do
      advance_to_next(socket)
    else
      socket
    end
  end

  defp advance_to_next(socket) do
    state = socket.assigns.engine_state

    case PracticeEngine.current_question(state) do
      {:question, question, new_state} ->
        assign(socket,
          engine_state: new_state,
          current_question: FunSheep.Questions.with_figures(question),
          question_number: socket.assigns.question_number + 1,
          start_time: System.monotonic_time(:second)
        )

      {:complete, new_state} ->
        summary = PracticeEngine.summary(new_state)
        finalize_session(socket)

        assign(socket,
          engine_state: new_state,
          current_question: nil,
          practice_complete: true,
          summary: summary
        )
    end
  end

  defp finalize_session(socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    course_id = socket.assigns.course.id

    if user_role_id && course_id do
      Engagement.after_session(user_role_id, course_id)
    end

    :ok
  end

  defp check_answer(question, answer), do: FunSheep.Questions.Grading.correct?(question, answer)

  defp has_figures?(%{figures: figures}) when is_list(figures), do: figures != []
  defp has_figures?(_), do: false

  defp figure_url(%{image_path: path}) when is_binary(path), do: FunSheep.Storage.url(path)
  defp figure_url(_), do: nil

  defp table_spec(%{metadata: %{"table_spec" => %{"headers" => _, "rows" => _} = spec}}), do: spec
  defp table_spec(_), do: nil

  # Renders an AI-supplied table spec as an accessible HTML table. Used when a
  # question depends on tabular data but no source figure exists — the LLM
  # supplies the data as structured JSON and we render it honestly, labeled
  # as AI-generated.
  attr :spec, :map, required: true

  defp render_table_spec(assigns) do
    ~H"""
    <figure class="bg-white rounded-2xl border border-[#E5E5EA] overflow-hidden">
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead class="bg-[#F5F5F7]">
            <tr>
              <th
                :for={header <- @spec["headers"] || []}
                scope="col"
                class="px-4 py-3 text-left font-semibold text-[#1C1C1E]"
              >
                {header}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @spec["rows"] || []} class="border-t border-[#E5E5EA]">
              <td :for={cell <- row} class="px-4 py-3 text-[#1C1C1E]">{cell}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <figcaption class="px-4 py-2 text-xs text-[#8E8E93] bg-[#F5F5F7] border-t border-[#E5E5EA]">
        <span :if={@spec["caption"] && @spec["caption"] != ""}>{@spec["caption"] <> " · "}</span>
        AI-generated reference table
      </figcaption>
    </figure>
    """
  end

  # Safe skill-name accessor. Questions can appear here with either a loaded
  # section (preloaded via `list_weak_questions`) or with `section: nil` if
  # they predate classifier runs. Returns nil when we have nothing to show
  # so the badge can be hidden entirely rather than rendering "Practicing: ".
  defp skill_name(%{section: %{name: name}}) when is_binary(name) and name != "", do: name
  defp skill_name(_), do: nil

  defp difficulty_badge_class(difficulty) do
    case difficulty do
      :easy -> "bg-[#E8F8EB] text-[#4CD964]"
      :medium -> "bg-yellow-100 text-yellow-700"
      :hard -> "bg-red-100 text-[#FF3B30]"
      _ -> "bg-gray-100 text-gray-600"
    end
  end

  defp difficulty_label(difficulty) do
    case difficulty do
      :easy -> "Easy"
      :medium -> "Medium"
      :hard -> "Hard"
      _ -> "Unknown"
    end
  end

  defp progress_percentage(question_number, total) do
    if total > 0, do: Float.round(question_number / total * 100, 0), else: 0
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto pb-20">
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-6">
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
            <h1 class="text-2xl font-bold text-[#1C1C1E]">Practice Mode</h1>
            <p class="text-sm text-[#8E8E93]">{@course.name}</p>
          </div>
        </div>

        <div :if={!@practice_complete} class="flex items-center gap-3">
          <span class="text-sm text-[#8E8E93]">
            {@question_number} / {@total_questions}
          </span>
        </div>
      </div>

      <%!-- Chapter filter --%>
      <div :if={!@practice_complete and length(@chapters) > 0} class="mb-6">
        <form phx-change="filter_chapter">
          <select
            name="chapter_id"
            class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors"
          >
            <option value="">All Chapters</option>
            <option
              :for={ch <- @chapters}
              value={ch.id}
              selected={@selected_chapter_id == ch.id}
            >
              {ch.name}
            </option>
          </select>
        </form>
      </div>

      <%!-- Progress bar --%>
      <div :if={!@practice_complete and @total_questions > 0} class="mb-6">
        <div class="w-full bg-[#E5E5EA] rounded-full h-2">
          <div
            class="bg-[#4CD964] h-2 rounded-full transition-all duration-300"
            style={"width: #{progress_percentage(@question_number, @total_questions)}%"}
          >
          </div>
        </div>
      </div>

      <%!-- No questions state --%>
      <div
        :if={@total_questions == 0 and !@practice_complete}
        class="bg-white rounded-2xl shadow-md p-8 text-center"
      >
        <.icon name="hero-academic-cap" class="w-16 h-16 text-[#4CD964] mx-auto mb-4" />
        <h2 class="text-xl font-bold text-[#1C1C1E] mb-2">No Weak Questions Found</h2>
        <p class="text-[#8E8E93] mb-6">
          You haven't missed any questions yet, or there are no questions to practice.
          Try taking an assessment first!
        </p>
        <.link
          navigate={~p"/courses/#{@course.id}"}
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
        >
          Go to Course Page
        </.link>
      </div>

      <%!-- Question card --%>
      <div :if={@current_question && !@practice_complete} class="bg-white rounded-2xl shadow-md p-8">
        <div class="flex items-center justify-between mb-3">
          <p class="text-sm text-[#8E8E93]">
            Question {@question_number}
            <span :if={@current_question.chapter}>
              | {@current_question.chapter.name}
            </span>
          </p>
          <span class={"px-3 py-1 rounded-full text-xs font-medium #{difficulty_badge_class(@current_question.difficulty)}"}>
            {difficulty_label(@current_question.difficulty)}
          </span>
        </div>

        <%!-- Teacher-review fix #4: show the skill being practiced.
             Metacognitive awareness (Flavell) — students who know what
             skill they're drilling retain more. Only renders when the
             question has a classified section; unclassified questions
             shouldn't even reach the adaptive engine per I-1. --%>
        <div
          :if={skill_name(@current_question)}
          class="mb-6 inline-flex items-center gap-2 px-3 py-1 bg-[#E8F8EB] text-[#4CD964] rounded-full text-xs font-medium"
        >
          <.icon name="hero-sparkles" class="w-3.5 h-3.5" />
          Practicing: {skill_name(@current_question)}
        </div>

        <%!-- Attached figures (tables, graphs, diagrams) from source material --%>
        <div
          :if={has_figures?(@current_question)}
          class="mb-6 space-y-4"
        >
          <figure
            :for={fig <- @current_question.figures}
            class="bg-[#F5F5F7] rounded-2xl p-4 border border-[#E5E5EA]"
          >
            <img
              src={figure_url(fig)}
              alt={fig.caption || "#{fig.figure_type} from source material"}
              class="w-full max-h-96 object-contain rounded-xl bg-white"
              loading="lazy"
            />
            <figcaption :if={fig.caption} class="mt-2 text-sm text-[#8E8E93]">
              {fig.caption}
            </figcaption>
          </figure>
        </div>

        <%!-- AI-generated table spec (rendered as HTML table, never fabricated image) --%>
        <div :if={table_spec(@current_question)} class="mb-6">
          <.render_table_spec spec={table_spec(@current_question)} />
        </div>

        <div class="mb-8">
          <p class="text-lg text-[#1C1C1E] font-medium leading-relaxed">
            {@current_question.content}
          </p>
        </div>

        <%!-- Answer options --%>
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

        <%!-- Feedback --%>
        <div :if={@feedback} class="mt-6">
          <div class={[
            "p-4 rounded-xl flex items-center gap-3",
            if(@feedback.is_correct, do: "bg-[#E8F8EB]", else: "bg-red-50")
          ]}>
            <.icon
              name={if(@feedback.is_correct, do: "hero-check-circle", else: "hero-x-circle")}
              class={[
                "w-6 h-6",
                if(@feedback.is_correct, do: "text-[#4CD964]", else: "text-[#FF3B30]")
              ]}
            />
            <div>
              <p class={[
                "font-medium",
                if(@feedback.is_correct, do: "text-[#4CD964]", else: "text-[#FF3B30]")
              ]}>
                {if @feedback.is_correct, do: "Correct!", else: "Incorrect"}
              </p>
              <p :if={!@feedback.is_correct} class="text-sm text-[#8E8E93] mt-1">
                Correct answer: {@feedback.correct_answer}
              </p>
            </div>
          </div>

          <%!-- Teacher-review fix #3: show the canonical explanation inline
               so wrong-answer feedback teaches. Only shown after submit and
               when we actually have an explanation to share. --%>
          <div
            :if={@feedback.explanation && String.trim(@feedback.explanation) != ""}
            class="mt-3 p-4 bg-[#F5F5F7] rounded-xl border border-[#E5E5EA]"
          >
            <p class="text-xs font-medium text-[#8E8E93] uppercase tracking-wide mb-1">
              Why
            </p>
            <p class="text-sm text-[#1C1C1E] leading-relaxed">
              {@feedback.explanation}
            </p>
          </div>

          <.question_flag_link question_flagged={@question_flagged} />

          <div class="flex justify-end mt-4">
            <button
              phx-click="next_question"
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
            >
              Next Question
            </button>
          </div>
        </div>

        <%!-- Submit button --%>
        <div :if={@feedback == nil} class="flex justify-end mt-6">
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
            Submit Answer
          </button>
        </div>
      </div>

      <%!-- Ask Tutor (only after submitting an answer) --%>
      <div :if={@current_question && @feedback && !@practice_complete} class="mt-4">
        <div class="flex items-center gap-2 flex-wrap">
          <button
            :if={!@feedback.is_correct}
            phx-click="tutor_quick_action"
            phx-value-action="why_wrong"
            class="inline-flex items-center gap-1.5 px-4 py-2 bg-white border border-[#E5E5EA] hover:border-[#FF3B30] text-sm text-[#1C1C1E] rounded-full transition-colors"
          >
            <.icon name="hero-question-mark-circle" class="w-4 h-4 text-[#FF3B30]" /> Why wrong?
          </button>
          <button
            phx-click="tutor_quick_action"
            phx-value-action="explain"
            class="inline-flex items-center gap-1.5 px-4 py-2 bg-white border border-[#E5E5EA] hover:border-[#4CD964] text-sm text-[#1C1C1E] rounded-full transition-colors"
          >
            <.icon name="hero-academic-cap" class="w-4 h-4 text-[#007AFF]" /> Explain
          </button>
          <button
            phx-click="tutor_quick_action"
            phx-value-action="step_by_step"
            class="inline-flex items-center gap-1.5 px-4 py-2 bg-white border border-[#E5E5EA] hover:border-[#4CD964] text-sm text-[#1C1C1E] rounded-full transition-colors"
          >
            <.icon name="hero-list-bullet" class="w-4 h-4 text-[#8E8E93]" /> Step by step
          </button>
          <button
            phx-click="open_tutor"
            class="inline-flex items-center gap-1.5 px-4 py-2 bg-[#4CD964] hover:bg-[#3DBF55] text-sm text-white font-medium rounded-full shadow-md transition-colors"
          >
            <.icon name="hero-chat-bubble-left-right" class="w-4 h-4" /> Ask Tutor
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
        <%!-- Panel header --%>
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

        <%!-- Messages --%>
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

        <%!-- Input --%>
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

      <%!-- Summary --%>
      <div :if={@practice_complete && @summary} class="bg-white rounded-2xl shadow-md p-8">
        <div class="text-center mb-8">
          <.icon name="hero-trophy" class="w-16 h-16 text-[#4CD964] mx-auto mb-4" />
          <h2 class="text-2xl font-bold text-[#1C1C1E]">Practice Complete!</h2>
          <p class="text-[#8E8E93] mt-2">{@course.name}</p>
        </div>

        <div class="bg-[#F5F5F7] rounded-xl p-6 mb-6">
          <div class="text-center">
            <p class="text-4xl font-bold text-[#4CD964]">{@summary.score}%</p>
            <p class="text-sm text-[#8E8E93] mt-1">
              {@summary.correct} of {@summary.total} correct
            </p>
          </div>
        </div>

        <div class="grid grid-cols-3 gap-4 mb-8">
          <div class="bg-[#E8F8EB] rounded-xl p-4 text-center">
            <p class="text-2xl font-bold text-[#4CD964]">{@summary.correct}</p>
            <p class="text-xs text-[#8E8E93]">Correct</p>
          </div>
          <div class="bg-red-50 rounded-xl p-4 text-center">
            <p class="text-2xl font-bold text-[#FF3B30]">{@summary.incorrect}</p>
            <p class="text-xs text-[#8E8E93]">Incorrect</p>
          </div>
          <div class="bg-blue-50 rounded-xl p-4 text-center">
            <p class="text-2xl font-bold text-[#007AFF]">{@summary.improved}</p>
            <p class="text-xs text-[#8E8E93]">Improved</p>
          </div>
        </div>

        <div class="flex justify-center gap-4">
          <.link
            navigate={~p"/courses/#{@course.id}"}
            class="px-6 py-2 border border-[#E5E5EA] text-[#1C1C1E] font-medium rounded-full hover:bg-[#F5F5F7] transition-colors"
          >
            Go to Course Page
          </.link>
          <button
            phx-click="practice_again"
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Practice Again
          </button>
        </div>
      </div>
    </div>
    """
  end

  # --- Tutor markdown renderer (simple bold/newline support) ---

  attr :content, :string, required: true

  defp render_tutor_markdown(assigns) do
    # Simple markdown: **bold**, \n newlines, numbered lists
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

  # Component functions reused from assessment patterns

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
    <div class="space-y-3">
      <button
        :for={opt <- @sorted_options}
        type="button"
        phx-click="select_answer"
        phx-value-answer={opt.key}
        disabled={@feedback != nil}
        class={[
          "w-full text-left p-4 rounded-xl border-2 transition-colors",
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
    <div class="flex gap-4">
      <button
        :for={value <- ["True", "False"]}
        type="button"
        phx-click="select_answer"
        phx-value-answer={value}
        disabled={@feedback != nil}
        class={[
          "flex-1 p-4 rounded-xl border-2 text-center font-medium transition-colors",
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
          rows="4"
          class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-xl outline-none transition-colors resize-none"
        >{@selected_answer}</textarea>
      </form>
    </div>
    """
  end

  attr :question_flagged, :boolean, default: false

  defp question_flag_link(assigns) do
    ~H"""
    <div class="flex justify-end mt-3">
      <div :if={@question_flagged} class="text-xs text-[#8E8E93]">
        Reported
      </div>

      <div :if={!@question_flagged} class="flex items-center gap-2">
        <button
          type="button"
          phx-click="flag_question"
          phx-value-reason=""
          class="text-xs text-[#C7C7CC] hover:text-[#8E8E93] transition-colors"
        >
          Report
        </button>
        <%= for {label, reason} <- [
          {"Wrong answer", "incorrect_answer"},
          {"Unclear", "unclear"},
          {"Outdated", "outdated"}
        ] do %>
          <button
            type="button"
            phx-click="flag_question"
            phx-value-reason={reason}
            class="text-xs text-[#C7C7CC] hover:text-[#8E8E93] transition-colors"
          >
            {label}
          </button>
        <% end %>
      </div>
    </div>
    """
  end
end
