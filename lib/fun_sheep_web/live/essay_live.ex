defmodule FunSheepWeb.EssayLive do
  @moduledoc """
  LiveView for timed essay practice.

  Route: `/courses/:course_id/essay/:question_id`

  Two-panel layout:
  - Left: essay prompt + optional rubric guide toggle
  - Right: textarea, word count, save indicator, submit button

  When `grading: true`: spinner overlay over textarea.
  When `grade_result` present: replace textarea with `EssayFeedbackCard`.
  When `premium_required: true`: locked overlay with upgrade CTA.
  """

  use FunSheepWeb, :live_view

  require Logger

  alias FunSheep.{Essays, Questions, Billing, Courses}
  alias FunSheep.Workers.EssayGradingWorker

  ## Mount

  @impl true
  def mount(%{"course_id" => course_id, "question_id" => question_id} = params, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    schedule_id = params["schedule_id"]

    question =
      Questions.get_question!(question_id)
      |> FunSheep.Repo.preload(:essay_rubric_template)

    course = Courses.get_course!(course_id)

    premium_required = not Billing.subscription_has_essay_grading?(user_role_id)

    {draft, subscribed_draft_id} =
      if premium_required do
        {nil, nil}
      else
        {:ok, draft} = Essays.get_or_create_draft(user_role_id, question_id, schedule_id)

        if connected?(socket) do
          Phoenix.PubSub.subscribe(FunSheep.PubSub, "essay_grading:#{draft.id}")
        end

        {draft, draft.id}
      end

    socket =
      socket
      |> assign(:course, course)
      |> assign(:question, question)
      |> assign(:draft, draft)
      |> assign(:draft_id, subscribed_draft_id)
      |> assign(:schedule_id, schedule_id)
      |> assign(:user_role_id, user_role_id)
      |> assign(:body, if(draft, do: draft.body, else: ""))
      |> assign(:word_count, if(draft, do: draft.word_count, else: 0))
      |> assign(:time_elapsed, if(draft, do: draft.time_elapsed_seconds, else: 0))
      |> assign(:last_saved_at, if(draft, do: draft.last_saved_at, else: nil))
      |> assign(:grading, false)
      |> assign(:grade_result, nil)
      |> assign(:show_rubric, false)
      |> assign(:premium_required, premium_required)
      |> assign(:page_title, "Essay: #{String.slice(question.content, 0, 60)}")

    {:ok, socket}
  end

  ## Events

  @impl true
  def handle_event("essay_draft_changed", %{"body" => body}, socket) do
    word_count = count_words(body)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Upsert draft asynchronously — don't block the UI
    user_role_id = socket.assigns.user_role_id
    question_id = socket.assigns.question.id
    schedule_id = socket.assigns.schedule_id
    elapsed = socket.assigns.time_elapsed

    Task.start(fn ->
      Essays.upsert_draft(user_role_id, question_id, body,
        schedule_id: schedule_id,
        word_count: word_count,
        time_elapsed_seconds: elapsed
      )
    end)

    socket =
      socket
      |> assign(:body, body)
      |> assign(:word_count, word_count)
      |> assign(:last_saved_at, now)

    {:noreply, socket}
  end

  def handle_event("heartbeat", %{"elapsed" => elapsed}, socket) when is_integer(elapsed) do
    {:noreply, assign(socket, :time_elapsed, elapsed)}
  end

  def handle_event("heartbeat", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("toggle_rubric", _params, socket) do
    {:noreply, assign(socket, :show_rubric, not socket.assigns.show_rubric)}
  end

  def handle_event("submit_essay", _params, socket) do
    body = socket.assigns.body

    if blank?(body) do
      {:noreply, put_flash(socket, :error, "Please write your essay before submitting.")}
    else
      question = socket.assigns.question
      user_role_id = socket.assigns.user_role_id

      # Ensure the latest body is saved before grading
      Essays.upsert_draft(user_role_id, question.id, body,
        schedule_id: socket.assigns.schedule_id,
        word_count: socket.assigns.word_count,
        time_elapsed_seconds: socket.assigns.time_elapsed
      )

      {:ok, refreshed_draft} =
        Essays.get_or_create_draft(user_role_id, question.id, socket.assigns.schedule_id)

      EssayGradingWorker.enqueue(refreshed_draft.id, question.id, user_role_id)

      {:noreply, assign(socket, :grading, true)}
    end
  end

  def handle_event("try_again", _params, socket) do
    # Clears the current grade result and creates a new draft for the same question
    user_role_id = socket.assigns.user_role_id
    question_id = socket.assigns.question.id
    schedule_id = socket.assigns.schedule_id

    {:ok, new_draft} = Essays.get_or_create_draft(user_role_id, question_id, schedule_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(FunSheep.PubSub, "essay_grading:#{new_draft.id}")
    end

    socket =
      socket
      |> assign(:draft, new_draft)
      |> assign(:draft_id, new_draft.id)
      |> assign(:body, new_draft.body)
      |> assign(:word_count, new_draft.word_count)
      |> assign(:grading, false)
      |> assign(:grade_result, nil)
      |> assign(:last_saved_at, new_draft.last_saved_at)

    {:noreply, socket}
  end

  ## PubSub

  @impl true
  def handle_info({:essay_graded, result}, socket) do
    socket =
      socket
      |> assign(:grading, false)
      |> assign(:grade_result, result)

    {:noreply, socket}
  end

  ## Render

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F5F5] dark:bg-[#1E1E1E]">
      <!-- Header -->
      <div class="bg-white dark:bg-[#2D2D2D] border-b border-gray-200 dark:border-gray-700 px-6 py-4">
        <div class="max-w-6xl mx-auto flex items-center justify-between">
          <div>
            <.link
              navigate={"/courses/#{@course.id}"}
              class="text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
            >
              ← {@course.name}
            </.link>
            <h1 class="text-xl font-semibold text-gray-900 dark:text-white mt-1">Essay Practice</h1>
          </div>
          <%= if @draft && @time_elapsed > 0 do %>
            <div class="text-sm text-gray-500 dark:text-gray-400">
              Time: {format_elapsed(@time_elapsed)}
            </div>
          <% end %>
        </div>
      </div>

      <%= if @premium_required do %>
        <!-- Premium gate -->
        <div class="max-w-2xl mx-auto mt-24 px-6 text-center">
          <div class="bg-white dark:bg-[#2D2D2D] rounded-2xl shadow-md p-10">
            <div class="w-16 h-16 bg-[#4CD964]/10 rounded-full flex items-center justify-center mx-auto mb-6">
              <svg
                class="w-8 h-8 text-[#4CD964]"
                fill="none"
                stroke="currentColor"
                stroke-width="1.5"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z"
                />
              </svg>
            </div>
            <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-3">AI Essay Grading</h2>
            <p class="text-gray-500 dark:text-gray-400 mb-8">
              Essay grading uses Claude AI to score your writing against rubric criteria.
              Upgrade to unlock detailed feedback on thesis, evidence, and style.
            </p>
            <.link
              navigate="/subscription"
              class="inline-flex items-center px-8 py-3 bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium rounded-full shadow-md transition-colors"
            >
              Upgrade to Premium
            </.link>
          </div>
        </div>
      <% else %>
        <!-- Main essay interface -->
        <div class="max-w-6xl mx-auto px-6 py-8">
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <!-- Left panel: prompt + rubric -->
            <div class="space-y-4">
              <!-- Question prompt -->
              <div class="bg-white dark:bg-[#2D2D2D] rounded-2xl shadow-md p-6">
                <h2 class="text-sm font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-3">
                  Essay Prompt
                </h2>
                <p class="text-gray-900 dark:text-white leading-relaxed">{@question.content}</p>

                <%= if @question.essay_word_target do %>
                  <p class="mt-3 text-sm text-gray-500 dark:text-gray-400">
                    Target: ~{@question.essay_word_target} words
                  </p>
                <% end %>

                <%= if @question.essay_time_limit_minutes do %>
                  <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                    Suggested time: {@question.essay_time_limit_minutes} minutes
                  </p>
                <% end %>
              </div>
              
    <!-- Rubric guide toggle -->
              <%= if @question.essay_rubric_template do %>
                <div class="bg-white dark:bg-[#2D2D2D] rounded-2xl shadow-md overflow-hidden">
                  <button
                    phx-click="toggle_rubric"
                    class="w-full flex items-center justify-between px-6 py-4 text-left"
                  >
                    <span class="font-medium text-gray-900 dark:text-white">
                      Scoring Rubric — {@question.essay_rubric_template.name}
                    </span>
                    <svg
                      class={"w-5 h-5 text-gray-400 transition-transform #{if @show_rubric, do: "rotate-180"}"}
                      fill="none"
                      stroke="currentColor"
                      stroke-width="1.5"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="M19.5 8.25l-7.5 7.5-7.5-7.5"
                      />
                    </svg>
                  </button>
                  <%= if @show_rubric do %>
                    <div class="px-6 pb-6 border-t border-gray-100 dark:border-gray-700">
                      <p class="text-sm text-gray-500 dark:text-gray-400 mt-4 mb-3">
                        Max score: <strong>{@question.essay_rubric_template.max_score}</strong>
                        points.
                        Mastery threshold: <strong><%= round(@question.essay_rubric_template.mastery_threshold_ratio * 100) %>%</strong>.
                      </p>
                      <div class="space-y-3">
                        <%= for criterion <- normalize_criteria(@question.essay_rubric_template.criteria) do %>
                          <div class="flex gap-3">
                            <span class="flex-shrink-0 inline-flex items-center justify-center w-8 h-8 rounded-full bg-[#4CD964]/10 text-[#4CD964] text-sm font-semibold">
                              {criterion["max_points"]}
                            </span>
                            <div>
                              <p class="font-medium text-gray-900 dark:text-white text-sm">
                                {criterion["name"]}
                              </p>
                              <p class="text-gray-500 dark:text-gray-400 text-sm">
                                {criterion["description"]}
                              </p>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
            
    <!-- Right panel: textarea / result -->
            <div class="relative">
              <%= if @grade_result do %>
                <!-- Feedback card -->
                <.essay_feedback_card
                  result={@grade_result}
                  rubric={@question.essay_rubric_template}
                />
                <div class="mt-4">
                  <button
                    phx-click="try_again"
                    class="w-full flex items-center justify-center gap-2 px-6 py-3 bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium rounded-full shadow-md transition-colors"
                  >
                    Try Again →
                  </button>
                </div>
              <% else %>
                <!-- Writing area -->
                <div class="bg-white dark:bg-[#2D2D2D] rounded-2xl shadow-md overflow-hidden">
                  <div class="relative">
                    <textarea
                      id="essay-body"
                      phx-debounce="2000"
                      phx-change="essay_draft_changed"
                      name="body"
                      rows="20"
                      placeholder="Start writing your essay here..."
                      disabled={@grading}
                      class="w-full p-6 text-gray-900 dark:text-white bg-transparent border-0 focus:ring-0 resize-none font-serif text-lg leading-relaxed placeholder-gray-300 dark:placeholder-gray-600"
                    ><%= @body %></textarea>
                    
    <!-- Grading overlay -->
                    <%= if @grading do %>
                      <div class="absolute inset-0 bg-white/80 dark:bg-[#2D2D2D]/80 flex flex-col items-center justify-center rounded-2xl">
                        <div class="animate-spin w-10 h-10 border-4 border-[#4CD964] border-t-transparent rounded-full mb-4">
                        </div>
                        <p class="text-gray-700 dark:text-gray-300 font-medium">
                          Grading your essay...
                        </p>
                        <p class="text-sm text-gray-500 dark:text-gray-400 mt-1">
                          This takes about 15 seconds
                        </p>
                      </div>
                    <% end %>
                  </div>
                  
    <!-- Footer: word count + save + submit -->
                  <div class="border-t border-gray-100 dark:border-gray-700 px-6 py-4 flex items-center justify-between">
                    <div class="flex items-center gap-4 text-sm text-gray-500 dark:text-gray-400">
                      <span>{@word_count} words</span>
                      <%= if @last_saved_at do %>
                        <span class="flex items-center gap-1">
                          <svg class="w-3 h-3 text-[#4CD964]" fill="currentColor" viewBox="0 0 20 20">
                            <path
                              fill-rule="evenodd"
                              d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                              clip-rule="evenodd"
                            />
                          </svg>
                          Saved
                        </span>
                      <% end %>
                    </div>

                    <button
                      phx-click="submit_essay"
                      disabled={@grading or blank?(@body)}
                      class={"px-6 py-2 font-medium rounded-full transition-colors shadow-sm #{if @grading or blank?(@body), do: "bg-gray-200 text-gray-400 cursor-not-allowed", else: "bg-[#4CD964] hover:bg-[#3DBF55] text-white"}"}
                    >
                      Submit for Grading
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  ## Components

  attr :result, :map, required: true
  attr :rubric, :any, default: nil

  defp essay_feedback_card(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2D2D2D] rounded-2xl shadow-md overflow-hidden">
      <!-- Score header -->
      <div class={"p-6 #{score_bg_class(@result.total_score, @result.max_score, @rubric)}"}>
        <div class="flex items-center gap-4">
          <div class="text-4xl font-bold text-white">
            {@result.total_score}<span class="text-2xl font-normal">/<%= @result.max_score %></span>
          </div>
          <div>
            <p class="text-white font-semibold text-lg">
              {score_label(@result.total_score, @result.max_score, @rubric)}
            </p>
            <p class="text-white/80 text-sm">{score_descriptor(@result)}</p>
          </div>
        </div>
      </div>

      <div class="p-6 space-y-6">
        <!-- Overall feedback -->
        <%= if @result.feedback != "" do %>
          <div>
            <h3 class="font-semibold text-gray-900 dark:text-white mb-2">Overall Feedback</h3>
            <p class="text-gray-700 dark:text-gray-300 leading-relaxed">{@result.feedback}</p>
          </div>
        <% end %>
        
    <!-- Strengths -->
        <%= if @result.strengths != [] do %>
          <div>
            <h3 class="font-semibold text-gray-900 dark:text-white mb-2">Strengths</h3>
            <ul class="space-y-1">
              <%= for strength <- @result.strengths do %>
                <li class="flex items-start gap-2 text-gray-700 dark:text-gray-300 text-sm">
                  <span class="text-[#4CD964] mt-0.5">✓</span>
                  {strength}
                </li>
              <% end %>
            </ul>
          </div>
        <% end %>
        
    <!-- Areas for improvement -->
        <%= if @result.improvements != [] do %>
          <div>
            <h3 class="font-semibold text-gray-900 dark:text-white mb-2">Areas for Improvement</h3>
            <ul class="space-y-1">
              <%= for improvement <- @result.improvements do %>
                <li class="flex items-start gap-2 text-gray-700 dark:text-gray-300 text-sm">
                  <span class="text-orange-400 mt-0.5">→</span>
                  {improvement}
                </li>
              <% end %>
            </ul>
          </div>
        <% end %>
        
    <!-- Per-criterion breakdown -->
        <%= if @result.criteria != [] do %>
          <details class="group">
            <summary class="cursor-pointer font-semibold text-gray-900 dark:text-white flex items-center gap-2 select-none">
              <svg
                class="w-4 h-4 transition-transform group-open:rotate-90"
                fill="none"
                stroke="currentColor"
                stroke-width="1.5"
                viewBox="0 0 24 24"
              >
                <path stroke-linecap="round" stroke-linejoin="round" d="M8.25 4.5l7.5 7.5-7.5 7.5" />
              </svg>
              Criterion Breakdown
            </summary>
            <div class="mt-3 space-y-3">
              <%= for criterion <- @result.criteria do %>
                <div class="bg-gray-50 dark:bg-gray-800 rounded-lg p-3">
                  <div class="flex items-center justify-between mb-1">
                    <span class="font-medium text-gray-900 dark:text-white text-sm">
                      {criterion.name}
                    </span>
                    <span class={["text-sm font-semibold", criterion_score_class(criterion)]}>
                      {criterion.earned}/{criterion.max}
                    </span>
                  </div>
                  <%= if criterion.comment != "" do %>
                    <p class="text-gray-500 dark:text-gray-400 text-sm">{criterion.comment}</p>
                  <% end %>
                </div>
              <% end %>
            </div>
          </details>
        <% end %>
      </div>
    </div>
    """
  end

  ## Helpers

  defp count_words(nil), do: 0

  defp count_words(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 == ""))
    |> length()
  end

  defp blank?(nil), do: true
  defp blank?(text) when is_binary(text), do: String.trim(text) == ""

  defp format_elapsed(seconds) when is_integer(seconds) do
    mins = div(seconds, 60)
    secs = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B", [mins, secs]) |> to_string()
  end

  defp format_elapsed(_), do: "0:00"

  defp normalize_criteria(criteria) when is_list(criteria), do: criteria
  defp normalize_criteria(_), do: []

  defp score_ratio(total, max) when is_integer(max) and max > 0, do: total / max
  defp score_ratio(_, _), do: 0.0

  defp mastery_threshold(nil), do: 0.67
  defp mastery_threshold(%{mastery_threshold_ratio: r}) when is_float(r), do: r
  defp mastery_threshold(_), do: 0.67

  defp score_bg_class(total, max, rubric) do
    ratio = score_ratio(total, max)
    threshold = mastery_threshold(rubric)

    cond do
      ratio >= threshold -> "bg-[#4CD964]"
      ratio >= 0.5 -> "bg-[#FFCC00]"
      true -> "bg-[#FF3B30]"
    end
  end

  defp score_label(total, max, rubric) do
    ratio = score_ratio(total, max)
    threshold = mastery_threshold(rubric)

    cond do
      ratio >= threshold -> "Mastered"
      ratio >= 0.5 -> "Developing"
      true -> "Needs Work"
    end
  end

  defp score_descriptor(%{is_correct: true}),
    do: "You've demonstrated mastery of this essay type."

  defp score_descriptor(%{is_correct: false}),
    do: "Review the feedback and try again to build mastery."

  defp criterion_score_class(%{earned: earned, max: max}) when is_integer(max) and max > 0 do
    ratio = earned / max

    cond do
      ratio >= 1.0 -> "text-[#4CD964]"
      ratio >= 0.5 -> "text-[#FFCC00]"
      true -> "text-[#FF3B30]"
    end
  end

  defp criterion_score_class(_), do: "text-gray-500"
end
