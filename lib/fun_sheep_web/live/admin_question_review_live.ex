defmodule FunSheepWeb.AdminQuestionReviewLive do
  @moduledoc """
  Admin question management: review flagged questions and manage all questions
  regardless of validation status.

  Per-card actions:
    * Approve — mark passed (student-visible)
    * Reject  — mark failed (hidden from students)
    * Edit & Approve — apply corrections and approve in one step
    * Delete — permanently remove the question (audit-logged)

  A status filter lets admins browse all questions, not just the review queue.
  """

  use FunSheepWeb, :live_view

  alias FunSheep.{Admin, Questions}
  alias FunSheep.Questions.Question

  @statuses [
    {"Review queue", :needs_review},
    {"Passed", :passed},
    {"Failed", :failed},
    {"Pending", :pending},
    {"All", nil}
  ]

  @tiers [
    {"All tiers", nil},
    {"Tier 1 — Official", 1},
    {"Tier 2 — Reputable", 2},
    {"Tier 3 — Unknown", 3},
    {"Tier 4 — Low quality", 4}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Question Review",
       editing_id: nil,
       status_filter: :needs_review,
       tier_filter: nil
     )
     |> load_queue()}
  end

  @impl true
  def handle_event("filter_status", %{"status" => raw}, socket) do
    status =
      case raw do
        "needs_review" -> :needs_review
        "passed" -> :passed
        "failed" -> :failed
        "pending" -> :pending
        _ -> nil
      end

    {:noreply,
     socket
     |> assign(status_filter: status, editing_id: nil)
     |> load_queue()}
  end

  def handle_event("filter_tier", %{"tier" => raw}, socket) do
    tier =
      case Integer.parse(raw) do
        {n, ""} when n in 1..4 -> n
        _ -> nil
      end

    {:noreply,
     socket
     |> assign(tier_filter: tier, editing_id: nil)
     |> load_queue()}
  end

  def handle_event("bulk_approve_tier1", _params, socket) do
    case Questions.bulk_approve_web_tier1_questions(reviewer_id(socket)) do
      {:ok, 0} ->
        {:noreply, put_flash(socket, :info, "No Tier 1 questions in the review queue.")}

      {:ok, count} ->
        {:noreply,
         socket
         |> put_flash(:info, "Bulk approved #{count} Tier 1 web-scraped question(s).")
         |> load_queue()}
    end
  end

  def handle_event("approve", %{"id" => id}, socket) do
    question = Questions.get_question!(id)

    case Questions.admin_approve_question(question, reviewer_id(socket)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Question approved and published.")
         |> load_queue()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to approve question.")}
    end
  end

  def handle_event("reject", %{"id" => id}, socket) do
    question = Questions.get_question!(id)

    case Questions.admin_reject_question(question, reviewer_id(socket)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Question rejected and hidden from students.")
         |> load_queue()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to reject question.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    question = Questions.get_question!(id)

    case Admin.admin_delete_question(question, socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Question deleted.")
         |> load_queue()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete question.")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_id: id)}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, editing_id: nil)}
  end

  def handle_event("save_edit", %{"id" => id, "question" => attrs}, socket) do
    question = Questions.get_question!(id)
    parsed = parse_edit_attrs(attrs)

    case Questions.admin_edit_and_approve(question, parsed, reviewer_id(socket)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(editing_id: nil)
         |> put_flash(:info, "Question updated and approved.")
         |> load_queue()}

      {:error, changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Save failed: #{inspect(changeset.errors)}"
         )}
    end
  end

  defp parse_edit_attrs(%{"content" => content, "answer" => answer} = attrs) do
    %{
      content: content,
      answer: answer,
      explanation: Map.get(attrs, "explanation", "")
    }
  end

  defp parse_edit_attrs(attrs), do: attrs

  defp load_queue(socket) do
    status = socket.assigns.status_filter
    tier = socket.assigns.tier_filter
    questions = Questions.list_all_questions_for_admin(status, tier)
    counts = Questions.count_questions_by_status()
    assign(socket, questions: questions, queue_count: length(questions), status_counts: counts)
  end

  defp reviewer_id(socket) do
    case socket.assigns[:current_user] do
      %{"user_role_id" => id} -> id
      %{"id" => id} -> id
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:statuses, @statuses)
      |> assign(:tiers, @tiers)

    ~H"""
    <div class="max-w-5xl mx-auto p-6">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold text-[#1C1C1E]">Questions</h1>
          <p class="text-sm text-[#8E8E93] mt-1">
            Review, edit, approve, reject, or delete questions.
          </p>
        </div>
        <div class="flex items-center gap-3">
          <button
            :if={@status_filter == :needs_review}
            type="button"
            phx-click="bulk_approve_tier1"
            data-confirm="Bulk approve all Tier 1 (official source) web-scraped questions in the review queue?"
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-5 py-2 rounded-full shadow-md transition-colors text-sm"
          >
            Bulk approve Tier 1
          </button>
          <div class="bg-white rounded-2xl shadow-md px-4 py-2">
            <span class="text-2xl font-bold text-[#4CD964]">{@queue_count}</span>
            <span class="text-sm text-[#8E8E93] ml-1">shown</span>
          </div>
        </div>
      </div>

      <%!-- Status filter tabs --%>
      <div class="bg-white rounded-2xl shadow-md p-3 mb-3 flex items-center gap-2 flex-wrap">
        <button
          :for={{label, status} <- @statuses}
          type="button"
          phx-click="filter_status"
          phx-value-status={status || "all"}
          class={[
            "px-3 py-1.5 rounded-full text-xs font-medium border transition-colors",
            if(@status_filter == status,
              do: "bg-[#4CD964] text-white border-[#4CD964]",
              else: "bg-white text-[#1C1C1E] border-[#E5E5EA] hover:border-[#4CD964]/40"
            )
          ]}
        >
          {label}
          <span :if={status && Map.get(@status_counts, status, 0) > 0} class="ml-1 opacity-75">
            ({Map.get(@status_counts, status, 0)})
          </span>
          <span :if={is_nil(status)} class="ml-1 opacity-75">
            ({@status_counts |> Map.values() |> Enum.sum()})
          </span>
        </button>
      </div>

      <%!-- Source tier filter --%>
      <div class="bg-white rounded-2xl shadow-md p-3 mb-4 flex items-center gap-2 flex-wrap">
        <span class="text-xs font-semibold text-[#8E8E93] mr-1">Source tier:</span>
        <button
          :for={{label, tier} <- @tiers}
          type="button"
          phx-click="filter_tier"
          phx-value-tier={tier || "all"}
          class={[
            "px-3 py-1.5 rounded-full text-xs font-medium border transition-colors",
            if(@tier_filter == tier,
              do: "bg-[#007AFF] text-white border-[#007AFF]",
              else: "bg-white text-[#1C1C1E] border-[#E5E5EA] hover:border-[#007AFF]/40"
            )
          ]}
        >
          {label}
        </button>
      </div>

      <div :if={@questions == []} class="bg-white rounded-2xl shadow-md p-12 text-center">
        <div class="text-4xl mb-3">✅</div>
        <p class="text-[#1C1C1E] font-semibold">No questions in this view</p>
        <p class="text-sm text-[#8E8E93] mt-1">
          Try a different status filter above.
        </p>
      </div>

      <div class="space-y-4">
        <.review_card
          :for={q <- @questions}
          question={q}
          editing={@editing_id == q.id}
        />
      </div>
    </div>
    """
  end

  attr :question, Question, required: true
  attr :editing, :boolean, default: false

  defp review_card(assigns) do
    assigns = assign(assigns, :report, assigns.question.validation_report || %{})

    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-6">
      <div class="flex items-start justify-between gap-4 mb-4">
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 flex-wrap mb-2">
            <span class="text-xs font-semibold text-[#8E8E93]">
              {course_label(@question)}
            </span>
            <span
              :if={@question.chapter}
              class="px-2 py-0.5 rounded-full bg-[#E8F8EB] text-[#4CD964] text-xs font-medium"
            >
              {@question.chapter.name}
            </span>
            <span class="px-2 py-0.5 rounded-full bg-gray-100 text-gray-700 text-xs font-medium">
              {@question.question_type}
            </span>
            <span class="px-2 py-0.5 rounded-full bg-gray-100 text-gray-700 text-xs font-medium">
              {@question.difficulty}
            </span>
            <span class={[
              "px-2 py-0.5 rounded-full text-xs font-medium",
              status_badge_class(@question.validation_status)
            ]}>
              {@question.validation_status}
            </span>
            <span
              :if={@question.source_tier}
              class={["px-2 py-0.5 rounded-full text-xs font-medium", tier_badge_class(@question.source_tier)]}
            >
              Tier {@question.source_tier}
            </span>
          </div>
          <div :if={score(@report)} class="flex items-center gap-2">
            <span class="text-xs text-[#8E8E93]">Topic relevance:</span>
            <span class={[
              "text-sm font-bold",
              score_color(score(@report))
            ]}>
              {Float.round(score(@report) * 1.0, 1)}%
            </span>
          </div>
        </div>
      </div>

      <%= if @editing do %>
        <.edit_form question={@question} />
      <% else %>
        <div class="space-y-3">
          <div>
            <p class="text-xs font-semibold text-[#8E8E93] uppercase tracking-wide mb-1">
              Question
            </p>
            <p class="text-[#1C1C1E]">{@question.content}</p>
          </div>

          <div :if={is_map(@question.options) && map_size(@question.options) > 0}>
            <p class="text-xs font-semibold text-[#8E8E93] uppercase tracking-wide mb-1">
              Options
            </p>
            <ul class="text-sm text-[#1C1C1E] space-y-1">
              <li :for={{key, val} <- sorted_options(@question.options)}>
                <span class="font-semibold">{key}.</span> {val}
              </li>
            </ul>
          </div>

          <div>
            <p class="text-xs font-semibold text-[#8E8E93] uppercase tracking-wide mb-1">
              Recorded answer
            </p>
            <p class="text-[#1C1C1E]">{@question.answer}</p>
          </div>

          <div :if={@question.explanation && @question.explanation != ""}>
            <p class="text-xs font-semibold text-[#8E8E93] uppercase tracking-wide mb-1">
              Explanation
            </p>
            <p class="text-sm text-[#1C1C1E]">{@question.explanation}</p>
          </div>
        </div>

        <.validator_findings report={@report} />

        <div class="flex flex-wrap gap-2 mt-5 pt-4 border-t border-[#E5E5EA]">
          <button
            :if={@question.validation_status != :passed}
            type="button"
            phx-click="approve"
            phx-value-id={@question.id}
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Approve
          </button>
          <button
            type="button"
            phx-click="edit"
            phx-value-id={@question.id}
            class="bg-white hover:bg-gray-50 text-gray-700 font-medium px-6 py-2 rounded-full border border-gray-200 shadow-sm transition-colors"
          >
            Edit &amp; Approve
          </button>
          <button
            :if={@question.validation_status != :failed}
            type="button"
            phx-click="reject"
            phx-value-id={@question.id}
            data-confirm="Reject this question? Students will not see it."
            class="bg-[#FF3B30] hover:bg-red-600 text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Reject
          </button>
          <button
            type="button"
            phx-click="delete"
            phx-value-id={@question.id}
            data-confirm="Permanently delete this question? This cannot be undone."
            class="bg-white hover:bg-[#FFE5E3] text-[#FF3B30] font-medium px-6 py-2 rounded-full border border-[#FF3B30]/30 shadow-sm transition-colors"
          >
            Delete
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  attr :report, :map, required: true

  defp validator_findings(assigns) do
    ~H"""
    <div :if={map_size(@report) > 0} class="mt-4 pt-4 border-t border-[#E5E5EA]">
      <p class="text-xs font-semibold text-[#8E8E93] uppercase tracking-wide mb-2">
        Validator findings
      </p>
      <dl class="text-sm space-y-2">
        <div :if={reason = @report["topic_relevance_reason"]}>
          <dt class="text-[#8E8E93] text-xs">Topic relevance</dt>
          <dd class="text-[#1C1C1E]">{reason}</dd>
        </div>
        <div :if={issues = completeness_issues(@report)}>
          <dt class="text-[#8E8E93] text-xs">Completeness</dt>
          <dd class="text-[#1C1C1E]">{issues}</dd>
        </div>
        <div :if={corrected = corrected_answer(@report)}>
          <dt class="text-[#8E8E93] text-xs">Suggested answer</dt>
          <dd class="text-[#1C1C1E]">{corrected}</dd>
        </div>
        <div :if={suggested = suggested_explanation(@report)}>
          <dt class="text-[#8E8E93] text-xs">Suggested explanation</dt>
          <dd class="text-[#1C1C1E]">{suggested}</dd>
        </div>
      </dl>
    </div>
    """
  end

  attr :question, Question, required: true

  defp edit_form(assigns) do
    assigns =
      assigns
      |> assign(
        :suggested_explanation,
        suggested_explanation(assigns.question.validation_report || %{})
      )
      |> assign(:corrected_answer, corrected_answer(assigns.question.validation_report || %{}))

    ~H"""
    <form
      phx-submit="save_edit"
      phx-value-id={@question.id}
      class="space-y-4"
    >
      <div>
        <label class="block text-xs font-semibold text-[#8E8E93] uppercase tracking-wide mb-1">
          Question
        </label>
        <textarea
          name="question[content]"
          rows="3"
          class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-xl outline-none transition-colors text-[#1C1C1E]"
        >{@question.content}</textarea>
      </div>

      <div>
        <label class="block text-xs font-semibold text-[#8E8E93] uppercase tracking-wide mb-1">
          Answer
          <span :if={@corrected_answer} class="text-[#4CD964] normal-case font-normal ml-1">
            (suggested: {@corrected_answer})
          </span>
        </label>
        <input
          type="text"
          name="question[answer]"
          value={@question.answer}
          class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors text-[#1C1C1E]"
        />
      </div>

      <div>
        <label class="block text-xs font-semibold text-[#8E8E93] uppercase tracking-wide mb-1">
          Explanation
          <span :if={@suggested_explanation} class="text-[#4CD964] normal-case font-normal ml-1">
            (suggestion available below)
          </span>
        </label>
        <textarea
          name="question[explanation]"
          rows="3"
          placeholder={@suggested_explanation || "Explanation shown to the student"}
          class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-xl outline-none transition-colors text-[#1C1C1E]"
        >{@question.explanation}</textarea>
      </div>

      <div class="flex gap-2 pt-2">
        <button
          type="submit"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
        >
          Save &amp; Approve
        </button>
        <button
          type="button"
          phx-click="cancel_edit"
          class="bg-white hover:bg-gray-50 text-gray-700 font-medium px-6 py-2 rounded-full border border-gray-200 shadow-sm transition-colors"
        >
          Cancel
        </button>
      </div>
    </form>
    """
  end

  # --- View helpers ---

  defp course_label(%Question{course: %{name: name, grade: grade}}),
    do: "#{name} · Grade #{grade}"

  defp course_label(_), do: ""

  defp tier_badge_class(1), do: "bg-[#E8F0FF] text-[#007AFF]"
  defp tier_badge_class(2), do: "bg-[#E8F8EB] text-[#34C759]"
  defp tier_badge_class(3), do: "bg-[#FFF4CC] text-[#8E6000]"
  defp tier_badge_class(_), do: "bg-[#F5F5F7] text-[#8E8E93]"

  defp status_badge_class(:passed), do: "bg-[#E8F8EB] text-[#4CD964]"
  defp status_badge_class(:failed), do: "bg-[#FFE5E3] text-[#FF3B30]"
  defp status_badge_class(:needs_review), do: "bg-[#FFF4CC] text-[#8E6000]"
  defp status_badge_class(_), do: "bg-[#F5F5F7] text-[#8E8E93]"

  defp score(%{"topic_relevance_score" => s}) when is_number(s), do: s
  defp score(_), do: nil

  defp score_color(score) when is_number(score) and score >= 95, do: "text-[#4CD964]"
  defp score_color(score) when is_number(score) and score >= 70, do: "text-[#FFCC00]"
  defp score_color(_), do: "text-[#FF3B30]"

  defp completeness_issues(%{"completeness" => %{"issues" => issues}})
       when is_list(issues) and issues != [] do
    Enum.join(issues, "; ")
  end

  defp completeness_issues(_), do: nil

  defp corrected_answer(%{"answer_correct" => %{"correct" => false, "corrected_answer" => a}})
       when is_binary(a) and a != "",
       do: a

  defp corrected_answer(_), do: nil

  defp suggested_explanation(%{"explanation" => %{"suggested_explanation" => e}})
       when is_binary(e) and e != "",
       do: e

  defp suggested_explanation(_), do: nil

  defp sorted_options(options) do
    options
    |> Enum.sort_by(fn {k, _} -> k end)
  end
end
