defmodule FunSheepWeb.StudyGuideLive do
  use FunSheepWeb, :live_view

  alias FunSheep.Learning

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    guide = Learning.get_study_guide!(id)
    content = guide.content || %{}
    sections = Map.get(content, "sections", [])

    {:ok,
     assign(socket,
       page_title: Map.get(content, "title", "Study Guide"),
       guide: guide,
       content: content,
       sections: sections,
       expanded_questions: MapSet.new()
     )}
  end

  @impl true
  def handle_event("toggle_questions", %{"chapter-id" => chapter_id}, socket) do
    expanded = socket.assigns.expanded_questions

    expanded =
      if MapSet.member?(expanded, chapter_id) do
        MapSet.delete(expanded, chapter_id)
      else
        MapSet.put(expanded, chapter_id)
      end

    {:noreply, assign(socket, expanded_questions: expanded)}
  end

  defp priority_badge_class("Critical"), do: "bg-[#FF3B30] text-white"
  defp priority_badge_class("High"), do: "bg-[#FFCC00] text-[#1C1C1E]"
  defp priority_badge_class("Medium"), do: "bg-[#007AFF] text-white"
  defp priority_badge_class("Low"), do: "bg-[#4CD964] text-white"
  defp priority_badge_class(_), do: "bg-[#8E8E93] text-white"

  defp score_color(score) when score >= 70, do: "bg-[#4CD964]"
  defp score_color(score) when score >= 40, do: "bg-[#FFCC00]"
  defp score_color(_), do: "bg-[#FF3B30]"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <%!-- Header --%>
      <div class="bg-white rounded-2xl shadow-md p-6 mb-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-3xl font-bold text-[#1C1C1E]">{@content["title"]}</h1>
            <p class="text-sm text-[#8E8E93] mt-1">{@content["generated_for"]}</p>
            <p :if={@content["test_date"]} class="text-sm text-[#8E8E93]">
              Test date: {@content["test_date"]}
            </p>
          </div>

          <div class="text-center">
            <p class="text-3xl font-bold text-[#1C1C1E]">
              {round(@content["aggregate_score"] || 0)}%
            </p>
            <p class="text-xs text-[#8E8E93]">aggregate score</p>
          </div>
        </div>

        <div class="flex gap-3 mt-4">
          <button
            disabled
            class="bg-[#E5E5EA] text-[#8E8E93] font-medium px-6 py-2 rounded-full shadow-md cursor-not-allowed"
          >
            Export as PDF
          </button>
          <button
            disabled
            class="bg-[#E5E5EA] text-[#8E8E93] font-medium px-6 py-2 rounded-full shadow-md cursor-not-allowed"
          >
            Practice These Topics
          </button>
          <.link
            navigate={~p"/study-guides"}
            class="bg-white border border-[#E5E5EA] text-[#1C1C1E] font-medium px-6 py-2 rounded-full shadow-sm transition-colors hover:bg-[#F5F5F7]"
          >
            Back to Guides
          </.link>
        </div>
      </div>

      <%!-- Sections --%>
      <div :if={@sections == []} class="bg-white rounded-2xl shadow-md p-8 text-center">
        <p class="text-[#8E8E93] text-lg">No weak areas identified. Great job!</p>
      </div>

      <div class="space-y-4">
        <div :for={section <- @sections} class="bg-white rounded-2xl shadow-md p-6">
          <div class="flex items-center justify-between mb-3">
            <div class="flex items-center gap-3">
              <h3 class="font-semibold text-[#1C1C1E] text-lg">{section["chapter_name"]}</h3>
              <span class={"text-xs font-medium px-3 py-1 rounded-full #{priority_badge_class(section["priority"])}"}>
                {section["priority"]}
              </span>
            </div>
            <span class="font-semibold text-sm text-[#8E8E93]">
              {round(section["score"] || 0)}%
            </span>
          </div>

          <%!-- Score bar --%>
          <div class="w-full bg-[#E5E5EA] rounded-full h-3 mb-4">
            <div
              class={"h-3 rounded-full #{score_color(section["score"] || 0)} transition-all"}
              style={"width: #{section["score"] || 0}%"}
            >
            </div>
          </div>

          <%!-- Review Topics --%>
          <div class="mb-3">
            <h4 class="text-sm font-medium text-[#1C1C1E] mb-2">Review Topics</h4>
            <ul class="list-disc list-inside text-sm text-[#8E8E93] space-y-1">
              <li :for={topic <- section["review_topics"] || []}>{topic}</li>
            </ul>
          </div>

          <%!-- Wrong Questions (expandable) --%>
          <div :if={(section["wrong_questions"] || []) != []}>
            <button
              phx-click="toggle_questions"
              phx-value-chapter-id={section["chapter_id"]}
              class="text-sm text-[#007AFF] hover:underline font-medium"
            >
              {if MapSet.member?(@expanded_questions, section["chapter_id"]),
                do: "Hide",
                else: "Show"} wrong questions ({length(section["wrong_questions"])})
            </button>

            <div
              :if={MapSet.member?(@expanded_questions, section["chapter_id"])}
              class="mt-3 space-y-3"
            >
              <div
                :for={wq <- section["wrong_questions"]}
                class="bg-[#F5F5F7] rounded-xl p-4"
              >
                <p class="text-sm text-[#1C1C1E] font-medium">{wq["content"]}</p>
                <p class="text-sm text-[#4CD964] mt-1">
                  <span class="font-medium">Answer:</span> {wq["answer"]}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
