defmodule FunSheepWeb.DailyChallengeLive do
  use FunSheepWeb, :live_view

  import FunSheepWeb.SheepMascot
  import FunSheepWeb.ShareButton

  alias FunSheep.{Courses, Questions, Gamification}
  alias FunSheep.Engagement.DailyChallenges

  @question_count 5
  @auto_advance_ms 1_500
  @xp_per_correct 20
  @xp_bonus_perfect 50

  @impl true
  def mount(%{"course_id" => course_id}, _session, socket) do
    course = Courses.get_course_with_chapters!(course_id)
    user_role_id = socket.assigns.current_user["user_role_id"]
    {:ok, challenge} = DailyChallenges.get_or_create_today(course_id)

    already_attempted = DailyChallenges.attempt_exists?(user_role_id, challenge.id)

    previous_attempt =
      if already_attempted, do: DailyChallenges.get_user_attempt(user_role_id, challenge.id)

    leaderboard = if already_attempted, do: DailyChallenges.today_leaderboard(course_id), else: []

    socket =
      socket
      |> assign(
        page_title: "Daily Shear: #{course.name}",
        course: course,
        challenge: challenge,
        user_role_id: user_role_id,
        phase: :intro,
        already_attempted: already_attempted,
        previous_attempt: previous_attempt,
        leaderboard: leaderboard,
        # Question phase assigns
        attempt: nil,
        questions: [],
        current_question: nil,
        current_index: 0,
        selected_answer: nil,
        feedback: nil,
        answers: [],
        elapsed_seconds: 0,
        timer_ref: nil,
        # Results phase assigns
        score: 0,
        total_time_ms: 0,
        xp_earned: 0
      )

    {:ok, socket}
  end

  # ── Events ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("share_completed", %{"method" => method}, socket) do
    message = if method == "clipboard", do: "Link copied!", else: "Shared!"
    {:noreply, put_flash(socket, :info, message)}
  end

  def handle_event("start_challenge", _params, socket) do
    %{user_role_id: user_role_id, challenge: challenge} = socket.assigns

    case DailyChallenges.start_attempt(user_role_id, challenge.id) do
      {:ok, attempt} ->
        questions =
          challenge.question_ids
          |> Enum.map(&Questions.get_question!/1)

        [first | _rest] = questions
        timer_ref = Process.send_after(self(), :tick, 1_000)

        socket =
          socket
          |> assign(
            phase: :question,
            attempt: attempt,
            questions: questions,
            current_question: first,
            current_index: 0,
            selected_answer: nil,
            feedback: nil,
            answers: [],
            elapsed_seconds: 0,
            timer_ref: timer_ref
          )

        {:noreply, socket}

      {:error, :already_attempted} ->
        {:noreply, put_flash(socket, :error, "You've already completed today's challenge!")}
    end
  end

  def handle_event("select_answer", %{"answer" => answer}, socket) do
    if socket.assigns.feedback do
      {:noreply, socket}
    else
      {:noreply, assign(socket, selected_answer: answer)}
    end
  end

  def handle_event("update_text_answer", %{"answer" => answer}, socket) do
    if socket.assigns.feedback do
      {:noreply, socket}
    else
      {:noreply, assign(socket, selected_answer: answer)}
    end
  end

  def handle_event("submit_answer", _params, socket) do
    %{
      current_question: question,
      selected_answer: answer,
      attempt: attempt,
      answers: answers
    } = socket.assigns

    if answer == nil or answer == "" or question == nil or socket.assigns.feedback != nil do
      {:noreply, socket}
    else
      is_correct = check_answer(question, answer)

      {:ok, _attempt} =
        DailyChallenges.submit_answer(attempt.id, question.id, answer, is_correct)

      new_answers =
        answers ++ [%{question_id: question.id, answer: answer, is_correct: is_correct}]

      # Schedule auto-advance
      Process.send_after(self(), :auto_advance, @auto_advance_ms)

      {:noreply,
       assign(socket,
         feedback: %{is_correct: is_correct, correct_answer: question.answer},
         answers: new_answers
       )}
    end
  end

  def handle_event("next_question", _params, socket) do
    {:noreply, advance_question(socket)}
  end

  # ── Timer & Auto-Advance ────────────────────────────────────────────────────

  @impl true
  def handle_info(:tick, socket) do
    if socket.assigns.phase == :question do
      timer_ref = Process.send_after(self(), :tick, 1_000)

      {:noreply,
       assign(socket,
         elapsed_seconds: socket.assigns.elapsed_seconds + 1,
         timer_ref: timer_ref
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:auto_advance, socket) do
    if socket.assigns.feedback do
      {:noreply, advance_question(socket)}
    else
      {:noreply, socket}
    end
  end

  # ── Private Helpers ─────────────────────────────────────────────────────────

  defp advance_question(socket) do
    %{
      current_index: idx,
      questions: questions,
      attempt: attempt,
      answers: answers,
      elapsed_seconds: elapsed,
      user_role_id: user_role_id
    } = socket.assigns

    next_idx = idx + 1

    if next_idx < length(questions) do
      next_question = Enum.at(questions, next_idx)

      assign(socket,
        current_index: next_idx,
        current_question: next_question,
        selected_answer: nil,
        feedback: nil
      )
    else
      # Challenge complete
      total_time_ms = elapsed * 1_000

      if socket.assigns.timer_ref do
        Process.cancel_timer(socket.assigns.timer_ref)
      end

      {:ok, _attempt} = DailyChallenges.complete_attempt(attempt.id, total_time_ms)

      score = Enum.count(answers, & &1.is_correct)

      xp_earned =
        score * @xp_per_correct + if(score == @question_count, do: @xp_bonus_perfect, else: 0)

      if xp_earned > 0 do
        Gamification.award_xp(user_role_id, xp_earned, "daily_challenge")
      end

      Gamification.record_activity(user_role_id)

      leaderboard = DailyChallenges.today_leaderboard(socket.assigns.course.id)

      assign(socket,
        phase: :results,
        score: score,
        total_time_ms: total_time_ms,
        xp_earned: xp_earned,
        leaderboard: leaderboard,
        feedback: nil,
        timer_ref: nil
      )
    end
  end

  defp check_answer(question, answer) do
    String.downcase(String.trim(answer)) == String.downcase(String.trim(question.answer))
  end

  defp format_time(seconds) do
    mins = div(seconds, 60)
    secs = rem(seconds, 60)

    "#{String.pad_leading(Integer.to_string(mins), 2, "0")}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp format_time_ms(ms) do
    format_time(div(ms, 1_000))
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

  defp today_display do
    Date.utc_today() |> Calendar.strftime("%B %d, %Y")
  end

  # ── Render ─────────────────────────────────────────────────────────────────

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
            <h1 class="text-2xl font-bold text-[#1C1C1E]">Daily Shear</h1>
            <p class="text-sm text-[#8E8E93]">{@course.name}</p>
          </div>
        </div>

        <%!-- Timer (during question phase) --%>
        <div
          :if={@phase == :question}
          class="flex items-center gap-2 bg-[#F5F5F7] rounded-full px-4 py-2"
        >
          <.icon name="hero-clock" class="w-5 h-5 text-[#8E8E93]" />
          <span class="font-mono text-lg font-semibold text-[#1C1C1E]">
            {format_time(@elapsed_seconds)}
          </span>
        </div>
      </div>

      <%!-- Phase: Intro --%>
      <div
        :if={@phase == :intro && !@already_attempted}
        class="bg-white rounded-2xl shadow-md p-8 text-center"
      >
        <div class="mb-6">
          <.sheep state={:flash_card} size="xl" />
        </div>

        <p class="text-sm text-[#8E8E93] mb-2">{today_display()}</p>
        <h2 class="text-2xl font-bold text-[#1C1C1E] mb-2">Today's Daily Shear</h2>
        <p class="text-[#8E8E93] mb-8">{@course.name}</p>

        <div class="bg-[#F5F5F7] rounded-xl p-4 mb-8 max-w-sm mx-auto">
          <div class="flex items-center justify-center gap-6 text-sm">
            <div class="flex items-center gap-2">
              <.icon name="hero-question-mark-circle" class="w-5 h-5 text-[#4CD964]" />
              <span class="text-[#1C1C1E] font-medium">5 questions</span>
            </div>
            <div class="flex items-center gap-2">
              <.icon name="hero-clock" class="w-5 h-5 text-[#4CD964]" />
              <span class="text-[#1C1C1E] font-medium">Timed</span>
            </div>
            <div class="flex items-center gap-2">
              <.icon name="hero-bolt" class="w-5 h-5 text-[#4CD964]" />
              <span class="text-[#1C1C1E] font-medium">One shot!</span>
            </div>
          </div>
        </div>

        <button
          phx-click="start_challenge"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-8 py-3 rounded-full shadow-md transition-colors text-lg"
        >
          Start Challenge
        </button>
      </div>

      <%!-- Phase: Intro (already attempted) --%>
      <div :if={@phase == :intro && @already_attempted} class="space-y-6">
        <div class="bg-white rounded-2xl shadow-md p-8 text-center">
          <div class="mb-4">
            <.sheep
              state={
                if(@previous_attempt && @previous_attempt.score >= 4,
                  do: :celebrating,
                  else: :encouraging
                )
              }
              size="lg"
            />
          </div>

          <p class="text-sm text-[#8E8E93] mb-2">{today_display()}</p>
          <h2 class="text-xl font-bold text-[#1C1C1E] mb-2">Already Completed!</h2>
          <p class="text-[#8E8E93] mb-6">You've already taken today's Daily Shear.</p>

          <div :if={@previous_attempt} class="bg-[#F5F5F7] rounded-xl p-6 mb-6 max-w-xs mx-auto">
            <p class="text-4xl font-bold text-[#4CD964]">
              {@previous_attempt.score}/{@question_count}
            </p>
            <p class="text-sm text-[#8E8E93] mt-1">
              in {format_time_ms(@previous_attempt.total_time_ms)}
            </p>
          </div>

          <p class="text-sm text-[#8E8E93]">Come back tomorrow for a new challenge!</p>
        </div>

        <%!-- Leaderboard --%>
        <.render_leaderboard
          leaderboard={@leaderboard}
          user_role_id={@user_role_id}
        />
      </div>

      <%!-- Phase: Question --%>
      <div :if={@phase == :question && @current_question} class="space-y-6">
        <%!-- Progress dots --%>
        <div class="flex items-center justify-center gap-3">
          <span class="text-sm text-[#8E8E93] mr-2">
            Question {@current_index + 1} of {@question_count}
          </span>
          <div
            :for={i <- 0..(@question_count - 1)}
            class={[
              "w-3 h-3 rounded-full transition-colors",
              cond do
                i < length(@answers) && Enum.at(@answers, i).is_correct -> "bg-[#4CD964]"
                i < length(@answers) -> "bg-[#FF3B30]"
                i == @current_index -> "bg-[#4CD964] ring-2 ring-[#4CD964] ring-offset-2"
                true -> "bg-[#E5E5EA]"
              end
            ]}
          />
        </div>

        <%!-- Question card --%>
        <div class="bg-white rounded-2xl shadow-md p-8">
          <div class="flex items-center justify-between mb-6">
            <p class="text-sm text-[#8E8E93]">
              Question {@current_index + 1}
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
                {if @current_index + 1 < @question_count, do: "Next Question", else: "See Results"}
              </button>
            </div>
          </div>

          <%!-- Submit button --%>
          <div :if={@feedback == nil} class="flex justify-end mt-6">
            <button
              phx-click="submit_answer"
              disabled={@selected_answer == nil || @selected_answer == ""}
              class={[
                "font-medium px-6 py-2 rounded-full shadow-md transition-colors",
                if(@selected_answer && @selected_answer != "",
                  do: "bg-[#4CD964] hover:bg-[#3DBF55] text-white",
                  else: "bg-[#E5E5EA] text-[#8E8E93] cursor-not-allowed"
                )
              ]}
            >
              Submit Answer
            </button>
          </div>
        </div>
      </div>

      <%!-- Phase: Results --%>
      <div :if={@phase == :results} class="space-y-6">
        <div class="bg-white rounded-2xl shadow-md p-8">
          <div class="text-center mb-8">
            <div class="mb-4">
              <.sheep
                state={if(@score >= 4, do: :celebrating, else: :encouraging)}
                size="lg"
                message={result_message(@score)}
              />
            </div>

            <h2 class="text-2xl font-bold text-[#1C1C1E] mb-1">
              {if @score == @question_count, do: "Perfect Score!", else: "Challenge Complete!"}
            </h2>
            <p class="text-sm text-[#8E8E93]">{@course.name} | {today_display()}</p>
          </div>

          <%!-- Score display --%>
          <div class="bg-[#F5F5F7] rounded-xl p-6 mb-6">
            <div class="flex items-center justify-center gap-8">
              <div class="text-center">
                <p class="text-5xl font-bold text-[#4CD964]">{@score}/{@question_count}</p>
                <p class="text-sm text-[#8E8E93] mt-1">Score</p>
              </div>
              <div class="w-px h-16 bg-[#E5E5EA]" />
              <div class="text-center">
                <p class="text-3xl font-bold text-[#1C1C1E]">{format_time_ms(@total_time_ms)}</p>
                <p class="text-sm text-[#8E8E93] mt-1">Time</p>
              </div>
            </div>
          </div>

          <%!-- XP earned --%>
          <div class="bg-[#E8F8EB] rounded-xl p-4 mb-6 flex items-center justify-center gap-3">
            <.icon name="hero-star" class="w-6 h-6 text-[#4CD964]" />
            <span class="text-lg font-semibold text-[#4CD964]">+{@xp_earned} XP earned!</span>
          </div>

          <%!-- Answer summary dots --%>
          <div class="flex items-center justify-center gap-3 mb-6">
            <div
              :for={answer <- @answers}
              class={[
                "w-4 h-4 rounded-full",
                if(answer.is_correct, do: "bg-[#4CD964]", else: "bg-[#FF3B30]")
              ]}
            />
          </div>

          <div class="flex justify-center gap-3">
            <.share_button
              title={"Daily Shear - #{@course.name}"}
              text={"I scored #{@score}/#{@question_count} on today's Daily Shear challenge in #{@course.name}! Can you beat me?"}
              url={share_url(~p"/courses/#{@course.id}/daily-shear")}
              label="Share Result"
            />
            <.link
              navigate={~p"/dashboard"}
              class="px-6 py-2 border border-[#E5E5EA] text-[#1C1C1E] font-medium rounded-full hover:bg-[#F5F5F7] transition-colors"
            >
              Back to Dashboard
            </.link>
          </div>
        </div>

        <%!-- Leaderboard --%>
        <.render_leaderboard
          leaderboard={@leaderboard}
          user_role_id={@user_role_id}
        />
      </div>
    </div>
    """
  end

  # ── Sub-Components ──────────────────────────────────────────────────────────

  defp result_message(5), do: "PERFECT! You're on fire!"
  defp result_message(4), do: "So close to perfect!"
  defp result_message(score) when score >= 3, do: "Nice work, keep it up!"
  defp result_message(_), do: "Practice makes perfect!"

  attr :leaderboard, :list, required: true
  attr :user_role_id, :string, required: true

  defp render_leaderboard(assigns) do
    ~H"""
    <div :if={length(@leaderboard) > 0} class="bg-white rounded-2xl shadow-md p-6">
      <h3 class="text-lg font-bold text-[#1C1C1E] mb-4 flex items-center gap-2">
        <.icon name="hero-trophy" class="w-5 h-5 text-[#4CD964]" /> Today's Leaderboard
      </h3>

      <div class="divide-y divide-[#F5F5F7]">
        <div
          :for={entry <- Enum.take(@leaderboard, 10)}
          class={[
            "flex items-center justify-between py-3 px-3 rounded-lg",
            if(Map.get(entry, :user_role_id) == @user_role_id, do: "bg-[#E8F8EB]", else: "")
          ]}
        >
          <div class="flex items-center gap-3">
            <span class={[
              "w-7 h-7 rounded-full flex items-center justify-center text-sm font-bold",
              case entry.rank do
                1 -> "bg-yellow-100 text-yellow-700"
                2 -> "bg-gray-100 text-gray-600"
                3 -> "bg-orange-100 text-orange-700"
                _ -> "bg-[#F5F5F7] text-[#8E8E93]"
              end
            ]}>
              {entry.rank}
            </span>
            <span class="font-medium text-[#1C1C1E]">{entry.display_name}</span>
          </div>

          <div class="flex items-center gap-4 text-sm">
            <span class="font-semibold text-[#4CD964]">{entry.score}/{@question_count}</span>
            <span class="text-[#8E8E93]">{format_time_ms(entry.total_time_ms)}</span>
          </div>
        </div>
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
end
