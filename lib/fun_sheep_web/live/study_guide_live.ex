defmodule FunSheepWeb.StudyGuideLive do
  use FunSheepWeb, :live_view

  alias FunSheep.Learning
  alias FunSheep.Learning.StudyGuideAI

  @impl true
  def mount(%{"course_id" => course_id, "id" => id}, _session, socket) do
    guide = Learning.get_study_guide!(id)
    content = guide.content || %{}
    sections = Map.get(content, "sections", [])
    study_plan = Map.get(content, "study_plan", [])
    progress = Map.get(content, "progress", %{})

    {:ok,
     assign(socket,
       page_title: Map.get(content, "title", "Study Guide"),
       course_id: course_id,
       guide: guide,
       content: content,
       sections: sections,
       study_plan: study_plan,
       progress: progress,
       active_tab: "overview",
       expanded_sections: MapSet.new(),
       expanded_explanations: MapSet.new(),
       explanations: %{},
       loading_explanations: MapSet.new(),
       loading_summary: nil,
       chapter_summaries: %{}
     )}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab)}
  end

  def handle_event("toggle_section", %{"chapter-id" => chapter_id}, socket) do
    expanded = socket.assigns.expanded_sections

    expanded =
      if MapSet.member?(expanded, chapter_id),
        do: MapSet.delete(expanded, chapter_id),
        else: MapSet.put(expanded, chapter_id)

    {:noreply, assign(socket, expanded_sections: expanded)}
  end

  def handle_event("toggle_reviewed", %{"chapter-id" => chapter_id}, socket) do
    case Learning.toggle_section_reviewed(socket.assigns.guide, chapter_id) do
      {:ok, updated_guide} ->
        content = updated_guide.content

        {:noreply,
         assign(socket,
           guide: updated_guide,
           content: content,
           sections: Map.get(content, "sections", []),
           progress: Map.get(content, "progress", %{})
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update progress.")}
    end
  end

  def handle_event("toggle_plan_day", %{"day" => day_str}, socket) do
    day = String.to_integer(day_str)

    case Learning.toggle_plan_day_completed(socket.assigns.guide, day) do
      {:ok, updated_guide} ->
        content = updated_guide.content

        {:noreply,
         assign(socket,
           guide: updated_guide,
           content: content,
           study_plan: Map.get(content, "study_plan", []),
           progress: Map.get(content, "progress", %{})
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update progress.")}
    end
  end

  def handle_event("explain_question", %{"question-id" => question_id}, socket) do
    # Toggle off if already showing
    if Map.has_key?(socket.assigns.explanations, question_id) do
      if MapSet.member?(socket.assigns.expanded_explanations, question_id) do
        {:noreply,
         assign(socket, expanded_explanations: MapSet.delete(socket.assigns.expanded_explanations, question_id))}
      else
        {:noreply, assign(socket, expanded_explanations: MapSet.put(socket.assigns.expanded_explanations, question_id))}
      end
    else
      # Start loading
      loading = MapSet.put(socket.assigns.loading_explanations, question_id)
      socket = assign(socket, loading_explanations: loading)

      # Find the question data
      question = find_question(socket.assigns.sections, question_id)
      section = find_section_for_question(socket.assigns.sections, question_id)
      subject = socket.assigns.content["generated_for"]

      # Async task for AI generation
      task_ref =
        Task.async(fn ->
          StudyGuideAI.explain_question(
            question["content"],
            question["answer"],
            subject: subject,
            chapter: section["chapter_name"]
          )
        end)

      socket = assign(socket, explain_task: {task_ref, question_id})
      {:noreply, socket}
    end
  end

  def handle_event("load_chapter_summary", %{"chapter-id" => chapter_id}, socket) do
    if Map.has_key?(socket.assigns.chapter_summaries, chapter_id) do
      {:noreply, socket}
    else
      socket = assign(socket, loading_summary: chapter_id)
      section = Enum.find(socket.assigns.sections, &(&1["chapter_id"] == chapter_id))
      subject = socket.assigns.content["generated_for"]

      task_ref =
        Task.async(fn ->
          StudyGuideAI.chapter_summary(
            section["chapter_name"],
            section["wrong_questions"] || [],
            subject: subject
          )
        end)

      socket = assign(socket, summary_task: {task_ref, chapter_id})
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({ref, {:ok, text}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    cond do
      match?({%Task{ref: ^ref}, _}, socket.assigns[:explain_task]) ->
        {_, question_id} = socket.assigns.explain_task
        explanations = Map.put(socket.assigns.explanations, question_id, text)
        loading = MapSet.delete(socket.assigns.loading_explanations, question_id)
        expanded = MapSet.put(socket.assigns.expanded_explanations, question_id)

        {:noreply,
         assign(socket,
           explanations: explanations,
           loading_explanations: loading,
           expanded_explanations: expanded,
           explain_task: nil
         )}

      match?({%Task{ref: ^ref}, _}, socket.assigns[:summary_task]) ->
        {_, chapter_id} = socket.assigns.summary_task
        summaries = Map.put(socket.assigns.chapter_summaries, chapter_id, text)

        {:noreply,
         assign(socket,
           chapter_summaries: summaries,
           loading_summary: nil,
           summary_task: nil
         )}

      true ->
        {:noreply, socket}
    end
  end

  def handle_info({ref, {:error, _reason}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    socket =
      socket
      |> assign(loading_explanations: MapSet.new(), loading_summary: nil)
      |> put_flash(:error, "Failed to generate AI content. Please try again.")

    {:noreply, socket}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, socket}
  end

  # --- Helpers ---

  defp find_question(sections, question_id) do
    sections
    |> Enum.flat_map(& &1["wrong_questions"])
    |> Enum.find(&(&1["id"] == question_id))
  end

  defp find_section_for_question(sections, question_id) do
    Enum.find(sections, fn s ->
      Enum.any?(s["wrong_questions"] || [], &(&1["id"] == question_id))
    end)
  end

  defp priority_badge_class("Critical"), do: "bg-[#FF3B30] text-white"
  defp priority_badge_class("High"), do: "bg-[#FFCC00] text-[#1C1C1E]"
  defp priority_badge_class("Medium"), do: "bg-[#007AFF] text-white"
  defp priority_badge_class("Low"), do: "bg-[#4CD964] text-white"
  defp priority_badge_class(_), do: "bg-[#8E8E93] text-white"

  defp score_color(score) when score >= 70, do: "bg-[#4CD964]"
  defp score_color(score) when score >= 40, do: "bg-[#FFCC00]"
  defp score_color(_), do: "bg-[#FF3B30]"

  defp tab_class(active_tab, tab) do
    if active_tab == tab do
      "border-b-2 border-[#4CD964] text-[#1C1C1E] font-semibold pb-2 px-4"
    else
      "text-[#8E8E93] hover:text-[#1C1C1E] pb-2 px-4 transition-colors"
    end
  end

  defp days_label(0), do: "Today!"
  defp days_label(1), do: "Tomorrow"
  defp days_label(n) when n < 0, do: "#{abs(n)} days ago"
  defp days_label(n), do: "#{n} days"

  defp progress_percent(progress) do
    total = Map.get(progress, "total_sections", 0)
    reviewed = Map.get(progress, "sections_reviewed", 0)
    if total > 0, do: round(reviewed / total * 100), else: 0
  end

  defp chapter_name_for_id(sections, chapter_id) do
    case Enum.find(sections, &(&1["chapter_id"] == chapter_id)) do
      nil -> "Unknown"
      section -> section["chapter_name"]
    end
  end

  defp is_today_or_past?(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> Date.compare(date, Date.utc_today()) != :gt
      _ -> false
    end
  end

  defp difficulty_badge("easy"), do: {"Easy", "bg-[#E8F8EB] text-[#34C759]"}
  defp difficulty_badge("hard"), do: {"Hard", "bg-[#FFE5E5] text-[#FF3B30]"}
  defp difficulty_badge(_), do: {"Medium", "bg-[#FFF8E0] text-[#FF9500]"}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <%!-- Header Card --%>
      <div class="bg-white rounded-2xl shadow-md p-4 sm:p-6 mb-6">
        <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
          <div class="min-w-0">
            <h1 class="text-2xl sm:text-3xl font-bold text-[#1C1C1E]">{@content["title"]}</h1>
            <p class="text-sm text-[#8E8E93] mt-1">{@content["generated_for"]}</p>
            <div class="flex items-center gap-4 mt-2">
              <span :if={@content["test_date"]} class="text-sm text-[#8E8E93]">
                <.icon name="hero-calendar" class="w-4 h-4 inline -mt-0.5" />
                {if @content["days_until_test"] do
                  "#{days_label(@content["days_until_test"])} (#{@content["test_date"]})"
                else
                  @content["test_date"]
                end}
              </span>
              <span class="text-sm text-[#8E8E93]">
                <.icon name="hero-book-open" class="w-4 h-4 inline -mt-0.5" />
                {length(@sections)} weak areas
              </span>
            </div>
          </div>

          <div class="flex items-center gap-4 shrink-0">
            <%!-- Progress Ring --%>
            <div class="text-center">
              <p class="text-3xl font-bold text-[#1C1C1E]">
                {round(@content["aggregate_score"] || 0)}%
              </p>
              <p class="text-xs text-[#8E8E93]">readiness</p>
            </div>
            <div :if={@progress != %{}} class="text-center">
              <p class="text-3xl font-bold text-[#4CD964]">
                {progress_percent(@progress)}%
              </p>
              <p class="text-xs text-[#8E8E93]">reviewed</p>
            </div>
          </div>
        </div>

        <%!-- Action Buttons --%>
        <div class="flex flex-wrap gap-2 sm:gap-3 mt-4">
          <.link
            navigate={~p"/courses/#{@course_id}/practice"}
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            <.icon name="hero-play" class="w-4 h-4 inline -mt-0.5 mr-1" /> Practice Weak Areas
          </.link>
          <a
            href={~p"/export/study-guide/#{@guide.id}"}
            class="bg-white border border-[#E5E5EA] text-[#1C1C1E] font-medium px-6 py-2 rounded-full shadow-sm transition-colors hover:bg-[#F5F5F7]"
          >
            <.icon name="hero-arrow-down-tray" class="w-4 h-4 inline -mt-0.5 mr-1" /> Export
          </a>
          <.link
            navigate={~p"/courses/#{@course_id}/study-guides"}
            class="bg-white border border-[#E5E5EA] text-[#1C1C1E] font-medium px-6 py-2 rounded-full shadow-sm transition-colors hover:bg-[#F5F5F7]"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4 inline -mt-0.5 mr-1" /> All Guides
          </.link>
        </div>
      </div>

      <%!-- Tab Navigation --%>
      <div class="flex gap-2 border-b border-[#E5E5EA] mb-6">
        <button phx-click="switch_tab" phx-value-tab="overview" class={tab_class(@active_tab, "overview")}>
          Overview
        </button>
        <button phx-click="switch_tab" phx-value-tab="plan" class={tab_class(@active_tab, "plan")}>
          Study Plan
          <span :if={@study_plan != []} class="text-xs ml-1 text-[#8E8E93]">
            ({@progress["plan_days_completed"] || 0}/{length(@study_plan)})
          </span>
        </button>
        <button phx-click="switch_tab" phx-value-tab="chapters" class={tab_class(@active_tab, "chapters")}>
          Chapters
          <span class="text-xs ml-1 text-[#8E8E93]">
            ({@progress["sections_reviewed"] || 0}/{length(@sections)})
          </span>
        </button>
      </div>

      <%!-- Tab Content --%>
      <div :if={@active_tab == "overview"}>
        {render_overview(assigns)}
      </div>
      <div :if={@active_tab == "plan"}>
        {render_study_plan(assigns)}
      </div>
      <div :if={@active_tab == "chapters"}>
        {render_chapters(assigns)}
      </div>
    </div>
    """
  end

  defp render_overview(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Quick Stats --%>
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <div class="bg-white rounded-2xl shadow-md p-4 text-center">
          <p class="text-2xl font-bold text-[#FF3B30]">
            {Enum.count(@sections, &(&1["priority"] == "Critical"))}
          </p>
          <p class="text-xs text-[#8E8E93] mt-1">Critical</p>
        </div>
        <div class="bg-white rounded-2xl shadow-md p-4 text-center">
          <p class="text-2xl font-bold text-[#FFCC00]">
            {Enum.count(@sections, &(&1["priority"] == "High"))}
          </p>
          <p class="text-xs text-[#8E8E93] mt-1">High Priority</p>
        </div>
        <div class="bg-white rounded-2xl shadow-md p-4 text-center">
          <p class="text-2xl font-bold text-[#1C1C1E]">
            {@sections |> Enum.flat_map(&(&1["wrong_questions"] || [])) |> length()}
          </p>
          <p class="text-xs text-[#8E8E93] mt-1">Wrong Questions</p>
        </div>
        <div class="bg-white rounded-2xl shadow-md p-4 text-center">
          <p class="text-2xl font-bold text-[#4CD964]">
            {progress_percent(@progress)}%
          </p>
          <p class="text-xs text-[#8E8E93] mt-1">Reviewed</p>
        </div>
      </div>

      <%!-- Today's Focus (from study plan) --%>
      <div :if={@study_plan != []} class="bg-white rounded-2xl shadow-md p-6">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-3">
          <.icon name="hero-fire" class="w-5 h-5 inline -mt-0.5 text-[#FF9500]" />
          Today's Focus
        </h2>
        <% today_plan = Enum.find(@study_plan, fn d ->
          case Date.from_iso8601(d["date"]) do
            {:ok, date} -> Date.compare(date, Date.utc_today()) == :eq
            _ -> false
          end
        end) %>
        <div :if={today_plan} class="space-y-2">
          <p class="text-sm text-[#1C1C1E] font-medium">{today_plan["focus"]}</p>
          <div :if={(today_plan["chapter_ids"] || []) != []} class="flex flex-wrap gap-2 mt-2">
            <span
              :for={ch_id <- today_plan["chapter_ids"] || []}
              class="text-sm bg-[#F5F5F7] px-3 py-1 rounded-full"
            >
              {chapter_name_for_id(@sections, ch_id)}
            </span>
          </div>
          <button
            :if={!today_plan["completed"]}
            phx-click="switch_tab"
            phx-value-tab="chapters"
            class="mt-3 text-sm text-[#007AFF] hover:underline font-medium"
          >
            Start studying →
          </button>
          <p :if={today_plan["completed"]} class="mt-2 text-sm text-[#4CD964] font-medium">
            <.icon name="hero-check-circle" class="w-4 h-4 inline -mt-0.5" /> Completed!
          </p>
        </div>
        <div :if={!today_plan} class="text-sm text-[#8E8E93]">
          <p>No study session scheduled for today. Check the Study Plan tab for your schedule.</p>
        </div>
      </div>

      <%!-- Chapter Priority Overview --%>
      <div class="bg-white rounded-2xl shadow-md p-6">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-4">Chapter Breakdown</h2>
        <div :if={@sections == []} class="text-[#8E8E93] text-center py-4">
          No weak areas identified. Great job!
        </div>
        <div class="space-y-3">
          <div :for={section <- @sections} class="flex items-center gap-3">
            <span class={"text-xs font-medium px-2 py-0.5 rounded-full shrink-0 #{priority_badge_class(section["priority"])}"}>
              {section["priority"]}
            </span>
            <div class="flex-1 min-w-0">
              <div class="flex items-center justify-between mb-1">
                <span class="text-sm font-medium text-[#1C1C1E] truncate">
                  {section["chapter_name"]}
                </span>
                <span class="text-sm text-[#8E8E93] shrink-0 ml-2">
                  {round(section["score"] || 0)}%
                </span>
              </div>
              <div class="w-full bg-[#E5E5EA] rounded-full h-2">
                <div
                  class={"h-2 rounded-full #{score_color(section["score"] || 0)} transition-all"}
                  style={"width: #{section["score"] || 0}%"}
                />
              </div>
            </div>
            <.icon
              :if={section["reviewed"]}
              name="hero-check-circle-solid"
              class="w-5 h-5 text-[#4CD964] shrink-0"
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_study_plan(assigns) do
    ~H"""
    <div class="space-y-3">
      <div :if={@study_plan == []} class="bg-white rounded-2xl shadow-md p-8 text-center">
        <.icon name="hero-calendar" class="w-12 h-12 text-[#8E8E93] mx-auto mb-4" />
        <p class="text-[#8E8E93] text-lg">No study plan available.</p>
        <p class="text-[#8E8E93] text-sm mt-1">
          This guide may have been generated without a future test date.
        </p>
      </div>

      <div
        :for={day <- @study_plan}
        class={"bg-white rounded-2xl shadow-md p-4 sm:p-5 #{if day["completed"], do: "opacity-75", else: ""}"}
      >
        <div class="flex items-start gap-3">
          <%!-- Checkbox --%>
          <button
            phx-click="toggle_plan_day"
            phx-value-day={day["day"]}
            class="mt-0.5 shrink-0"
          >
            <div class={
              if day["completed"],
                do: "w-6 h-6 rounded-full bg-[#4CD964] flex items-center justify-center",
                else: "w-6 h-6 rounded-full border-2 border-[#E5E5EA] hover:border-[#4CD964] transition-colors"
            }>
              <.icon :if={day["completed"]} name="hero-check-mini" class="w-4 h-4 text-white" />
            </div>
          </button>

          <div class="flex-1 min-w-0">
            <div class="flex items-center justify-between mb-1">
              <div class="flex items-center gap-2">
                <span class="font-semibold text-[#1C1C1E]">Day {day["day"]}</span>
                <span class="text-sm text-[#8E8E93]">{day["date"]}</span>
                <span
                  :if={is_today_or_past?(day["date"]) and !day["completed"]}
                  class="text-xs bg-[#FF3B30] text-white px-2 py-0.5 rounded-full"
                >
                  {if day["date"] == Date.to_string(Date.utc_today()), do: "Today", else: "Overdue"}
                </span>
              </div>
            </div>

            <p class={"text-sm #{if day["completed"], do: "text-[#8E8E93] line-through", else: "text-[#1C1C1E]"}"}>
              {day["focus"]}
            </p>

            <div :if={(day["chapter_ids"] || []) != []} class="flex flex-wrap gap-2 mt-2">
              <button
                :for={ch_id <- day["chapter_ids"] || []}
                phx-click="switch_tab"
                phx-value-tab="chapters"
                class="text-xs bg-[#F5F5F7] hover:bg-[#E5E5EA] px-3 py-1 rounded-full transition-colors"
              >
                {chapter_name_for_id(@sections, ch_id)}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_chapters(assigns) do
    ~H"""
    <div class="space-y-4">
      <div :if={@sections == []} class="bg-white rounded-2xl shadow-md p-8 text-center">
        <p class="text-[#8E8E93] text-lg">No weak areas identified. Great job!</p>
      </div>

      <div :for={section <- @sections} class="bg-white rounded-2xl shadow-md overflow-hidden">
        <%!-- Chapter Header (clickable) --%>
        <button
          phx-click="toggle_section"
          phx-value-chapter-id={section["chapter_id"]}
          class="w-full p-4 sm:p-5 text-left hover:bg-[#FAFAFA] transition-colors"
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2 sm:gap-3 min-w-0">
              <%!-- Reviewed checkbox --%>
              <div
                phx-click="toggle_reviewed"
                phx-value-chapter-id={section["chapter_id"]}
                class={
                  if section["reviewed"],
                    do: "w-6 h-6 rounded-full bg-[#4CD964] flex items-center justify-center shrink-0",
                    else: "w-6 h-6 rounded-full border-2 border-[#E5E5EA] shrink-0"
                }
              >
                <.icon :if={section["reviewed"]} name="hero-check-mini" class="w-4 h-4 text-white" />
              </div>

              <h3 class={"font-semibold text-base sm:text-lg truncate #{if section["reviewed"], do: "text-[#8E8E93] line-through", else: "text-[#1C1C1E]"}"}>
                {section["chapter_name"]}
              </h3>
              <span class={"text-xs font-medium px-2 py-0.5 rounded-full shrink-0 #{priority_badge_class(section["priority"])}"}>
                {section["priority"]}
              </span>
            </div>
            <div class="flex items-center gap-3 shrink-0">
              <span class="font-semibold text-sm text-[#8E8E93]">
                {round(section["score"] || 0)}%
              </span>
              <.icon
                name={if MapSet.member?(@expanded_sections, section["chapter_id"]), do: "hero-chevron-up", else: "hero-chevron-down"}
                class="w-5 h-5 text-[#8E8E93]"
              />
            </div>
          </div>

          <%!-- Score bar --%>
          <div class="w-full bg-[#E5E5EA] rounded-full h-2 mt-3">
            <div
              class={"h-2 rounded-full #{score_color(section["score"] || 0)} transition-all"}
              style={"width: #{section["score"] || 0}%"}
            />
          </div>

          <%!-- Quick stats row --%>
          <div class="flex gap-4 mt-2 text-xs text-[#8E8E93]">
            <span>{length(section["wrong_questions"] || [])} wrong questions</span>
            <span :if={section["total_attempted"]}>
              {section["total_correct"] || 0}/{section["total_attempted"]} correct attempts
            </span>
            <span :if={(section["source_materials"] || []) != []}>
              {length(section["source_materials"] || [])} source materials
            </span>
          </div>
        </button>

        <%!-- Expanded Content --%>
        <div
          :if={MapSet.member?(@expanded_sections, section["chapter_id"])}
          class="border-t border-[#E5E5EA] p-4 sm:p-5 space-y-5"
        >
          <%!-- AI Chapter Summary --%>
          <div class="bg-[#F5F5F7] rounded-xl p-4">
            <div class="flex items-center justify-between mb-2">
              <h4 class="text-sm font-semibold text-[#1C1C1E]">
                <.icon name="hero-light-bulb" class="w-4 h-4 inline -mt-0.5 text-[#FF9500]" />
                AI Study Summary
              </h4>
              <button
                :if={!Map.has_key?(@chapter_summaries, section["chapter_id"])}
                phx-click="load_chapter_summary"
                phx-value-chapter-id={section["chapter_id"]}
                class="text-xs text-[#007AFF] hover:underline font-medium"
              >
                {if @loading_summary == section["chapter_id"], do: "Loading...", else: "Generate"}
              </button>
            </div>
            <div :if={Map.has_key?(@chapter_summaries, section["chapter_id"])} class="text-sm text-[#1C1C1E] leading-relaxed whitespace-pre-wrap">
              {Map.get(@chapter_summaries, section["chapter_id"])}
            </div>
            <p :if={!Map.has_key?(@chapter_summaries, section["chapter_id"]) and @loading_summary != section["chapter_id"]} class="text-sm text-[#8E8E93]">
              Click "Generate" for an AI-powered summary of what to focus on in this chapter.
            </p>
            <div :if={@loading_summary == section["chapter_id"]} class="flex items-center gap-2 text-sm text-[#8E8E93]">
              <div class="animate-spin h-4 w-4 border-2 border-[#4CD964] border-t-transparent rounded-full" />
              Generating summary...
            </div>
          </div>

          <%!-- Review Topics --%>
          <div>
            <h4 class="text-sm font-semibold text-[#1C1C1E] mb-2">Review Topics</h4>
            <ul class="list-disc list-inside text-sm text-[#8E8E93] space-y-1">
              <li :for={topic <- section["review_topics"] || []}>{if is_map(topic), do: topic["topic"] || topic["name"], else: topic}</li>
            </ul>
          </div>

          <%!-- Source Materials --%>
          <div :if={(section["source_materials"] || []) != []}>
            <h4 class="text-sm font-semibold text-[#1C1C1E] mb-2">
              <.icon name="hero-document-text" class="w-4 h-4 inline -mt-0.5" />
              Source Materials
            </h4>
            <div class="flex flex-wrap gap-2">
              <span
                :for={mat <- section["source_materials"]}
                class="text-xs bg-[#E8F8EB] text-[#34C759] px-3 py-1 rounded-full"
              >
                {mat["file_name"] || mat["name"]}
              </span>
            </div>
          </div>

          <%!-- Wrong Questions --%>
          <div :if={(section["wrong_questions"] || []) != []}>
            <h4 class="text-sm font-semibold text-[#1C1C1E] mb-3">
              Wrong Questions ({length(section["wrong_questions"])})
            </h4>
            <div class="space-y-3">
              <div
                :for={wq <- section["wrong_questions"]}
                class="bg-[#F5F5F7] rounded-xl p-4"
              >
                <div class="flex items-start justify-between gap-2">
                  <p class="text-sm text-[#1C1C1E] font-medium flex-1">{wq["content"] || wq["question_text"]}</p>
                  <div class="flex items-center gap-2 shrink-0">
                    <% {diff_label, diff_class} = difficulty_badge(wq["difficulty"]) %>
                    <span class={"text-xs px-2 py-0.5 rounded-full #{diff_class}"}>{diff_label}</span>
                    <span :if={wq["attempt_count"]} class="text-xs text-[#8E8E93]">
                      {wq["attempt_count"]}x
                    </span>
                  </div>
                </div>

                <p class="text-sm text-[#4CD964] mt-2">
                  <span class="font-medium">Answer:</span> {wq["answer"] || wq["correct_answer"]}
                </p>

                <%!-- AI Explanation --%>
                <div class="mt-2">
                  <button
                    phx-click="explain_question"
                    phx-value-question-id={wq["id"]}
                    class="text-xs text-[#007AFF] hover:underline font-medium"
                  >
                    <.icon name="hero-sparkles" class="w-3 h-3 inline -mt-0.5" />
                    {cond do
                      MapSet.member?(@loading_explanations, wq["id"]) -> "Loading..."
                      MapSet.member?(@expanded_explanations, wq["id"]) -> "Hide explanation"
                      Map.has_key?(@explanations, wq["id"]) -> "Show explanation"
                      true -> "Explain why"
                    end}
                  </button>

                  <div :if={MapSet.member?(@loading_explanations, wq["id"])} class="mt-2 flex items-center gap-2 text-xs text-[#8E8E93]">
                    <div class="animate-spin h-3 w-3 border-2 border-[#4CD964] border-t-transparent rounded-full" />
                    AI is generating an explanation...
                  </div>

                  <div
                    :if={MapSet.member?(@expanded_explanations, wq["id"]) and Map.has_key?(@explanations, wq["id"])}
                    class="mt-2 bg-white rounded-lg p-3 border border-[#E5E5EA] text-sm text-[#1C1C1E] leading-relaxed whitespace-pre-wrap"
                  >
                    {Map.get(@explanations, wq["id"])}
                  </div>
                </div>

                <p :if={wq["source_page"]} class="text-xs text-[#8E8E93] mt-2">
                  <.icon name="hero-document" class="w-3 h-3 inline -mt-0.5" />
                  Source: page {wq["source_page"]}
                </p>
              </div>
            </div>
          </div>

          <%!-- Practice this chapter --%>
          <div class="pt-2">
            <.link
              navigate={~p"/courses/#{@course_id}/practice"}
              class="inline-flex items-center gap-1 bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-5 py-2 rounded-full shadow-md transition-colors text-sm"
            >
              <.icon name="hero-play" class="w-4 h-4" />
              Practice This Chapter
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
