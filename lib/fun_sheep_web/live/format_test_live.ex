defmodule FunSheepWeb.FormatTestLive do
  use FunSheepWeb, :live_view

  import FunSheepWeb.BillingComponents

  alias FunSheep.{Assessments, Billing, Questions}
  alias FunSheep.Assessments.FormatReplicator

  @impl true
  def mount(%{"course_id" => course_id, "schedule_id" => schedule_id}, _session, socket) do
    schedule = Assessments.get_test_schedule_with_course!(schedule_id)
    user_role_id = socket.assigns.current_user["user_role_id"]
    role = socket.assigns.current_user["role"]

    case Billing.check_test_allowance(user_role_id, role) do
      :ok ->
        Billing.record_test_usage(user_role_id, "format_test", course_id)
        mount_format_test(socket, course_id, schedule, user_role_id)

      {:error, :limit_reached, _info} ->
        billing_stats = Billing.usage_stats(user_role_id)

        {:ok,
         assign(socket,
           page_title: "Format Test: #{schedule.name}",
           course_id: course_id,
           schedule: schedule,
           billing_blocked: true,
           billing_stats: billing_stats,
           no_template: false,
           submitted: false,
           results: nil
         )}
    end
  end

  defp mount_format_test(socket, course_id, schedule, user_role_id) do
    if schedule.format_template_id do
      practice_test =
        FormatReplicator.generate_practice_test(
          schedule.format_template_id,
          schedule.course_id,
          user_role_id
        )

      # Load all questions
      all_questions =
        practice_test.sections
        |> Enum.flat_map(fn s -> s["questions"] end)
        |> Enum.map(&Questions.get_question!/1)

      # Build section-indexed question lists
      {sections_with_questions, _} =
        Enum.map_reduce(practice_test.sections, 0, fn section, offset ->
          count = section["actual_count"]
          qs = Enum.slice(all_questions, offset, count)

          section_data = %{
            name: section["name"],
            question_type: section["question_type"],
            points_per_question: section["points_per_question"],
            questions: qs
          }

          {section_data, offset + count}
        end)

      time_limit = practice_test.time_limit
      timer_ref = if time_limit, do: Process.send_after(self(), :tick, 1_000), else: nil

      {:ok,
       assign(socket,
         page_title: "Format Test: #{schedule.name}",
         course_id: course_id,
         schedule: schedule,
         billing_blocked: false,
         billing_stats: nil,
         user_role_id: user_role_id,
         practice_test: practice_test,
         sections_with_questions: sections_with_questions,
         current_section_index: 0,
         current_question_index: 0,
         selected_answer: nil,
         answers: %{},
         submitted: false,
         results: nil,
         time_limit: time_limit,
         remaining_seconds: if(time_limit, do: time_limit * 60, else: nil),
         timer_ref: timer_ref,
         start_time: System.monotonic_time(:second)
       )}
    else
      {:ok,
       socket
       |> assign(
         page_title: "Format Test",
         course_id: course_id,
         schedule: schedule,
         billing_blocked: false,
         billing_stats: nil,
         no_template: true
       )}
    end
  end

  @impl true
  def handle_info(:tick, socket) do
    remaining = socket.assigns.remaining_seconds - 1

    if remaining <= 0 do
      # Time's up - auto submit
      {:noreply, submit_test(assign(socket, remaining_seconds: 0))}
    else
      Process.send_after(self(), :tick, 1_000)
      {:noreply, assign(socket, remaining_seconds: remaining)}
    end
  end

  @impl true
  def handle_event("select_answer", %{"answer" => answer}, socket) do
    {:noreply, assign(socket, selected_answer: answer)}
  end

  def handle_event("update_text_answer", %{"answer" => answer}, socket) do
    {:noreply, assign(socket, selected_answer: answer)}
  end

  def handle_event("save_and_next", _params, socket) do
    socket = save_current_answer(socket)

    {section_idx, question_idx} =
      next_position(
        socket.assigns.current_section_index,
        socket.assigns.current_question_index,
        socket.assigns.sections_with_questions
      )

    {:noreply,
     assign(socket,
       current_section_index: section_idx,
       current_question_index: question_idx,
       selected_answer: get_saved_answer(socket.assigns.answers, section_idx, question_idx)
     )}
  end

  def handle_event("go_to_question", %{"section" => s, "question" => q}, socket) do
    socket = save_current_answer(socket)
    section_idx = String.to_integer(s)
    question_idx = String.to_integer(q)

    {:noreply,
     assign(socket,
       current_section_index: section_idx,
       current_question_index: question_idx,
       selected_answer: get_saved_answer(socket.assigns.answers, section_idx, question_idx)
     )}
  end

  def handle_event("submit_test", _params, socket) do
    socket = save_current_answer(socket)
    {:noreply, submit_test(socket)}
  end

  defp save_current_answer(socket) do
    answer = socket.assigns.selected_answer
    s_idx = socket.assigns.current_section_index
    q_idx = socket.assigns.current_question_index

    if answer do
      key = {s_idx, q_idx}
      answers = Map.put(socket.assigns.answers, key, answer)
      assign(socket, answers: answers, selected_answer: nil)
    else
      assign(socket, selected_answer: nil)
    end
  end

  defp get_saved_answer(answers, section_idx, question_idx) do
    Map.get(answers, {section_idx, question_idx})
  end

  defp next_position(section_idx, question_idx, sections) do
    section = Enum.at(sections, section_idx)

    if question_idx + 1 < length(section.questions) do
      {section_idx, question_idx + 1}
    else
      if section_idx + 1 < length(sections) do
        {section_idx + 1, 0}
      else
        # Stay on last question
        {section_idx, question_idx}
      end
    end
  end

  defp submit_test(socket) do
    if socket.assigns[:timer_ref] do
      Process.cancel_timer(socket.assigns.timer_ref)
    end

    answers = socket.assigns.answers
    sections = socket.assigns.sections_with_questions
    time_taken = System.monotonic_time(:second) - socket.assigns.start_time
    user_role_id = socket.assigns.user_role_id

    section_results =
      Enum.with_index(sections)
      |> Enum.map(fn {section, s_idx} ->
        question_results =
          Enum.with_index(section.questions)
          |> Enum.map(fn {question, q_idx} ->
            answer = Map.get(answers, {s_idx, q_idx})
            is_correct = if answer, do: check_answer(question, answer), else: false

            # Record attempt
            if user_role_id && answer do
              Questions.record_attempt_with_stats(%{
                user_role_id: user_role_id,
                question_id: question.id,
                answer_given: answer,
                is_correct: is_correct,
                time_taken_seconds: 0,
                difficulty_at_attempt: to_string(question.difficulty)
              })
            end

            %{question: question, answer: answer, is_correct: is_correct}
          end)

        correct_count = Enum.count(question_results, & &1.is_correct)
        total = length(question_results)

        %{
          name: section.name,
          correct: correct_count,
          total: total,
          score: if(total > 0, do: round(correct_count / total * 100), else: 0),
          points: correct_count * section.points_per_question,
          max_points: total * section.points_per_question,
          question_results: question_results
        }
      end)

    total_correct = Enum.sum(Enum.map(section_results, & &1.correct))
    total_questions = Enum.sum(Enum.map(section_results, & &1.total))
    total_points = Enum.sum(Enum.map(section_results, & &1.points))
    max_points = Enum.sum(Enum.map(section_results, & &1.max_points))

    # Load community stats for all questions
    all_question_ids =
      section_results
      |> Enum.flat_map(fn sr -> Enum.map(sr.question_results, & &1.question.id) end)

    question_stats_map = Questions.get_bulk_question_stats(all_question_ids)

    results = %{
      section_results: section_results,
      total_correct: total_correct,
      total_questions: total_questions,
      total_points: total_points,
      max_points: max_points,
      overall_score:
        if(total_questions > 0, do: round(total_correct / total_questions * 100), else: 0),
      time_taken: time_taken,
      question_stats: question_stats_map
    }

    assign(socket, submitted: true, results: results)
  end

  defp check_answer(question, answer) do
    String.downcase(String.trim(answer)) == String.downcase(String.trim(question.answer))
  end

  defp format_time(nil), do: "No Limit"

  defp format_time(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)

    "#{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(secs), 2, "0")}"
  end

  defp format_elapsed(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}m #{secs}s"
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> Map.put_new(:no_template, false)
      |> Map.put_new(:submitted, false)
      |> Map.put_new(:results, nil)

    ~H"""
    <div class="max-w-3xl mx-auto">
      <.billing_wall
        :if={@billing_blocked}
        course_id={@course_id}
        course_name={(@schedule.course && @schedule.course.name) || "Course"}
        stats={@billing_stats}
      />

      <div :if={!@billing_blocked}>
        <div class="flex items-center justify-between gap-3 mb-4 sm:mb-6">
          <div class="flex items-center gap-3 sm:gap-4 min-w-0">
            <.link
              navigate={~p"/courses/#{@course_id}/tests"}
              class="text-[#8E8E93] hover:text-[#1C1C1E] transition-colors touch-target shrink-0"
            >
              <.icon name="hero-arrow-left" class="w-6 h-6" />
            </.link>
            <div class="min-w-0">
              <h1 class="text-xl sm:text-2xl font-bold text-[#1C1C1E] truncate">{@schedule.name}</h1>
              <p class="text-sm text-[#8E8E93]">Format Practice Test</p>
            </div>
          </div>

          <div
            :if={!@no_template && !@submitted && @remaining_seconds}
            class={"px-4 py-2 rounded-full font-mono font-bold text-lg #{if @remaining_seconds < 60, do: "bg-red-100 text-[#FF3B30]", else: "bg-[#F5F5F7] text-[#1C1C1E]"}"}
          >
            {format_time(@remaining_seconds)}
          </div>
        </div>

        <div :if={@no_template} class="bg-white rounded-2xl shadow-md p-8 text-center">
          <.icon name="hero-document-text" class="w-12 h-12 text-[#8E8E93] mx-auto mb-4" />
          <p class="text-[#8E8E93] text-lg">No format template defined for this test.</p>
          <.link
            navigate={~p"/courses/#{@course_id}/tests/#{@schedule.id}/format"}
            class="inline-block mt-4 bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Define Test Format
          </.link>
        </div>

        <%= if @submitted do %>
          <.render_results results={@results} schedule={@schedule} />
        <% end %>

        <%= if !@no_template && !@submitted do %>
          <.render_test_question
            sections={@sections_with_questions}
            section_index={@current_section_index}
            question_index={@current_question_index}
            selected_answer={@selected_answer}
            answers={@answers}
          />
        <% end %>
      </div>
    </div>
    """
  end

  attr :sections, :list, required: true
  attr :section_index, :integer, required: true
  attr :question_index, :integer, required: true
  attr :selected_answer, :string, default: nil
  attr :answers, :map, required: true

  defp render_test_question(assigns) do
    section = Enum.at(assigns.sections, assigns.section_index)
    question = Enum.at(section.questions, assigns.question_index)
    assigns = assign(assigns, section: section, question: question)

    ~H"""
    <div class="bg-[#E8F8EB] rounded-xl px-4 py-2 mb-4">
      <p class="text-[#4CD964] font-semibold text-sm">
        Section: {@section.name}
      </p>
    </div>

    <div class="bg-white rounded-2xl shadow-md p-8">
      <div class="flex items-center justify-between mb-6">
        <p class="text-sm text-[#8E8E93]">
          Question {@question_index + 1} of {length(@section.questions)}
        </p>
      </div>

      <div class="mb-8">
        <p class="text-lg text-[#1C1C1E] font-medium leading-relaxed">{@question.content}</p>
      </div>

      <%= case @question.question_type do %>
        <% :multiple_choice -> %>
          <.render_mcq question={@question} selected_answer={@selected_answer} />
        <% :true_false -> %>
          <.render_tf selected_answer={@selected_answer} />
        <% _other -> %>
          <.render_text selected_answer={@selected_answer} />
      <% end %>

      <div class="flex justify-between mt-6">
        <button
          phx-click="submit_test"
          data-confirm="Are you sure you want to submit?"
          class="px-6 py-2 border border-[#FF3B30] text-[#FF3B30] font-medium rounded-full hover:bg-red-50 transition-colors"
        >
          Submit Test
        </button>
        <button
          phx-click="save_and_next"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
        >
          Save & Next
        </button>
      </div>
    </div>

    <%!-- Question Navigator --%>
    <div class="bg-white rounded-2xl shadow-md p-4 mt-4">
      <p class="text-xs text-[#8E8E93] mb-2">Question Navigator</p>
      <div class="flex flex-wrap gap-2">
        <div :for={{section, s_idx} <- Enum.with_index(@sections)}>
          <p class="text-xs text-[#8E8E93] mb-1">{section.name}</p>
          <div class="flex flex-wrap gap-1">
            <button
              :for={{_q, q_idx} <- Enum.with_index(section.questions)}
              phx-click="go_to_question"
              phx-value-section={s_idx}
              phx-value-question={q_idx}
              class={[
                "w-8 h-8 rounded-lg text-xs font-medium transition-colors",
                cond do
                  s_idx == @section_index and q_idx == @question_index ->
                    "bg-[#4CD964] text-white"

                  Map.has_key?(@answers, {s_idx, q_idx}) ->
                    "bg-[#E8F8EB] text-[#4CD964]"

                  true ->
                    "bg-[#F5F5F7] text-[#8E8E93]"
                end
              ]}
            >
              {q_idx + 1}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :question, :map, required: true
  attr :selected_answer, :string, default: nil

  defp render_mcq(assigns) do
    options =
      (assigns.question.options || %{})
      |> Enum.sort_by(fn {k, _v} -> k end)
      |> Enum.map(fn {key, value} -> %{key: key, value: value} end)

    assigns = assign(assigns, sorted_options: options)

    ~H"""
    <div class="space-y-3">
      <button
        :for={opt <- @sorted_options}
        type="button"
        phx-click="select_answer"
        phx-value-answer={opt.key}
        class={[
          "w-full text-left p-4 rounded-xl border-2 transition-colors",
          if(@selected_answer == opt.key,
            do: "border-[#4CD964] bg-[#E8F8EB]",
            else: "border-[#E5E5EA] hover:border-[#4CD964] hover:bg-[#F5F5F7]"
          )
        ]}
      >
        <span class="font-medium text-[#1C1C1E]">{opt.key}.</span>
        <span class="ml-2 text-[#1C1C1E]">{opt.value}</span>
      </button>
    </div>
    """
  end

  attr :selected_answer, :string, default: nil

  defp render_tf(assigns) do
    ~H"""
    <div class="flex gap-2 sm:gap-4">
      <button
        :for={value <- ["True", "False"]}
        type="button"
        phx-click="select_answer"
        phx-value-answer={value}
        class={[
          "flex-1 p-3 sm:p-4 rounded-xl border-2 text-center font-medium transition-colors touch-target",
          if(@selected_answer == value,
            do: "border-[#4CD964] bg-[#E8F8EB] text-[#4CD964]",
            else: "border-[#E5E5EA] hover:border-[#4CD964] text-[#1C1C1E]"
          )
        ]}
      >
        {value}
      </button>
    </div>
    """
  end

  attr :selected_answer, :string, default: nil

  defp render_text(assigns) do
    ~H"""
    <div>
      <form phx-change="update_text_answer">
        <textarea
          name="answer"
          placeholder="Type your answer..."
          rows="4"
          class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-xl outline-none transition-colors resize-none"
        >{@selected_answer}</textarea>
      </form>
    </div>
    """
  end

  attr :results, :map, required: true
  attr :schedule, :map, required: true

  defp render_results(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-5 sm:p-8">
      <div class="text-center mb-6 sm:mb-8">
        <.icon
          name="hero-trophy"
          class="w-12 h-12 sm:w-16 sm:h-16 text-[#4CD964] mx-auto mb-3 sm:mb-4"
        />
        <h2 class="text-xl sm:text-2xl font-bold text-[#1C1C1E]">Test Complete!</h2>
        <p class="text-[#8E8E93] mt-2">{@schedule.name}</p>
      </div>

      <div class="grid grid-cols-3 gap-2 sm:gap-4 mb-6 sm:mb-8">
        <div class="bg-[#F5F5F7] rounded-xl p-3 sm:p-4 text-center">
          <p class="text-2xl sm:text-3xl font-bold text-[#4CD964]">{@results.overall_score}%</p>
          <p class="text-[10px] sm:text-xs text-[#8E8E93] mt-1">Overall Score</p>
        </div>
        <div class="bg-[#F5F5F7] rounded-xl p-3 sm:p-4 text-center">
          <p class="text-xl sm:text-3xl font-bold text-[#1C1C1E]">
            {@results.total_points}/{@results.max_points}
          </p>
          <p class="text-[10px] sm:text-xs text-[#8E8E93] mt-1">Points</p>
        </div>
        <div class="bg-[#F5F5F7] rounded-xl p-3 sm:p-4 text-center">
          <p class="text-xl sm:text-3xl font-bold text-[#1C1C1E]">
            {format_elapsed(@results.time_taken)}
          </p>
          <p class="text-xs text-[#8E8E93] mt-1">Time Taken</p>
        </div>
      </div>

      <div class="space-y-3 mb-8">
        <h3 class="font-semibold text-[#1C1C1E]">Results by Section</h3>
        <div
          :for={sr <- @results.section_results}
          class="flex items-center justify-between p-4 bg-[#F5F5F7] rounded-xl"
        >
          <div>
            <p class="font-medium text-[#1C1C1E]">{sr.name}</p>
            <p class="text-xs text-[#8E8E93]">
              {sr.correct}/{sr.total} correct | {sr.points}/{sr.max_points} pts
            </p>
          </div>
          <span class={[
            "px-3 py-1 rounded-full text-sm font-medium",
            if(sr.score >= 70,
              do: "bg-[#E8F8EB] text-[#4CD964]",
              else: "bg-red-100 text-[#FF3B30]"
            )
          ]}>
            {sr.score}%
          </span>
        </div>
      </div>

      <%!-- Question review with community stats --%>
      <div class="space-y-4 mb-8">
        <h3 class="font-semibold text-[#1C1C1E]">Question Review</h3>
        <div :for={sr <- @results.section_results}>
          <p class="text-xs font-medium text-[#8E8E93] uppercase tracking-wide mb-2">{sr.name}</p>
          <div class="space-y-2 mb-4">
            <div
              :for={qr <- sr.question_results}
              class={[
                "p-3 rounded-xl border",
                if(qr.is_correct,
                  do: "border-[#E8F8EB] bg-[#F9FFF9]",
                  else: "border-red-100 bg-red-50/30"
                )
              ]}
            >
              <div class="flex items-start justify-between gap-2">
                <p class="text-sm text-[#1C1C1E] flex-1">{qr.question.content}</p>
                <.icon
                  name={if(qr.is_correct, do: "hero-check-circle", else: "hero-x-circle")}
                  class={[
                    "w-5 h-5 flex-shrink-0",
                    if(qr.is_correct, do: "text-[#4CD964]", else: "text-[#FF3B30]")
                  ]}
                />
              </div>
              <div :if={!qr.is_correct} class="text-xs text-[#8E8E93] mt-1">
                Correct answer: {qr.question.answer}
              </div>
              <% stats = Map.get(@results.question_stats || %{}, qr.question.id) %>
              <div :if={stats} class="flex items-center gap-2 text-xs text-[#8E8E93] mt-2">
                <.icon name="hero-users" class="w-3 h-3" />
                <span>
                  <span class="font-medium">
                    {if stats.total_attempts > 0,
                      do:
                        "#{trunc(Float.round(stats.correct_attempts / stats.total_attempts * 100, 0))}%",
                      else: "0%"}
                  </span>
                  of students got this right ({stats.total_attempts} attempts)
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="flex justify-center gap-4">
        <.link
          navigate={~p"/courses/#{@course_id}/tests"}
          class="px-6 py-2 border border-[#E5E5EA] text-[#1C1C1E] font-medium rounded-full hover:bg-[#F5F5F7] transition-colors"
        >
          Back to Tests
        </.link>
        <.link
          navigate={~p"/courses/#{@course_id}/tests/#{@schedule.id}/format-test"}
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
        >
          Retake Test
        </.link>
      </div>
    </div>
    """
  end
end
