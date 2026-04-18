defmodule FunSheepWeb.QuickTestLive do
  use FunSheepWeb, :live_view

  alias FunSheep.{Courses, Questions}
  alias FunSheep.Assessments.QuickTestEngine

  @impl true
  def mount(_params, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    courses = Courses.list_courses_for_user(user_role_id)

    state = QuickTestEngine.start_session(user_role_id)
    total_questions = length(state.questions)

    socket =
      socket
      |> assign(
        page_title: "Quick Test",
        courses: courses,
        selected_course_id: nil,
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

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_course", %{"course_id" => course_id}, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]

    opts =
      if course_id == "" do
        %{}
      else
        %{course_id: course_id}
      end

    state = QuickTestEngine.start_session(user_role_id, opts)
    total_questions = length(state.questions)

    socket =
      socket
      |> assign(
        selected_course_id: if(course_id == "", do: nil, else: course_id),
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

  def handle_event("mark_known", _params, socket) do
    %{current_question: question, engine_state: state, stats: stats} = socket.assigns

    if question do
      # Record as correct attempt in DB
      record_attempt(socket, question, "known", true)
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

  def handle_event("mark_unknown", _params, socket) do
    %{current_question: question, engine_state: state, stats: stats} = socket.assigns

    if question do
      # Record as incorrect attempt in DB
      record_attempt(socket, question, "unknown", false)
      new_state = QuickTestEngine.mark_unknown(state, question.id)

      {:noreply,
       assign(socket,
         engine_state: new_state,
         show_explanation: true,
         stats: %{stats | incorrect: stats.incorrect + 1}
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

      record_attempt(socket, question, answer, is_correct)
      new_state = QuickTestEngine.mark_answered(state, question.id, is_correct)

      new_stats =
        if is_correct do
          %{stats | correct: stats.correct + 1}
        else
          %{stats | incorrect: stats.incorrect + 1}
        end

      {:noreply,
       assign(socket,
         engine_state: new_state,
         stats: new_stats,
         feedback: %{is_correct: is_correct, correct_answer: question.answer}
       )}
    end
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

    opts =
      case socket.assigns.selected_course_id do
        nil -> %{}
        course_id -> %{course_id: course_id}
      end

    state = QuickTestEngine.start_session(user_role_id, opts)
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

  defp advance_to_next_card(socket) do
    state = socket.assigns.engine_state

    case QuickTestEngine.current_card(state) do
      {:card, question, new_state} ->
        assign(socket,
          engine_state: new_state,
          current_question: question,
          question_number: socket.assigns.question_number + 1
        )

      {:complete, new_state} ->
        summary = QuickTestEngine.summary(new_state)

        assign(socket,
          engine_state: new_state,
          current_question: nil,
          test_complete: true,
          summary: summary
        )
    end
  end

  defp check_answer(question, answer) do
    String.downcase(String.trim(answer)) == String.downcase(String.trim(question.answer))
  end

  defp record_attempt(socket, question, answer_given, is_correct) do
    user_role_id = socket.assigns.current_user["user_role_id"]

    if user_role_id do
      Questions.create_question_attempt(%{
        user_role_id: user_role_id,
        question_id: question.id,
        answer_given: answer_given,
        is_correct: is_correct,
        difficulty_at_attempt: to_string(question.difficulty)
      })
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
    <div class="max-w-lg mx-auto">
      <%!-- Header with stats --%>
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/dashboard"}
            class="text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
          >
            <.icon name="hero-arrow-left" class="w-6 h-6" />
          </.link>
          <h1 class="text-2xl font-bold text-[#1C1C1E]">Quick Test</h1>
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

      <%!-- Course filter --%>
      <div :if={!@test_complete and length(@courses) > 0} class="mb-6">
        <form phx-change="filter_course">
          <select
            name="course_id"
            class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors text-sm"
          >
            <option value="">All Courses</option>
            <option
              :for={c <- @courses}
              value={c.id}
              selected={@selected_course_id == c.id}
            >
              {c.name}
            </option>
          </select>
        </form>
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
          navigate={~p"/dashboard"}
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
        >
          Back to Dashboard
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

        <div class="bg-white rounded-2xl shadow-lg p-8 min-h-[300px] flex flex-col">
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
              <div class="flex justify-center">
                <button
                  phx-click="next_after_answer"
                  class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
                >
                  Next Card
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
            <div class="flex justify-center mt-4">
              <button
                phx-click="dismiss_explanation"
                class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
              >
                Got It
              </button>
            </div>
          </div>

          <%!-- Action buttons (hidden during answer/explanation) --%>
          <div
            :if={!@show_answer_input and !@show_explanation}
            class="flex items-center justify-between gap-3 mt-auto"
          >
            <button
              phx-click="mark_known"
              class="flex-1 bg-[#E8F8EB] hover:bg-[#D0F0D8] text-[#4CD964] font-medium py-3 rounded-full transition-colors text-sm"
            >
              I Know This
            </button>
            <button
              phx-click="show_answer_input"
              class="flex-1 bg-[#007AFF] hover:bg-[#0066DD] text-white font-medium py-3 rounded-full transition-colors text-sm"
            >
              Answer
            </button>
            <button
              phx-click="mark_unknown"
              class="flex-1 bg-red-50 hover:bg-red-100 text-[#FF3B30] font-medium py-3 rounded-full transition-colors text-sm"
            >
              I Don't Know
            </button>
          </div>
        </div>
      </div>

      <%!-- Completion summary --%>
      <div :if={@test_complete && @summary} class="bg-white rounded-2xl shadow-md p-8">
        <div class="text-center mb-8">
          <.icon name="hero-sparkles" class="w-16 h-16 text-[#4CD964] mx-auto mb-4" />
          <h2 class="text-2xl font-bold text-[#1C1C1E]">Session Complete!</h2>
        </div>

        <div class="bg-[#F5F5F7] rounded-xl p-6 mb-6">
          <div class="text-center">
            <p class="text-4xl font-bold text-[#4CD964]">{@summary.score}%</p>
            <p class="text-sm text-[#8E8E93] mt-1">
              {@summary.total} questions reviewed
            </p>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-3 mb-8">
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

        <div class="flex justify-center gap-4">
          <.link
            navigate={~p"/dashboard"}
            class="px-6 py-2 border border-[#E5E5EA] text-[#1C1C1E] font-medium rounded-full hover:bg-[#F5F5F7] transition-colors"
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
    </div>
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
end
