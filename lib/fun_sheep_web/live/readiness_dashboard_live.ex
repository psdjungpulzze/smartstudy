defmodule FunSheepWeb.ReadinessDashboardLive do
  use FunSheepWeb, :live_view

  alias FunSheep.{Assessments, Courses}
  alias FunSheep.Learning.StudyGuideGenerator

  @impl true
  def mount(%{"schedule_id" => schedule_id}, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    schedule = Assessments.get_test_schedule_with_course!(schedule_id)
    readiness = Assessments.latest_readiness(user_role_id, schedule_id)
    history = Assessments.list_readiness_history(user_role_id, schedule_id, 5)

    chapter_ids = get_in(schedule.scope, ["chapter_ids"]) || []
    chapters = Courses.list_chapters_by_ids(chapter_ids)

    chapter_breakdown =
      chapters
      |> Enum.map(fn ch ->
        score =
          if readiness do
            Map.get(readiness.chapter_scores || %{}, ch.id, 0.0)
          else
            0.0
          end

        %{id: ch.id, name: ch.name, score: score}
      end)
      |> Enum.sort_by(& &1.score)

    {:ok,
     assign(socket,
       page_title: "Readiness: #{schedule.name}",
       schedule: schedule,
       readiness: readiness,
       history: history,
       chapter_breakdown: chapter_breakdown,
       today: Date.utc_today(),
       generating_guide: false
     )}
  end

  @impl true
  def handle_event("calculate_readiness", _params, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    schedule_id = socket.assigns.schedule.id

    case Assessments.calculate_and_save_readiness(user_role_id, schedule_id) do
      {:ok, readiness} ->
        history = Assessments.list_readiness_history(user_role_id, schedule_id, 5)
        chapter_ids = get_in(socket.assigns.schedule.scope, ["chapter_ids"]) || []
        chapters = Courses.list_chapters_by_ids(chapter_ids)

        chapter_breakdown =
          chapters
          |> Enum.map(fn ch ->
            score = Map.get(readiness.chapter_scores || %{}, ch.id, 0.0)
            %{id: ch.id, name: ch.name, score: score}
          end)
          |> Enum.sort_by(& &1.score)

        {:noreply,
         socket
         |> assign(readiness: readiness, history: history, chapter_breakdown: chapter_breakdown)
         |> put_flash(:info, "Readiness score updated.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to calculate readiness.")}
    end
  end

  @impl true
  def handle_event("generate_study_guide", _params, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    schedule_id = socket.assigns.schedule.id

    case StudyGuideGenerator.generate(user_role_id, schedule_id) do
      {:ok, guide} ->
        {:noreply,
         socket
         |> put_flash(:info, "Study guide generated.")
         |> push_navigate(to: ~p"/study-guides/#{guide.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to generate study guide.")}
    end
  end

  defp days_remaining(test_date) do
    Date.diff(test_date, Date.utc_today())
  end

  defp days_color(days) when days < 3, do: "text-[#FF3B30]"
  defp days_color(days) when days <= 7, do: "text-[#FFCC00]"
  defp days_color(_), do: "text-[#4CD964]"

  defp score_color(score) when score >= 70, do: "bg-[#4CD964]"
  defp score_color(score) when score >= 40, do: "bg-[#FFCC00]"
  defp score_color(_), do: "bg-[#FF3B30]"

  defp score_text_color(score) when score >= 70, do: "text-[#4CD964]"
  defp score_text_color(score) when score >= 40, do: "text-[#FFCC00]"
  defp score_text_color(_), do: "text-[#FF3B30]"

  defp aggregate_score(nil), do: 0.0
  defp aggregate_score(readiness), do: readiness.aggregate_score

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <%!-- Header Section --%>
      <div class="bg-white rounded-2xl shadow-md p-6 mb-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-3xl font-bold text-[#1C1C1E]">{@schedule.name}</h1>
            <p class="text-sm text-[#8E8E93] mt-1">
              {if @schedule.course, do: @schedule.course.name, else: "Unknown Course"}
            </p>
            <p class="text-sm text-[#8E8E93]">
              Test date: {Calendar.strftime(@schedule.test_date, "%B %d, %Y")}
            </p>
          </div>

          <div class="flex items-center gap-8">
            <%!-- Days Remaining --%>
            <div class="text-center">
              <p class={"text-3xl font-bold #{days_color(days_remaining(@schedule.test_date))}"}>
                {days_remaining(@schedule.test_date)}
              </p>
              <p class="text-xs text-[#8E8E93]">days left</p>
            </div>

            <%!-- Circular Progress Indicator --%>
            <div class="relative w-24 h-24">
              <svg class="w-24 h-24 transform -rotate-90" viewBox="0 0 100 100">
                <circle
                  cx="50"
                  cy="50"
                  r="42"
                  fill="none"
                  stroke="#E5E5EA"
                  stroke-width="8"
                />
                <circle
                  cx="50"
                  cy="50"
                  r="42"
                  fill="none"
                  stroke={
                    if aggregate_score(@readiness) >= 70,
                      do: "#4CD964",
                      else: if(aggregate_score(@readiness) >= 40, do: "#FFCC00", else: "#FF3B30")
                  }
                  stroke-width="8"
                  stroke-dasharray={Float.to_string(aggregate_score(@readiness) / 100 * 263.9) <> " 263.9"}
                  stroke-linecap="round"
                />
              </svg>
              <div class="absolute inset-0 flex items-center justify-center">
                <span class={"text-xl font-bold #{score_text_color(aggregate_score(@readiness))}"}>
                  {round(aggregate_score(@readiness))}%
                </span>
              </div>
            </div>
          </div>
        </div>

        <p class="mt-4 text-sm text-[#8E8E93]">
          {days_remaining(@schedule.test_date)} days left, readiness: {round(
            aggregate_score(@readiness)
          )}%
        </p>
      </div>

      <%!-- Chapter Breakdown Section --%>
      <div class="bg-white rounded-2xl shadow-md p-6 mb-6">
        <h2 class="text-xl font-semibold text-[#1C1C1E] mb-4">Chapter Breakdown</h2>

        <div :if={@chapter_breakdown == []} class="text-center py-4">
          <p class="text-[#8E8E93]">No chapters in test scope.</p>
        </div>

        <div class="space-y-4">
          <div :for={chapter <- @chapter_breakdown} class="flex items-center gap-4">
            <div class="w-40 truncate">
              <p class="font-medium text-[#1C1C1E] text-sm">{chapter.name}</p>
            </div>
            <div class="flex-1">
              <div class="w-full bg-[#E5E5EA] rounded-full h-3">
                <div
                  class={"h-3 rounded-full #{score_color(chapter.score)} transition-all"}
                  style={"width: #{chapter.score}%"}
                >
                </div>
              </div>
            </div>
            <div class="w-16 text-right">
              <span class={"font-semibold text-sm #{score_text_color(chapter.score)}"}>
                {round(chapter.score)}%
              </span>
            </div>
          </div>
        </div>
      </div>

      <%!-- Actions Section --%>
      <div class="bg-white rounded-2xl shadow-md p-6 mb-6">
        <h2 class="text-xl font-semibold text-[#1C1C1E] mb-4">Actions</h2>
        <div class="flex flex-wrap gap-3">
          <.link
            navigate={~p"/tests/#{@schedule.id}/assess"}
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Start Assessment
          </.link>
          <button
            phx-click="generate_study_guide"
            class="bg-[#007AFF] hover:bg-blue-600 text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Generate Study Guide
          </button>
          <button
            disabled
            class="bg-[#E5E5EA] text-[#8E8E93] font-medium px-6 py-2 rounded-full shadow-md cursor-not-allowed"
          >
            Practice Weak Areas
          </button>
          <button
            phx-click="calculate_readiness"
            class="bg-white border border-[#4CD964] text-[#4CD964] hover:bg-[#E8F8EB] font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Recalculate Readiness
          </button>
        </div>
      </div>

      <%!-- Score Trend Section --%>
      <div class="bg-white rounded-2xl shadow-md p-6">
        <h2 class="text-xl font-semibold text-[#1C1C1E] mb-4">Score History</h2>

        <div :if={@history == []} class="text-center py-4">
          <p class="text-[#8E8E93]">
            No readiness scores yet. Click "Recalculate Readiness" to get started.
          </p>
        </div>

        <div :if={@history != []} class="space-y-3">
          <div :for={score <- Enum.reverse(@history)} class="flex items-center gap-4">
            <p class="text-xs text-[#8E8E93] w-28">
              {Calendar.strftime(score.inserted_at, "%b %d, %H:%M")}
            </p>
            <div class="flex-1">
              <div class="w-full bg-[#E5E5EA] rounded-full h-4">
                <div
                  class={"h-4 rounded-full #{score_color(score.aggregate_score)} transition-all"}
                  style={"width: #{score.aggregate_score}%"}
                >
                </div>
              </div>
            </div>
            <span class={"font-semibold text-sm w-12 text-right #{score_text_color(score.aggregate_score)}"}>
              {round(score.aggregate_score)}%
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
