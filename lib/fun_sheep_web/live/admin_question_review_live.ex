defmodule FunSheepWeb.AdminQuestionReviewLive do
  @moduledoc """
  Admin review queue for questions flagged by the validator.

  Lists every question in `validation_status = :needs_review`, shows the
  full validator report (why it was flagged, suggested corrections), and
  lets an admin:

    * Approve — override the flag and make the question visible to students
    * Reject — mark it failed so students never see it
    * Edit & Approve — apply the validator's suggested corrections (or their
      own edits) and approve in one step
  """

  use FunSheepWeb, :live_view

  alias FunSheep.Questions
  alias FunSheep.Questions.Question

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Question Review", editing_id: nil)
     |> load_queue()}
  end

  @impl true
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
    questions = Questions.list_all_questions_needing_review()
    assign(socket, questions: questions, queue_count: length(questions))
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
    ~H"""
    <div class="max-w-5xl mx-auto p-6">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold text-[#1C1C1E]">Question Review Queue</h1>
          <p class="text-sm text-[#8E8E93] mt-1">
            Questions flagged by the validator for manual review.
          </p>
        </div>
        <div class="bg-white rounded-2xl shadow-md px-4 py-2">
          <span class="text-2xl font-bold text-[#4CD964]">{@queue_count}</span>
          <span class="text-sm text-[#8E8E93] ml-1">pending</span>
        </div>
      </div>

      <div :if={@questions == []} class="bg-white rounded-2xl shadow-md p-12 text-center">
        <div class="text-4xl mb-3">✅</div>
        <p class="text-[#1C1C1E] font-semibold">Queue is empty</p>
        <p class="text-sm text-[#8E8E93] mt-1">
          No questions are currently flagged for review.
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
            type="button"
            phx-click="reject"
            phx-value-id={@question.id}
            data-confirm="Reject this question? Students will not see it."
            class="bg-[#FF3B30] hover:bg-red-600 text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Reject
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
