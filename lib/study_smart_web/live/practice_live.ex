defmodule StudySmartWeb.PracticeLive do
  use StudySmartWeb, :live_view

  alias StudySmart.{Courses, Questions}
  alias StudySmart.Assessments.PracticeEngine

  @impl true
  def mount(%{"course_id" => course_id}, _session, socket) do
    course = Courses.get_course_with_chapters!(course_id)
    user_role_id = socket.assigns.current_user["user_role_id"]

    state = PracticeEngine.start_practice(user_role_id, course_id)
    total_questions = length(state.questions)

    socket =
      socket
      |> assign(
        page_title: "Practice: #{course.name}",
        course: course,
        chapters: course.chapters,
        selected_chapter_id: nil,
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

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_chapter", %{"chapter_id" => chapter_id}, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    course_id = socket.assigns.course.id

    opts =
      if chapter_id == "" do
        %{}
      else
        %{chapter_id: chapter_id}
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
        Questions.create_question_attempt(%{
          user_role_id: user_role_id,
          question_id: question.id,
          answer_given: answer,
          is_correct: is_correct,
          time_taken_seconds: max(time_taken, 0),
          difficulty_at_attempt: to_string(question.difficulty)
        })
      end

      new_state = PracticeEngine.record_answer(state, question.id, answer, is_correct)

      {:noreply,
       assign(socket,
         engine_state: new_state,
         feedback: %{
           is_correct: is_correct,
           correct_answer: question.answer
         }
       )}
    end
  end

  def handle_event("next_question", _params, socket) do
    socket =
      socket
      |> assign(feedback: nil, selected_answer: nil)
      |> advance_to_next()

    {:noreply, socket}
  end

  def handle_event("practice_again", _params, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    course_id = socket.assigns.course.id

    opts =
      case socket.assigns.selected_chapter_id do
        nil -> %{}
        chapter_id -> %{chapter_id: chapter_id}
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
        start_time: System.monotonic_time(:second)
      )
      |> maybe_advance_to_next()

    {:noreply, socket}
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
          current_question: question,
          question_number: socket.assigns.question_number + 1,
          start_time: System.monotonic_time(:second)
        )

      {:complete, new_state} ->
        summary = PracticeEngine.summary(new_state)

        assign(socket,
          engine_state: new_state,
          current_question: nil,
          practice_complete: true,
          summary: summary
        )
    end
  end

  defp check_answer(question, answer) do
    String.downcase(String.trim(answer)) == String.downcase(String.trim(question.answer))
  end

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
    <div class="max-w-3xl mx-auto">
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-6">
        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/courses/#{@course.id}"}
            class="text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
          >
            <.icon name="hero-arrow-left" class="w-6 h-6" />
          </.link>
          <div>
            <h1 class="text-2xl font-bold text-[#1C1C1E]">Practice Mode</h1>
            <p class="text-sm text-[#8E8E93]">{@course.name}</p>
          </div>
        </div>

        <div :if={!@practice_complete} class="flex items-center gap-2">
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
          Back to Course
        </.link>
      </div>

      <%!-- Question card --%>
      <div :if={@current_question && !@practice_complete} class="bg-white rounded-2xl shadow-md p-8">
        <div class="flex items-center justify-between mb-6">
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
            Back to Course
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
end
