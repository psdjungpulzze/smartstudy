defmodule FunSheepWeb.ExamSimulationLive.Results do
  use FunSheepWeb, :live_view

  alias FunSheep.{Courses, Repo}
  alias FunSheep.Assessments.ExamSimulations
  import Ecto.Query

  @impl true
  def mount(%{"course_id" => course_id, "session_id" => session_id}, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    course = Courses.get_course!(course_id)

    session = ExamSimulations.get_session!(session_id)

    if session.user_role_id != user_role_id do
      {:ok, push_navigate(socket, to: ~p"/dashboard")}
    else
      questions = load_questions(session.question_ids_order || [])
      question_map = Map.new(questions, &{&1.id, &1})

      question_review = build_question_review(session, question_map)
      section_summary = build_section_summary(session)
      insights = build_insights(session, section_summary)

      weak_sections =
        Enum.filter(section_summary, fn s ->
          pct = if s.total > 0, do: s.correct / s.total, else: 0
          pct < 0.70 || s.time_used_seconds > s.time_budget_seconds
        end)

      {:ok,
       assign(socket,
         page_title: "Exam Results — #{course.name}",
         course: course,
         course_id: course_id,
         session: session,
         question_review: question_review,
         section_summary: section_summary,
         insights: insights,
         weak_sections: weak_sections,
         expanded_question: nil
       )}
    end
  end

  @impl true
  def handle_event("toggle_question", %{"index" => i}, socket) do
    idx = String.to_integer(i)
    expanded = if socket.assigns.expanded_question == idx, do: nil, else: idx
    {:noreply, assign(socket, expanded_question: expanded)}
  end

  def handle_event("practice_weak", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/courses/#{socket.assigns.course_id}/practice")}
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp load_questions([]), do: []

  defp load_questions(ids) do
    from(q in FunSheep.Questions.Question, where: q.id in ^ids)
    |> Repo.all()
  end

  defp build_question_review(session, question_map) do
    ids = session.question_ids_order || []
    answers = session.answers || %{}

    ids
    |> Enum.with_index()
    |> Enum.map(fn {qid, idx} ->
      question = Map.get(question_map, qid)
      entry = Map.get(answers, qid, %{})
      your_answer = Map.get(entry, "answer")
      is_correct = Map.get(entry, "is_correct")
      flagged = Map.get(entry, "flagged", false)
      time_spent = Map.get(entry, "time_spent_seconds", 0)

      %{
        index: idx,
        question_id: qid,
        question: question,
        your_answer: your_answer,
        is_correct: is_correct,
        flagged: flagged,
        time_spent_seconds: time_spent,
        answered: your_answer not in [nil, ""]
      }
    end)
  end

  defp build_section_summary(session) do
    boundaries = session.section_boundaries || []
    section_scores = session.section_scores || %{}
    answers = session.answers || %{}
    ids = session.question_ids_order || []

    Enum.map(boundaries, fn sec ->
      name = sec["name"]
      time_budget = sec["time_budget_seconds"] || 0
      start = sec["start_index"]
      count = sec["question_count"]
      section_ids = Enum.slice(ids, start, count)

      scores = Map.get(section_scores, name, %{})
      correct = Map.get(scores, "correct", 0)
      total = Map.get(scores, "total", count)

      time_used =
        Enum.sum(
          Enum.map(section_ids, fn id ->
            get_in(answers, [id, "time_spent_seconds"]) || 0
          end)
        )

      %{
        name: name,
        correct: correct,
        total: total,
        time_used_seconds: time_used,
        time_budget_seconds: time_budget
      }
    end)
  end

  defp build_insights(session, section_summary) do
    insights = []

    insights =
      if session.status == "timed_out" do
        unanswered =
          Enum.count(session.question_ids_order || [], fn id ->
            get_in(session.answers, [id, "answer"]) in [nil, ""]
          end)

        if unanswered > 0 do
          insights ++
            [
              "Time ran out with #{unanswered} unanswered question(s). Consider using the last 5 minutes to answer remaining questions, even if you're unsure."
            ]
        else
          insights
        end
      else
        insights
      end

    over_budget = Enum.filter(section_summary, fn s -> s.time_used_seconds > s.time_budget_seconds end)

    insights =
      if over_budget != [] do
        names = Enum.map_join(over_budget, ", ", & &1.name)

        insights ++
          [
            "You spent more time than budgeted on: #{names}. Try setting a per-question time limit next time."
          ]
      else
        insights
      end

    flagged_not_answered =
      Enum.count(session.answers || %{}, fn {_id, entry} ->
        Map.get(entry, "flagged", false) && Map.get(entry, "answer") in [nil, ""]
      end)

    insights =
      if flagged_not_answered > 0 do
        insights ++
          [
            "#{flagged_not_answered} question(s) were flagged for review but left unanswered. Try to return to flagged questions before the time runs out."
          ]
      else
        insights
      end

    insights
  end

  defp score_pct(nil), do: 0
  defp score_pct(pct), do: round(pct * 100)

  defp section_time_status(used, budget) when budget > 0 do
    ratio = used / budget

    cond do
      ratio > 1.05 -> :over
      ratio < 0.80 -> :under
      true -> :on_track
    end
  end

  defp section_time_status(_, _), do: :on_track

  defp format_time(seconds) do
    m = div(seconds, 60)
    s = rem(seconds, 60)
    if s == 0, do: "#{m}m", else: "#{m}m #{s}s"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto py-8 px-4">
      <div class="mb-6">
        <a href={~p"/courses/#{@course_id}"} class="text-sm text-gray-500 hover:text-gray-700">
          &larr; <%= @course.name %>
        </a>
      </div>

      <!-- Score header -->
      <div class="rounded-2xl bg-white shadow-md overflow-hidden mb-6">
        <div class="bg-slate-800 text-white px-8 py-6 flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold">Exam Results</h1>
            <p class="text-slate-300 mt-1">
              <%= if @session.status == "timed_out", do: "⏰ Time ran out", else: "✅ Submitted" %>
            </p>
          </div>
          <div class="text-center">
            <div class="text-4xl font-bold"><%= score_pct(@session.score_pct) %>%</div>
            <div class="text-slate-300 text-sm mt-1">
              <%= @session.score_correct || 0 %> / <%= @session.score_total || 0 %> correct
            </div>
          </div>
        </div>

        <!-- Section scores -->
        <%= if @section_summary != [] do %>
          <div class="p-6">
            <h2 class="font-semibold text-gray-700 mb-3">Section Breakdown</h2>
            <div class="space-y-3">
              <%= for sec <- @section_summary do %>
                <% pct = if sec.total > 0, do: round(sec.correct / sec.total * 100), else: 0 %>
                <% time_status = section_time_status(sec.time_used_seconds, sec.time_budget_seconds) %>
                <div class="flex items-center justify-between py-2 border-b border-gray-100 last:border-0">
                  <div>
                    <span class="font-medium text-gray-800"><%= sec.name %></span>
                    <span class="text-gray-500 text-sm ml-2">
                      <%= sec.correct %>/<%= sec.total %> (<%= pct %>%)
                    </span>
                  </div>
                  <div class="text-right text-sm">
                    <span class={[
                      "inline-flex items-center gap-1",
                      case time_status do
                        :over -> "text-amber-600"
                        :under -> "text-emerald-600"
                        :on_track -> "text-gray-500"
                      end
                    ]}>
                      ⏱ <%= format_time(sec.time_used_seconds) %>
                      <%= if sec.time_budget_seconds > 0 do %>
                        / <%= format_time(sec.time_budget_seconds) %>
                        <%= case time_status do %>
                          <% :over -> %>
                            <span class="text-amber-500 text-xs">over</span>
                          <% :under -> %>
                            <span class="text-emerald-500 text-xs">under</span>
                          <% _ -> %>
                        <% end %>
                      <% end %>
                    </span>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <!-- Insights -->
      <%= if @insights != [] do %>
        <div class="rounded-2xl bg-amber-50 border border-amber-200 p-5 mb-6">
          <h2 class="font-semibold text-amber-800 mb-2">💡 Insights</h2>
          <ul class="space-y-2">
            <%= for insight <- @insights do %>
              <li class="text-amber-700 text-sm"><%= insight %></li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <!-- Actions -->
      <div class="flex gap-3 mb-8">
        <%= if @weak_sections != [] do %>
          <button
            phx-click="practice_weak"
            class="flex-1 bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium py-3 rounded-full shadow-md"
          >
            Practice Weak Sections &rarr;
          </button>
        <% end %>
        <a
          href={~p"/courses/#{@course_id}/exam-simulation"}
          class="flex-1 text-center border border-gray-300 text-gray-700 hover:bg-gray-50 font-medium py-3 rounded-full"
        >
          Retake Exam
        </a>
        <a
          href={~p"/courses/#{@course_id}"}
          class="flex-1 text-center border border-gray-300 text-gray-700 hover:bg-gray-50 font-medium py-3 rounded-full"
        >
          Back to Course
        </a>
      </div>

      <!-- Question review -->
      <div class="rounded-2xl bg-white shadow-md overflow-hidden">
        <div class="px-6 py-4 border-b border-gray-100">
          <h2 class="font-semibold text-gray-700">Question Review</h2>
        </div>
        <div class="divide-y divide-gray-100">
          <%= for item <- @question_review do %>
            <div class="px-6 py-4">
              <button
                phx-click="toggle_question"
                phx-value-index={item.index}
                class="w-full flex items-center justify-between text-left"
              >
                <div class="flex items-center gap-3">
                  <span class={[
                    "w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0",
                    cond do
                      !item.answered -> "bg-gray-200 text-gray-500"
                      item.is_correct -> "bg-emerald-100 text-emerald-700"
                      true -> "bg-red-100 text-red-700"
                    end
                  ]}>
                    <%= cond do %>
                      <% !item.answered -> %>
                        —
                      <% item.is_correct -> %>
                        ✓
                      <% true -> %>
                        ✗
                    <% end %>
                  </span>
                  <span class="text-gray-700 text-sm">
                    Q<%= item.index + 1 %>
                    <%= if item.question,
                      do:
                        " — #{String.slice(item.question.content, 0, 60)}#{if String.length(item.question.content || "") > 60, do: "...", else: ""}" %>
                  </span>
                  <%= if item.flagged do %>
                    <span class="text-amber-500 text-xs">🚩 Flagged</span>
                  <% end %>
                </div>
                <span class="text-gray-400 text-sm"><%= format_time(item.time_spent_seconds) %></span>
              </button>

              <%= if @expanded_question == item.index && item.question do %>
                <div class="mt-4 ml-9 space-y-2 text-sm">
                  <div class="text-gray-600">
                    <strong>Question:</strong> <%= item.question.content %>
                  </div>
                  <%= if item.answered do %>
                    <div class={if item.is_correct, do: "text-emerald-700", else: "text-red-700"}>
                      <strong>Your answer:</strong> <%= item.your_answer %>
                    </div>
                  <% else %>
                    <div class="text-gray-400">Not answered</div>
                  <% end %>
                  <div class="text-emerald-700">
                    <strong>Correct answer:</strong> <%= item.question.answer %>
                  </div>
                  <%= if item.question.explanation do %>
                    <div class="text-gray-500 bg-gray-50 rounded-lg p-3">
                      <%= item.question.explanation %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
