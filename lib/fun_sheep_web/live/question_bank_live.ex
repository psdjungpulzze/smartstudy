defmodule FunSheepWeb.QuestionBankLive do
  use FunSheepWeb, :live_view

  import Ecto.Query, only: [from: 2]

  alias FunSheep.{Courses, Questions}
  alias FunSheep.Questions.Question

  @all_statuses [:passed, :pending, :needs_review, :failed]

  @impl true
  def mount(%{"course_id" => course_id}, _session, socket) do
    course = Courses.get_course_with_chapters!(course_id)
    role = socket.assigns[:current_role] || "student"
    statuses = role_statuses(role)

    question_counts = Questions.list_chapter_section_counts(course_id, statuses: statuses)

    first_chapter = List.first(course.chapters)
    {sel_chapter_id, sel_section_id} = initial_selection(first_chapter)

    {questions, total_count} =
      load_questions(sel_chapter_id, sel_section_id, statuses, %{}, 1)

    expanded_chapter_ids =
      if first_chapter, do: MapSet.new([first_chapter.id]), else: MapSet.new()

    coverage = if role == "admin", do: Questions.coverage_summary(course_id), else: nil

    {:ok,
     socket
     |> assign(
       page_title: "Question Bank — #{course.name}",
       course: course,
       role: role,
       statuses: statuses,
       question_counts: question_counts,
       selected_chapter_id: sel_chapter_id,
       selected_section_id: sel_section_id,
       expanded_chapter_ids: expanded_chapter_ids,
       questions: questions,
       total_count: total_count,
       page: 1,
       filters: %{},
       expanded_question_ids: MapSet.new(),
       coverage: coverage,
       show_form: false,
       question_form: nil
     )
     |> allow_upload(:question_figure,
       accept: ~w(.png .jpg .jpeg .webp),
       max_entries: 3,
       max_file_size: 5_000_000
     )}
  end

  # ── Event Handlers ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_chapter", %{"id" => chapter_id}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded_chapter_ids, chapter_id) do
        MapSet.delete(socket.assigns.expanded_chapter_ids, chapter_id)
      else
        MapSet.put(socket.assigns.expanded_chapter_ids, chapter_id)
      end

    {:noreply, assign(socket, expanded_chapter_ids: expanded)}
  end

  def handle_event("select_chapter", %{"id" => chapter_id}, socket) do
    statuses = socket.assigns.statuses

    {questions, total_count} =
      load_questions(chapter_id, nil, statuses, socket.assigns.filters, 1)

    expanded = MapSet.put(socket.assigns.expanded_chapter_ids, chapter_id)

    {:noreply,
     assign(socket,
       selected_chapter_id: chapter_id,
       selected_section_id: nil,
       questions: questions,
       total_count: total_count,
       page: 1,
       expanded_chapter_ids: expanded,
       expanded_question_ids: MapSet.new()
     )}
  end

  def handle_event("select_section", %{"id" => section_id, "chapter_id" => chapter_id}, socket) do
    statuses = socket.assigns.statuses

    {questions, total_count} =
      load_questions(chapter_id, section_id, statuses, socket.assigns.filters, 1)

    {:noreply,
     assign(socket,
       selected_chapter_id: chapter_id,
       selected_section_id: section_id,
       questions: questions,
       total_count: total_count,
       page: 1,
       expanded_question_ids: MapSet.new()
     )}
  end

  def handle_event("set_filter", params, socket) do
    filters = %{
      "difficulty" => params["difficulty"] || "",
      "question_type" => params["question_type"] || "",
      "validation_status" => params["validation_status"] || ""
    }

    statuses = effective_statuses(socket.assigns.role, filters["validation_status"])

    {questions, total_count} =
      load_questions(
        socket.assigns.selected_chapter_id,
        socket.assigns.selected_section_id,
        statuses,
        filters,
        1
      )

    {:noreply,
     assign(socket,
       filters: filters,
       statuses: statuses,
       questions: questions,
       total_count: total_count,
       page: 1,
       expanded_question_ids: MapSet.new()
     )}
  end

  def handle_event("next_page", _params, socket) do
    max_page = ceil_div(socket.assigns.total_count, Questions.page_size())

    if socket.assigns.page < max_page do
      new_page = socket.assigns.page + 1

      {questions, _total} =
        load_questions(
          socket.assigns.selected_chapter_id,
          socket.assigns.selected_section_id,
          socket.assigns.statuses,
          socket.assigns.filters,
          new_page
        )

      {:noreply,
       assign(socket, page: new_page, questions: questions, expanded_question_ids: MapSet.new())}
    else
      {:noreply, socket}
    end
  end

  def handle_event("prev_page", _params, socket) do
    if socket.assigns.page > 1 do
      new_page = socket.assigns.page - 1

      {questions, _total} =
        load_questions(
          socket.assigns.selected_chapter_id,
          socket.assigns.selected_section_id,
          socket.assigns.statuses,
          socket.assigns.filters,
          new_page
        )

      {:noreply,
       assign(socket, page: new_page, questions: questions, expanded_question_ids: MapSet.new())}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_question", %{"id" => question_id}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded_question_ids, question_id) do
        MapSet.delete(socket.assigns.expanded_question_ids, question_id)
      else
        MapSet.put(socket.assigns.expanded_question_ids, question_id)
      end

    {:noreply, assign(socket, expanded_question_ids: expanded)}
  end

  def handle_event("delete_question", %{"id" => question_id}, socket) do
    question = Questions.get_question!(question_id)

    case Questions.delete_question(question) do
      {:ok, _} ->
        {questions, total_count} =
          load_questions(
            socket.assigns.selected_chapter_id,
            socket.assigns.selected_section_id,
            socket.assigns.statuses,
            socket.assigns.filters,
            socket.assigns.page
          )

        question_counts =
          Questions.list_chapter_section_counts(socket.assigns.course.id,
            statuses: role_statuses(socket.assigns.role)
          )

        coverage =
          if socket.assigns.role == "admin",
            do: Questions.coverage_summary(socket.assigns.course.id),
            else: nil

        {:noreply,
         socket
         |> assign(
           questions: questions,
           total_count: total_count,
           question_counts: question_counts,
           coverage: coverage
         )
         |> put_flash(:info, "Question deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete question")}
    end
  end

  def handle_event("approve_question", %{"id" => id}, socket) do
    if socket.assigns.role == "admin" do
      reviewer_id = get_in(socket.assigns, [:current_user, "user_role_id"])
      question = Questions.get_question!(id)

      case Questions.admin_approve_question(question, reviewer_id) do
        {:ok, _} ->
          socket = reload_questions_and_counts(socket)
          {:noreply, put_flash(socket, :info, "Question approved")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not approve question")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("reject_question", %{"id" => id}, socket) do
    if socket.assigns.role == "admin" do
      reviewer_id = get_in(socket.assigns, [:current_user, "user_role_id"])
      question = Questions.get_question!(id)

      case Questions.admin_reject_question(question, reviewer_id) do
        {:ok, _} ->
          socket = reload_questions_and_counts(socket)
          {:noreply, put_flash(socket, :info, "Question rejected")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not reject question")}
      end
    else
      {:noreply, socket}
    end
  end

  # ── Add Question Form ────────────────────────────────────────────────────────

  def handle_event("show_add_question", _params, socket) do
    changeset = Questions.change_question(%Question{})

    {:noreply, assign(socket, show_form: true, question_form: to_form(changeset))}
  end

  def handle_event("cancel_form", _params, socket) do
    {:noreply, assign(socket, show_form: false, question_form: nil)}
  end

  def handle_event("validate_question", %{"question" => params}, socket) do
    changeset =
      %Question{}
      |> Questions.change_question(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, question_form: to_form(changeset))}
  end

  def handle_event("save_question", %{"question" => params}, socket) do
    course = socket.assigns.course
    attrs = Map.put(params, "course_id", course.id)

    case Questions.create_question(attrs) do
      {:ok, question} ->
        attach_uploaded_figures(socket, question)
        socket = reload_questions_and_counts(socket)

        {:noreply,
         socket
         |> assign(show_form: false, question_form: nil)
         |> put_flash(:info, "Question added")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, question_form: to_form(changeset))}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :question_figure, ref)}
  end

  # ── Render ───────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto">
      <%!-- Breadcrumb --%>
      <div class="mb-4">
        <.link
          navigate={~p"/courses/#{@course.id}"}
          class="text-[#8E8E93] hover:text-[#1C1C1E] text-sm inline-flex items-center transition-colors"
        >
          <.icon name="hero-arrow-left" class="w-4 h-4 mr-1" /> Back to {@course.name}
        </.link>
      </div>

      <%!-- Header --%>
      <div class="flex items-center justify-between mb-4">
        <div>
          <h1 class="text-2xl font-bold text-[#1C1C1E]">Question Bank</h1>
          <p class="text-[#8E8E93] mt-0.5 text-sm">{@course.name}</p>
        </div>
        <button
          :if={@role in ["admin", "teacher"]}
          phx-click="show_add_question"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-5 py-2 rounded-full shadow-md transition-colors text-sm"
        >
          <.icon name="hero-plus" class="w-4 h-4 inline mr-1" /> Add Question
        </button>
      </div>

      <%!-- Admin coverage bar --%>
      <.coverage_bar :if={@role == "admin" and @coverage} coverage={@coverage} />

      <%!-- Add Question form --%>
      <.add_question_form
        :if={@show_form}
        form={@question_form}
        course={@course}
        uploads={@uploads}
      />

      <%!-- 2-column layout: sidebar + content --%>
      <div class="flex gap-5">
        <%!-- Left sidebar: chapter/section tree --%>
        <aside class="w-60 shrink-0">
          <div class="bg-white rounded-2xl shadow-md overflow-hidden">
            <div class="px-4 py-3 border-b border-[#F2F2F7]">
              <p class="text-xs font-semibold text-[#8E8E93] uppercase tracking-wide">Chapters</p>
            </div>
            <nav class="py-1">
              <div :if={map_size(@question_counts) == 0} class="px-4 py-3 text-sm text-[#8E8E93]">
                No questions yet
              </div>
              <.chapter_tree
                :for={chapter <- @course.chapters}
                chapter={chapter}
                question_counts={@question_counts}
                selected_chapter_id={@selected_chapter_id}
                selected_section_id={@selected_section_id}
                expanded_chapter_ids={@expanded_chapter_ids}
              />
            </nav>
          </div>
        </aside>

        <%!-- Right panel: filters + question list --%>
        <div class="flex-1 min-w-0">
          <%!-- Filters --%>
          <.question_filters filters={@filters} role={@role} />

          <%!-- Selection heading --%>
          <div class="mb-3 flex items-center justify-between">
            <h2 class="text-sm font-semibold text-[#1C1C1E]">
              {selection_label(@course, @selected_chapter_id, @selected_section_id)}
            </h2>
            <span class="text-xs text-[#8E8E93]">{@total_count} question(s)</span>
          </div>

          <%!-- Empty state --%>
          <div :if={@questions == []} class="bg-white rounded-2xl shadow-md p-8 text-center">
            <.icon name="hero-question-mark-circle" class="w-10 h-10 text-[#8E8E93] mx-auto mb-3" />
            <p class="text-[#1C1C1E] font-medium">No questions here</p>
            <p class="text-sm text-[#8E8E93] mt-1">
              Select a chapter or section from the sidebar.
            </p>
          </div>

          <%!-- Question cards --%>
          <div class="space-y-2">
            <.question_card
              :for={q <- @questions}
              question={q}
              role={@role}
              expanded={MapSet.member?(@expanded_question_ids, q.id)}
            />
          </div>

          <%!-- Pagination --%>
          <.pagination
            :if={@total_count > 0}
            page={@page}
            total_count={@total_count}
            page_size={Questions.page_size()}
          />
        </div>
      </div>
    </div>
    """
  end

  # ── Components ───────────────────────────────────────────────────────────────

  defp coverage_bar(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-4 mb-5">
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-semibold text-[#1C1C1E]">Coverage</h3>
        <span class="text-xs text-[#8E8E93]">
          {@coverage.sections_with_questions}/{@coverage.total_sections} sections have questions
        </span>
      </div>
      <div class="w-full bg-[#F2F2F7] rounded-full h-2 mb-3">
        <div
          class="bg-[#4CD964] h-2 rounded-full transition-all"
          style={"width: #{min(@coverage.coverage_pct, 100)}%"}
        >
        </div>
      </div>
      <div class="flex flex-wrap gap-3 text-xs">
        <span class="text-green-700 bg-green-50 px-2 py-0.5 rounded-full">
          Easy: {@coverage.by_difficulty.easy}
        </span>
        <span class="text-yellow-700 bg-yellow-50 px-2 py-0.5 rounded-full">
          Med: {@coverage.by_difficulty.medium}
        </span>
        <span class="text-red-700 bg-red-50 px-2 py-0.5 rounded-full">
          Hard: {@coverage.by_difficulty.hard}
        </span>
        <span
          :if={@coverage.needs_review > 0}
          class="text-orange-700 bg-orange-50 px-2 py-0.5 rounded-full"
        >
          Review: {@coverage.needs_review}
        </span>
        <span :if={@coverage.failed > 0} class="text-red-700 bg-red-50 px-2 py-0.5 rounded-full">
          Failed: {@coverage.failed}
        </span>
        <span :if={@coverage.pending > 0} class="text-gray-600 bg-gray-100 px-2 py-0.5 rounded-full">
          Pending: {@coverage.pending}
        </span>
      </div>
    </div>
    """
  end

  defp chapter_tree(assigns) do
    ch_id = assigns.chapter.id
    count_data = Map.get(assigns.question_counts, ch_id, %{total: 0, sections: %{}})
    expanded = MapSet.member?(assigns.expanded_chapter_ids, ch_id)
    selected = assigns.selected_chapter_id == ch_id and is_nil(assigns.selected_section_id)

    assigns =
      assigns
      |> assign(count_data: count_data, expanded: expanded, selected: selected, ch_id: ch_id)

    ~H"""
    <div>
      <div class="flex items-center">
        <button
          phx-click="toggle_chapter"
          phx-value-id={@ch_id}
          class="p-1 text-[#8E8E93] hover:text-[#1C1C1E] shrink-0"
          aria-label={if @expanded, do: "Collapse", else: "Expand"}
        >
          <.icon
            name={if @expanded, do: "hero-chevron-down", else: "hero-chevron-right"}
            class="w-3.5 h-3.5"
          />
        </button>
        <button
          phx-click="select_chapter"
          phx-value-id={@ch_id}
          class={[
            "flex-1 flex items-center justify-between px-2 py-1.5 text-left text-sm rounded-lg transition-colors",
            if(@selected,
              do: "bg-[#4CD964]/10 text-[#1C1C1E] font-medium",
              else: "hover:bg-[#F2F2F7] text-[#3C3C43]"
            )
          ]}
        >
          <span class="truncate">{@chapter.name}</span>
          <span class="ml-1 text-xs text-[#8E8E93] shrink-0">{@count_data.total}</span>
        </button>
      </div>

      <div :if={@expanded} class="ml-5">
        <.section_row
          :for={section <- @chapter.sections}
          section={section}
          chapter_id={@ch_id}
          count={Map.get(@count_data.sections, section.id, 0)}
          selected={@selected_section_id == section.id}
        />
        <.section_row
          :if={Map.get(@count_data.sections, :none, 0) > 0}
          section={%{id: :unclassified, name: "Unclassified"}}
          chapter_id={@ch_id}
          count={Map.get(@count_data.sections, :none, 0)}
          selected={false}
        />
      </div>
    </div>
    """
  end

  defp section_row(assigns) do
    ~H"""
    <button
      phx-click="select_section"
      phx-value-id={@section.id}
      phx-value-chapter_id={@chapter_id}
      class={[
        "w-full flex items-center justify-between px-2 py-1 text-left text-xs rounded-lg transition-colors",
        if(@selected,
          do: "bg-[#4CD964]/10 text-[#1C1C1E] font-medium",
          else: "hover:bg-[#F2F2F7] text-[#8E8E93]"
        )
      ]}
    >
      <span class="truncate">{@section.name}</span>
      <span class="ml-1 shrink-0">{@count}</span>
    </button>
    """
  end

  defp question_filters(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-3 mb-4">
      <form phx-change="set_filter" class="flex flex-wrap gap-2">
        <select
          name="difficulty"
          class="px-3 py-1.5 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors text-xs"
        >
          <option value="">All Difficulties</option>
          <option value="easy" selected={@filters["difficulty"] == "easy"}>Easy</option>
          <option value="medium" selected={@filters["difficulty"] == "medium"}>Medium</option>
          <option value="hard" selected={@filters["difficulty"] == "hard"}>Hard</option>
        </select>
        <select
          name="question_type"
          class="px-3 py-1.5 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors text-xs"
        >
          <option value="">All Types</option>
          <option value="multiple_choice" selected={@filters["question_type"] == "multiple_choice"}>
            Multiple Choice
          </option>
          <option value="short_answer" selected={@filters["question_type"] == "short_answer"}>
            Short Answer
          </option>
          <option value="free_response" selected={@filters["question_type"] == "free_response"}>
            Free Response
          </option>
          <option value="true_false" selected={@filters["question_type"] == "true_false"}>
            True/False
          </option>
          <option value="essay" selected={@filters["question_type"] == "essay"}>Essay</option>
        </select>
        <select
          :if={@role == "admin"}
          name="validation_status"
          class="px-3 py-1.5 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors text-xs"
        >
          <option value="">All Statuses</option>
          <option value="passed" selected={@filters["validation_status"] == "passed"}>
            Passed
          </option>
          <option value="needs_review" selected={@filters["validation_status"] == "needs_review"}>
            Needs Review
          </option>
          <option value="pending" selected={@filters["validation_status"] == "pending"}>
            Pending
          </option>
          <option value="failed" selected={@filters["validation_status"] == "failed"}>
            Failed
          </option>
        </select>
      </form>
    </div>
    """
  end

  defp question_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-4">
      <div class="flex items-start gap-3">
        <div class="flex-1 min-w-0">
          <p class="text-[#1C1C1E] text-sm font-medium leading-snug">
            {truncate(@question.content, 160)}
          </p>
          <div class="flex flex-wrap gap-1.5 mt-2">
            <span class={"px-2 py-0.5 rounded-full text-xs font-medium #{type_color(@question.question_type)}"}>
              {type_label(@question.question_type)}
            </span>
            <span
              :if={@question.difficulty}
              class={"px-2 py-0.5 rounded-full text-xs font-medium #{difficulty_color(@question.difficulty)}"}
            >
              {String.capitalize(to_string(@question.difficulty))}
            </span>
            <span
              :if={@question.section}
              class="px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-600"
            >
              {@question.section.name}
            </span>
            <span
              :if={@role == "admin"}
              class={"px-2 py-0.5 rounded-full text-xs font-medium #{status_color(@question.validation_status)}"}
            >
              {String.capitalize(to_string(@question.validation_status))}
            </span>
            <span
              :if={@role == "admin" and @question.source_type}
              class="px-2 py-0.5 rounded-full text-xs font-medium bg-purple-50 text-purple-700"
            >
              {source_label(@question.source_type)}
            </span>
          </div>
        </div>
        <div class="flex items-center gap-1 shrink-0">
          <button
            phx-click="toggle_question"
            phx-value-id={@question.id}
            class="p-1 text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
            aria-label={if @expanded, do: "Collapse", else: "Expand"}
          >
            <.icon
              name={if @expanded, do: "hero-chevron-up", else: "hero-chevron-down"}
              class="w-4 h-4"
            />
          </button>
          <button
            :if={@role == "admin" and @question.validation_status == :needs_review}
            phx-click="approve_question"
            phx-value-id={@question.id}
            class="p-1 text-green-600 hover:text-green-700 transition-colors"
            title="Approve"
          >
            <.icon name="hero-check" class="w-4 h-4" />
          </button>
          <button
            :if={@role == "admin" and @question.validation_status == :needs_review}
            phx-click="reject_question"
            phx-value-id={@question.id}
            class="p-1 text-[#FF3B30] hover:text-red-700 transition-colors"
            title="Reject"
          >
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
          <button
            :if={@role in ["admin", "teacher"]}
            phx-click="delete_question"
            phx-value-id={@question.id}
            data-confirm="Delete this question?"
            class="p-1 text-[#8E8E93] hover:text-[#FF3B30] transition-colors"
            aria-label="Delete"
          >
            <.icon name="hero-trash" class="w-4 h-4" />
          </button>
        </div>
      </div>

      <%!-- Expanded detail --%>
      <div :if={@expanded} class="mt-3 pt-3 border-t border-[#F2F2F7] space-y-2 text-sm">
        <div>
          <span class="text-xs font-semibold text-[#8E8E93] uppercase">Question</span>
          <p class="mt-0.5 text-[#1C1C1E]">{@question.content}</p>
        </div>
        <div :if={@question.question_type == :multiple_choice and @question.options not in [nil, %{}]}>
          <span class="text-xs font-semibold text-[#8E8E93] uppercase">Options</span>
          <div class="mt-0.5 space-y-0.5">
            <div :for={{key, text} <- Enum.sort(@question.options)} class="flex gap-2">
              <span class="font-medium text-[#8E8E93] w-5">{key}.</span>
              <span class={
                if to_string(@question.answer) == to_string(text),
                  do: "text-green-700 font-medium",
                  else: "text-[#3C3C43]"
              }>
                {text}
              </span>
            </div>
          </div>
        </div>
        <div>
          <span class="text-xs font-semibold text-[#8E8E93] uppercase">Answer</span>
          <p class="mt-0.5 text-green-700 font-medium">{@question.answer}</p>
        </div>
        <div :if={@question.explanation not in [nil, ""]}>
          <span class="text-xs font-semibold text-[#8E8E93] uppercase">Explanation</span>
          <p class="mt-0.5 text-[#3C3C43]">{@question.explanation}</p>
        </div>
        <div :if={@role == "admin" and @question.validation_report not in [nil, %{}]}>
          <span class="text-xs font-semibold text-[#8E8E93] uppercase">Validation Report</span>
          <pre class="mt-0.5 text-xs text-[#8E8E93] bg-[#F5F5F7] rounded-lg p-2 overflow-x-auto whitespace-pre-wrap">{Jason.encode!(@question.validation_report, pretty: true)}</pre>
        </div>
      </div>
    </div>
    """
  end

  defp pagination(assigns) do
    total_pages = ceil_div(assigns.total_count, assigns.page_size)
    assigns = assign(assigns, total_pages: total_pages)

    ~H"""
    <div class="flex items-center justify-between mt-4 text-sm">
      <button
        phx-click="prev_page"
        disabled={@page <= 1}
        class="px-4 py-1.5 rounded-full border border-[#E5E5EA] text-[#3C3C43] disabled:opacity-40 hover:bg-[#F5F5F7] transition-colors"
      >
        Previous
      </button>
      <span class="text-[#8E8E93]">Page {@page} of {@total_pages}</span>
      <button
        phx-click="next_page"
        disabled={@page >= @total_pages}
        class="px-4 py-1.5 rounded-full border border-[#E5E5EA] text-[#3C3C43] disabled:opacity-40 hover:bg-[#F5F5F7] transition-colors"
      >
        Next
      </button>
    </div>
    """
  end

  defp add_question_form(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-6 mb-5">
      <h3 class="text-lg font-semibold text-[#1C1C1E] mb-4">Add Question</h3>
      <.form
        for={@form}
        phx-change="validate_question"
        phx-submit="save_question"
        class="space-y-4"
      >
        <.input field={@form[:content]} type="textarea" label="Question Content" required />
        <.input field={@form[:answer]} type="text" label="Answer" required />

        <div>
          <label class="block text-sm font-medium text-[#1C1C1E] mb-2">
            Figures (optional) — up to 3 images
          </label>
          <div
            phx-drop-target={@uploads.question_figure.ref}
            class="border-2 border-dashed border-[#E5E5EA] rounded-2xl p-4 text-center"
          >
            <.live_file_input upload={@uploads.question_figure} class="text-sm" />
            <p class="text-xs text-[#8E8E93] mt-2">PNG, JPG, WebP up to 5MB each.</p>
          </div>
          <div :for={entry <- @uploads.question_figure.entries} class="mt-2 flex items-center gap-3">
            <.live_img_preview entry={entry} class="w-16 h-16 object-cover rounded-lg" />
            <div class="flex-1 text-sm">
              <p class="text-[#1C1C1E]">{entry.client_name}</p>
              <p class="text-xs text-[#8E8E93]">{entry.progress}%</p>
            </div>
            <button
              type="button"
              phx-click="cancel_upload"
              phx-value-ref={entry.ref}
              class="text-sm text-[#FF3B30]"
            >
              Remove
            </button>
          </div>
          <p
            :for={err <- upload_errors(@uploads.question_figure)}
            class="text-sm text-[#FF3B30] mt-1"
          >
            {upload_error_message(err)}
          </p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.input
            field={@form[:question_type]}
            type="select"
            label="Question Type"
            prompt="Select type..."
            options={[
              {"Multiple Choice", :multiple_choice},
              {"Short Answer", :short_answer},
              {"Free Response", :free_response},
              {"True/False", :true_false},
              {"Essay", :essay}
            ]}
            required
          />
          <.input
            field={@form[:difficulty]}
            type="select"
            label="Difficulty"
            prompt="Select difficulty..."
            options={[{"Easy", :easy}, {"Medium", :medium}, {"Hard", :hard}]}
          />
        </div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.input
            field={@form[:chapter_id]}
            type="select"
            label="Chapter (optional)"
            prompt="Select chapter..."
            options={Enum.map(@course.chapters, &{&1.name, &1.id})}
          />
          <.input
            field={@form[:section_id]}
            type="select"
            label="Section (optional)"
            prompt="Select section..."
            options={
              @course.chapters
              |> Enum.flat_map(fn ch ->
                Enum.map(ch.sections, &{"#{ch.name} > #{&1.name}", &1.id})
              end)
            }
          />
        </div>
        <div class="flex gap-3 pt-2">
          <button
            type="submit"
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Save Question
          </button>
          <button
            type="button"
            phx-click="cancel_form"
            class="bg-white hover:bg-gray-50 text-gray-700 font-medium px-6 py-2 rounded-full border border-gray-200 shadow-sm transition-colors"
          >
            Cancel
          </button>
        </div>
      </.form>
    </div>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp role_statuses("admin"), do: @all_statuses
  defp role_statuses(_), do: [:passed]

  defp effective_statuses("admin", ""), do: @all_statuses
  defp effective_statuses("admin", nil), do: @all_statuses
  defp effective_statuses("admin", status), do: [String.to_existing_atom(status)]
  defp effective_statuses(_, _), do: [:passed]

  defp initial_selection(nil), do: {nil, nil}
  defp initial_selection(chapter), do: {chapter.id, nil}

  defp load_questions(nil, _section_id, _statuses, _filters, _page), do: {[], 0}

  defp load_questions(chapter_id, nil, statuses, filters, page) do
    Questions.list_questions_for_chapter(chapter_id,
      statuses: statuses,
      filters: filters,
      page: page
    )
  end

  defp load_questions(_chapter_id, section_id, statuses, filters, page) do
    Questions.list_questions_for_section(section_id,
      statuses: statuses,
      filters: filters,
      page: page
    )
  end

  defp reload_questions_and_counts(socket) do
    %{
      course: course,
      selected_chapter_id: ch_id,
      selected_section_id: sec_id,
      statuses: statuses,
      filters: filters,
      page: page,
      role: role
    } = socket.assigns

    {questions, total_count} = load_questions(ch_id, sec_id, statuses, filters, page)

    question_counts =
      Questions.list_chapter_section_counts(course.id,
        statuses: role_statuses(role)
      )

    coverage = if role == "admin", do: Questions.coverage_summary(course.id), else: nil

    assign(socket,
      questions: questions,
      total_count: total_count,
      question_counts: question_counts,
      coverage: coverage
    )
  end

  defp selection_label(_course, nil, _), do: "All Questions"

  defp selection_label(course, chapter_id, nil) do
    case Enum.find(course.chapters, &(&1.id == chapter_id)) do
      nil -> "Chapter"
      ch -> ch.name
    end
  end

  defp selection_label(course, chapter_id, section_id) do
    chapter = Enum.find(course.chapters, &(&1.id == chapter_id))

    section =
      if chapter do
        Enum.find(chapter.sections, &(&1.id == section_id))
      end

    cond do
      section -> section.name
      chapter -> chapter.name
      true -> "Questions"
    end
  end

  defp ceil_div(_n, 0), do: 1
  defp ceil_div(n, d), do: div(n + d - 1, d)

  defp type_label(:multiple_choice), do: "MC"
  defp type_label(:short_answer), do: "Short Answer"
  defp type_label(:free_response), do: "Free Response"
  defp type_label(:true_false), do: "T/F"
  defp type_label(:essay), do: "Essay"
  defp type_label(_), do: "?"

  defp type_color(:multiple_choice), do: "bg-blue-50 text-blue-600"
  defp type_color(:true_false), do: "bg-purple-50 text-purple-600"
  defp type_color(:short_answer), do: "bg-orange-50 text-orange-600"
  defp type_color(:free_response), do: "bg-teal-50 text-teal-600"
  defp type_color(:essay), do: "bg-indigo-50 text-indigo-600"
  defp type_color(_), do: "bg-gray-100 text-gray-600"

  defp difficulty_color(:easy), do: "bg-green-50 text-green-700"
  defp difficulty_color(:medium), do: "bg-yellow-50 text-yellow-700"
  defp difficulty_color(:hard), do: "bg-red-50 text-red-700"
  defp difficulty_color(_), do: "bg-gray-100 text-gray-600"

  defp status_color(:passed), do: "bg-green-50 text-green-700"
  defp status_color(:needs_review), do: "bg-orange-50 text-orange-700"
  defp status_color(:pending), do: "bg-gray-100 text-gray-600"
  defp status_color(:failed), do: "bg-red-50 text-red-700"
  defp status_color(_), do: "bg-gray-100 text-gray-600"

  defp source_label(:ai_generated), do: "AI"
  defp source_label(:web_scraped), do: "Web"
  defp source_label(:user_uploaded), do: "Uploaded"
  defp source_label(:curated), do: "Curated"
  defp source_label(_), do: "Unknown"

  defp upload_error_message(:too_large), do: "File too large — max 5MB"
  defp upload_error_message(:too_many_files), do: "Too many files — max 3"
  defp upload_error_message(:not_accepted), do: "File type not supported"
  defp upload_error_message(err), do: "Upload error: #{inspect(err)}"

  defp truncate(nil, _), do: ""

  defp truncate(text, max) when is_binary(text) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end

  # ── Figure upload helpers (unchanged from original) ──────────────────────────

  defp attach_uploaded_figures(socket, question) do
    figure_ids =
      consume_uploaded_entries(socket, :question_figure, fn %{path: path}, entry ->
        with {:ok, binary} <- File.read(path),
             key <-
               Path.join([
                 "user-figures",
                 question.course_id,
                 "#{question.id}-#{entry.uuid}#{Path.extname(entry.client_name)}"
               ]),
             {:ok, stored_key} <-
               FunSheep.Storage.put(key, binary, content_type: entry.client_type) do
          figure_id = create_user_figure(socket, question, stored_key, entry.client_name)
          {:ok, figure_id}
        else
          _ -> {:postpone, :error}
        end
      end)
      |> Enum.reject(&(&1 in [nil, :error]))

    if figure_ids != [], do: Questions.attach_figures(question, figure_ids)
  end

  defp create_user_figure(socket, question, stored_key, client_name) do
    alias FunSheep.Content

    case find_or_create_user_figure_page(socket, question) do
      {:ok, page} ->
        {:ok, figure} =
          Content.create_source_figure(%{
            ocr_page_id: page.id,
            material_id: page.material_id,
            page_number: 0,
            figure_type: :image,
            caption: client_name,
            image_path: stored_key
          })

        figure.id

      _ ->
        nil
    end
  end

  defp find_or_create_user_figure_page(socket, question) do
    alias FunSheep.Content

    material = ensure_user_uploads_material(socket, question.course_id)

    existing =
      FunSheep.Repo.get_by(Content.OcrPage, material_id: material.id, page_number: 0)

    case existing do
      %Content.OcrPage{} = page ->
        {:ok, page}

      nil ->
        Content.create_ocr_page(%{
          material_id: material.id,
          page_number: 0,
          status: :completed,
          extracted_text: "User-uploaded figures"
        })
    end
  end

  defp ensure_user_uploads_material(socket, course_id) do
    alias FunSheep.Content.UploadedMaterial

    existing =
      FunSheep.Repo.one(
        from(m in UploadedMaterial,
          where: m.course_id == ^course_id and m.file_name == "__user_figures__"
        )
      )

    case existing do
      %UploadedMaterial{} = m ->
        m

      nil ->
        user_role_id = uploader_role_id(socket, course_id)

        {:ok, m} =
          %UploadedMaterial{}
          |> UploadedMaterial.changeset(%{
            file_path: "virtual/user_figures/#{course_id}",
            file_name: "__user_figures__",
            file_type: "virtual/user-figures",
            file_size: 0,
            user_role_id: user_role_id,
            course_id: course_id,
            ocr_status: :completed
          })
          |> FunSheep.Repo.insert()

        m
    end
  end

  defp uploader_role_id(socket, course_id) do
    case get_in(socket.assigns, [:current_user, "user_role_id"]) do
      id when is_binary(id) ->
        id

      _ ->
        from(m in FunSheep.Content.UploadedMaterial,
          where: m.course_id == ^course_id and not is_nil(m.user_role_id),
          select: m.user_role_id,
          limit: 1
        )
        |> FunSheep.Repo.one()
    end
  end
end
