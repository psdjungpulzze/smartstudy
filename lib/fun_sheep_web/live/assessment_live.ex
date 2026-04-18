defmodule FunSheepWeb.AssessmentLive do
  use FunSheepWeb, :live_view

  alias FunSheep.{Assessments, Questions}
  alias FunSheep.Assessments.Engine

  @impl true
  def mount(%{"schedule_id" => schedule_id}, _session, socket) do
    schedule = Assessments.get_test_schedule_with_course!(schedule_id)
    state = Engine.start_assessment(schedule)

    socket =
      socket
      |> assign(
        page_title: "Assessment: #{schedule.name}",
        schedule: schedule,
        engine_state: state,
        current_question: nil,
        selected_answer: nil,
        feedback: nil,
        question_number: 0,
        start_time: System.monotonic_time(:second)
      )
      |> advance_to_next_question()

    {:ok, socket}
  end

  @impl true
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
          difficulty_at_attempt: to_string(state.current_difficulty)
        })
      end

      new_state = Engine.record_answer(state, question.id, answer, is_correct)

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
      |> advance_to_next_question()

    {:noreply, socket}
  end

  defp advance_to_next_question(socket) do
    state = socket.assigns.engine_state

    case Engine.next_question(state) do
      {:question, question, new_state} ->
        assign(socket,
          engine_state: new_state,
          current_question: question,
          question_number: socket.assigns.question_number + 1,
          start_time: System.monotonic_time(:second)
        )

      {:complete, new_state} ->
        summary = Engine.summary(new_state)

        assign(socket,
          engine_state: new_state,
          current_question: nil,
          assessment_complete: true,
          summary: summary
        )

      _other ->
        # generate_needed or other - treat as complete for now
        summary = Engine.summary(state)

        assign(socket,
          current_question: nil,
          assessment_complete: true,
          summary: summary
        )
    end
  end

  defp check_answer(question, answer) do
    case question.question_type do
      :multiple_choice ->
        String.downcase(String.trim(answer)) == String.downcase(String.trim(question.answer))

      :true_false ->
        String.downcase(String.trim(answer)) == String.downcase(String.trim(question.answer))

      _other ->
        String.downcase(String.trim(answer)) == String.downcase(String.trim(question.answer))
    end
  end

  defp difficulty_badge_class(difficulty) do
    case difficulty do
      :easy -> "bg-[#E8F8EB] text-[#4CD964]"
      :medium -> "bg-yellow-100 text-yellow-700"
      :hard -> "bg-red-100 text-[#FF3B30]"
    end
  end

  defp difficulty_label(difficulty) do
    case difficulty do
      :easy -> "Easy"
      :medium -> "Medium"
      :hard -> "Hard"
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> Map.put_new(:assessment_complete, false)
      |> Map.put_new(:summary, nil)

    ~H"""
    <div class="max-w-3xl mx-auto">
      <div class="flex items-center justify-between mb-6">
        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/tests"}
            class="text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
          >
            <.icon name="hero-arrow-left" class="w-6 h-6" />
          </.link>
          <div>
            <h1 class="text-2xl font-bold text-[#1C1C1E]">{@schedule.name}</h1>
            <p class="text-sm text-[#8E8E93]">{@schedule.course.name}</p>
          </div>
        </div>

        <div :if={!@assessment_complete} class="flex items-center gap-4">
          <span class={"px-3 py-1 rounded-full text-xs font-medium #{difficulty_badge_class(@engine_state.current_difficulty)}"}>
            {difficulty_label(@engine_state.current_difficulty)}
          </span>
        </div>
      </div>

      <%= if @assessment_complete do %>
        <.render_summary summary={@summary} schedule={@schedule} />
      <% else %>
        <.render_question
          question={@current_question}
          selected_answer={@selected_answer}
          feedback={@feedback}
          question_number={@question_number}
          engine_state={@engine_state}
        />
      <% end %>
    </div>
    """
  end

  attr :question, :map, required: true
  attr :selected_answer, :string, default: nil
  attr :feedback, :map, default: nil
  attr :question_number, :integer, required: true
  attr :engine_state, :map, required: true

  defp render_question(assigns) do
    assigns =
      assign(assigns,
        topic_name:
          case Enum.at(assigns.engine_state.topics, assigns.engine_state.current_topic_index) do
            nil -> "Unknown"
            t -> t.name
          end
      )

    ~H"""
    <div :if={@question} class="bg-white rounded-2xl shadow-md p-8">
      <div class="flex items-center justify-between mb-6">
        <p class="text-sm text-[#8E8E93]">
          Question {@question_number} | Topic: {@topic_name}
        </p>
      </div>

      <div class="mb-8">
        <p class="text-lg text-[#1C1C1E] font-medium leading-relaxed">{@question.content}</p>
      </div>

      <%= case @question.question_type do %>
        <% :multiple_choice -> %>
          <.render_mcq_options
            question={@question}
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
    """
  end

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

  attr :summary, :map, required: true
  attr :schedule, :map, required: true

  defp render_summary(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-8">
      <div class="text-center mb-8">
        <.icon name="hero-trophy" class="w-16 h-16 text-[#4CD964] mx-auto mb-4" />
        <h2 class="text-2xl font-bold text-[#1C1C1E]">Assessment Complete!</h2>
        <p class="text-[#8E8E93] mt-2">{@schedule.name}</p>
      </div>

      <div class="bg-[#F5F5F7] rounded-xl p-6 mb-6">
        <div class="text-center">
          <p class="text-4xl font-bold text-[#4CD964]">{@summary.overall_score}%</p>
          <p class="text-sm text-[#8E8E93] mt-1">
            {@summary.total_correct} of {@summary.total_questions} correct
          </p>
        </div>
      </div>

      <div :if={@summary.topic_results != []} class="space-y-3 mb-8">
        <h3 class="font-semibold text-[#1C1C1E]">Results by Topic</h3>
        <div
          :for={result <- @summary.topic_results}
          class="flex items-center justify-between p-3 bg-[#F5F5F7] rounded-xl"
        >
          <div>
            <p class="font-medium text-[#1C1C1E]">{result.topic_name}</p>
            <p class="text-xs text-[#8E8E93]">{result.correct}/{result.total} correct</p>
          </div>
          <div class="flex items-center gap-2">
            <span class={[
              "px-3 py-1 rounded-full text-xs font-medium",
              if(result.mastered,
                do: "bg-[#E8F8EB] text-[#4CD964]",
                else: "bg-red-100 text-[#FF3B30]"
              )
            ]}>
              {if result.mastered, do: "Mastered", else: "Needs Work"}
            </span>
            <span class="font-bold text-[#1C1C1E]">{result.score}%</span>
          </div>
        </div>
      </div>

      <div class="flex justify-center gap-4">
        <.link
          navigate={~p"/tests"}
          class="px-6 py-2 border border-[#E5E5EA] text-[#1C1C1E] font-medium rounded-full hover:bg-[#F5F5F7] transition-colors"
        >
          Back to Tests
        </.link>
        <.link
          navigate={~p"/tests/#{@schedule.id}/assess"}
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
        >
          Retake Assessment
        </.link>
      </div>
    </div>
    """
  end
end
