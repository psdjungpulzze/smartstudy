defmodule FunSheepWeb.ReadinessDashboardLive do
  use FunSheepWeb, :live_view

  import FunSheepWeb.ShareButton

  alias FunSheep.Assessments
  alias FunSheep.Learning.StudyGuideGenerator

  @impl true
  def mount(%{"course_id" => course_id, "schedule_id" => schedule_id}, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    schedule = Assessments.get_test_schedule_with_course!(schedule_id)
    readiness = Assessments.latest_readiness(user_role_id, schedule_id)
    history = Assessments.list_readiness_history(user_role_id, schedule_id, 5)
    attempts_count = Assessments.attempts_count_for_schedule(user_role_id, schedule)
    mastery_map = Assessments.topic_mastery_map(user_role_id, schedule_id)

    {:ok,
     assign(socket,
       page_title: "Readiness: #{schedule.name}",
       course_id: course_id,
       schedule: schedule,
       readiness: readiness,
       history: history,
       attempts_count: attempts_count,
       mastery_map: mastery_map,
       readiness_state: readiness_state(mastery_map),
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
        attempts_count = Assessments.attempts_count_for_schedule(user_role_id, socket.assigns.schedule)
        mastery_map = Assessments.topic_mastery_map(user_role_id, schedule_id)

        {:noreply,
         socket
         |> assign(
           readiness: readiness,
           history: history,
           attempts_count: attempts_count,
           mastery_map: mastery_map,
           readiness_state: readiness_state(mastery_map)
         )
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
         |> push_navigate(to: ~p"/courses/#{socket.assigns.course_id}/study-guides/#{guide.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to generate study guide.")}
    end
  end

  def handle_event("share_completed", %{"method" => method}, socket) do
    message = if method == "clipboard", do: "Link copied to clipboard!", else: "Shared!"
    {:noreply, put_flash(socket, :info, message)}
  end

  def handle_event("delete_schedule", _params, socket) do
    {:ok, _} = Assessments.delete_test_schedule(socket.assigns.schedule)

    {:noreply,
     socket
     |> put_flash(:info, "Test schedule deleted.")
     |> push_navigate(to: ~p"/courses/#{socket.assigns.course_id}/tests")}
  end

  # --- State Detection ---

  defp readiness_state(mastery_map) do
    all_topics = Enum.flat_map(mastery_map, & &1.topics)
    total = length(all_topics)
    tested = Enum.count(all_topics, fn t -> t.status != :insufficient_data end)

    cond do
      total == 0 -> :untested
      tested == 0 -> :untested
      tested < total -> :in_progress
      true -> :complete
    end
  end

  # --- Helpers ---

  defp readiness_share_message(score) when score >= 80, do: "Almost there!"
  defp readiness_share_message(score) when score >= 60, do: "Getting closer every day."
  defp readiness_share_message(score) when score >= 40, do: "Making progress!"
  defp readiness_share_message(_), do: "Just getting started."

  defp days_remaining(test_date), do: Date.diff(test_date, Date.utc_today())

  defp days_color(days) when days < 3, do: "text-[#FF3B30]"
  defp days_color(days) when days <= 7, do: "text-[#FFCC00]"
  defp days_color(_), do: "text-[#4CD964]"

  defp score_color(score) when score >= 70, do: "bg-[#4CD964]"
  defp score_color(score) when score >= 40, do: "bg-[#FFCC00]"
  defp score_color(_), do: "bg-[#FF3B30]"

  defp score_text_color(score) when score >= 70, do: "text-[#4CD964]"
  defp score_text_color(score) when score >= 40, do: "text-[#FFCC00]"
  defp score_text_color(_), do: "text-[#FF3B30]"

  defp status_color(:mastered), do: "text-[#4CD964]"
  defp status_color(:probing), do: "text-[#FFCC00]"
  defp status_color(:weak), do: "text-[#FF3B30]"
  defp status_color(:insufficient_data), do: "text-[#8E8E93]"

  defp status_bg(:mastered), do: "bg-[#E8F8EB] text-[#1D8234]"
  defp status_bg(:probing), do: "bg-[#FFF9E6] text-[#8A6800]"
  defp status_bg(:weak), do: "bg-[#FFF0EF] text-[#CC3328]"
  defp status_bg(:insufficient_data), do: "bg-[#F2F2F7] text-[#8E8E93]"

  defp status_label(:mastered), do: "Ready"
  defp status_label(:probing), do: "Needs Work"
  defp status_label(:weak), do: "Focus Here"
  defp status_label(:insufficient_data), do: "Not Tested"

  defp aggregate_score(nil), do: 0.0
  defp aggregate_score(readiness), do: readiness.aggregate_score

  defp topic_counts(mastery_map) do
    all = Enum.flat_map(mastery_map, & &1.topics)
    total = length(all)
    tested = Enum.count(all, fn t -> t.status != :insufficient_data end)
    weak = Enum.count(all, fn t -> t.status == :weak end)
    mastered = Enum.count(all, fn t -> t.status == :mastered end)
    %{total: total, tested: tested, weak: weak, mastered: mastered}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <%!-- Header --%>
      <div class="bg-white rounded-2xl shadow-md p-4 sm:p-6 mb-6">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div class="min-w-0">
            <div class="flex items-center gap-2">
              <h1 class="text-2xl sm:text-3xl font-bold text-[#1C1C1E] truncate">{@schedule.name}</h1>
              <.link
                navigate={~p"/courses/#{@course_id}/tests/#{@schedule.id}/edit"}
                class="text-[#8E8E93] hover:text-[#1C1C1E] p-2 rounded-lg transition-colors touch-target"
                title="Edit test"
              >
                <.icon name="hero-pencil" class="w-5 h-5" />
              </.link>
              <button
                type="button"
                phx-click="delete_schedule"
                data-confirm="Delete this test schedule? This cannot be undone."
                class="text-[#FF3B30] hover:text-red-700 p-2 rounded-lg transition-colors touch-target"
                title="Delete test"
              >
                <.icon name="hero-trash" class="w-5 h-5" />
              </button>
            </div>
            <p class="text-sm text-[#8E8E93] mt-1">
              {if @schedule.course, do: @schedule.course.name, else: "Unknown Course"}
            </p>
            <p class="text-sm text-[#8E8E93]">
              Test date: {Calendar.strftime(@schedule.test_date, "%B %d, %Y")}
            </p>
          </div>

          <div class="flex items-center gap-4 sm:gap-8">
            <div class="text-center">
              <p class={"text-2xl sm:text-3xl font-bold #{days_color(days_remaining(@schedule.test_date))}"}>
                {days_remaining(@schedule.test_date)}
              </p>
              <p class="text-[10px] sm:text-xs text-[#8E8E93]">days left</p>
            </div>

            <%!-- Gauge --%>
            <div class="relative w-20 h-20 sm:w-24 sm:h-24">
              <svg class="w-20 h-20 sm:w-24 sm:h-24 transform -rotate-90" viewBox="0 0 100 100">
                <circle cx="50" cy="50" r="42" fill="none" stroke="#E5E5EA" stroke-width="8" />
                <circle
                  cx="50"
                  cy="50"
                  r="42"
                  fill="none"
                  stroke={
                    cond do
                      @readiness_state == :untested -> "#E5E5EA"
                      aggregate_score(@readiness) >= 70 -> "#4CD964"
                      aggregate_score(@readiness) >= 40 -> "#FFCC00"
                      true -> "#FF3B30"
                    end
                  }
                  stroke-width="8"
                  stroke-dasharray={
                    Float.to_string(aggregate_score(@readiness) / 100 * 263.9) <> " 263.9"
                  }
                  stroke-linecap="round"
                />
              </svg>
              <div class="absolute inset-0 flex flex-col items-center justify-center">
                <%= if @readiness_state == :untested do %>
                  <span class="text-xs font-semibold text-[#8E8E93] text-center leading-tight">
                    Not yet<br />tested
                  </span>
                <% else %>
                  <span class={"text-lg sm:text-xl font-bold #{score_text_color(aggregate_score(@readiness))}"}>
                    {round(aggregate_score(@readiness))}%
                  </span>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <%!-- State subtitle --%>
        <p class="mt-3 sm:mt-4 text-sm text-[#8E8E93]">
          <%= case @readiness_state do %>
            <% :untested -> %>
              You haven't been tested yet — let's find out where you stand
            <% :in_progress -> %>
              <% counts = topic_counts(@mastery_map) %>
              Based on {counts.tested} of {counts.total} topics tested
              &middot; {@attempts_count} {if @attempts_count == 1,
                do: "question answered",
                else: "questions answered"}
            <% :complete -> %>
              Based on all {topic_counts(@mastery_map).total} topics
              &middot; {@attempts_count} {if @attempts_count == 1,
                do: "question answered",
                else: "questions answered"}
          <% end %>
        </p>
        <p :if={@readiness_state == :in_progress} class="mt-1 text-xs text-[#C7C7CC]">
          Complete the assessment for your full readiness picture
        </p>
      </div>

      <%!-- State A: Untested --%>
      <div :if={@readiness_state == :untested} class="bg-white rounded-2xl shadow-md p-6 sm:p-8 mb-6 text-center">
        <div class="text-5xl mb-4">🐑</div>
        <h2 class="text-xl font-bold text-[#1C1C1E] mb-2">Let's find your starting point</h2>
        <p class="text-[#8E8E93] mb-6">
          Take the diagnostic assessment to see which topics you're ready for and which need work.
        </p>
        <.link
          navigate={~p"/courses/#{@course_id}/tests/#{@schedule.id}/assess"}
          class="inline-block bg-[#4CD964] hover:bg-[#3DBF55] text-white font-semibold px-8 py-3 rounded-full shadow-md transition-colors text-lg"
        >
          Start Assessment
        </.link>
        <div :if={@mastery_map != []} class="mt-8 text-left">
          <h3 class="text-sm font-semibold text-[#8E8E93] uppercase tracking-wide mb-3">
            Topics in scope
          </h3>
          <div class="space-y-2">
            <div :for={chapter <- @mastery_map} class="bg-[#F2F2F7] rounded-xl p-3">
              <p class="font-medium text-[#1C1C1E] text-sm">{chapter.chapter_name}</p>
              <p class="text-xs text-[#8E8E93] mt-0.5">
                {length(chapter.topics)} {if length(chapter.topics) == 1,
                  do: "topic",
                  else: "topics"}
              </p>
            </div>
          </div>
        </div>
      </div>

      <%!-- State B: In Progress --%>
      <div :if={@readiness_state == :in_progress} class="space-y-6 mb-6">
        <% counts = topic_counts(@mastery_map) %>
        <%!-- Coverage progress --%>
        <div class="bg-white rounded-2xl shadow-md p-4 sm:p-6">
          <div class="flex items-center justify-between mb-2">
            <h2 class="text-sm font-semibold text-[#8E8E93] uppercase tracking-wide">
              Assessment Progress
            </h2>
            <span class="text-sm font-semibold text-[#1C1C1E]">
              {counts.tested} / {counts.total} topics
            </span>
          </div>
          <div class="w-full bg-[#E5E5EA] rounded-full h-2.5">
            <div
              class="h-2.5 rounded-full bg-[#007AFF] transition-all"
              style={"width: #{if counts.total > 0, do: round(counts.tested / counts.total * 100), else: 0}%"}
            >
            </div>
          </div>
        </div>

        <%!-- Needs Work / Focus Here --%>
        <% weak_topics =
          @mastery_map
          |> Enum.flat_map(fn ch ->
            ch.topics
            |> Enum.filter(fn t -> t.status in [:weak, :probing] end)
            |> Enum.map(fn t -> Map.put(t, :chapter_name, ch.chapter_name) end)
          end)
          |> Enum.sort_by(& &1.accuracy) %>

        <div :if={weak_topics != []} class="bg-white rounded-2xl shadow-md p-4 sm:p-6">
          <h2 class="text-lg font-semibold text-[#1C1C1E] mb-4">
            Needs Work
            <span class="ml-2 text-sm font-normal text-[#FF3B30]">
              {length(weak_topics)} topics
            </span>
          </h2>
          <div class="space-y-1">
            <.topic_row
              :for={topic <- weak_topics}
              topic={topic}
              course_id={@course_id}
              schedule_id={@schedule.id}
            />
          </div>
        </div>

        <%!-- Not yet tested --%>
        <% untested =
          @mastery_map
          |> Enum.flat_map(fn ch ->
            ch.topics
            |> Enum.filter(fn t -> t.status == :insufficient_data end)
            |> Enum.map(fn t -> Map.put(t, :chapter_name, ch.chapter_name) end)
          end) %>

        <div :if={untested != []} class="bg-white rounded-2xl shadow-md p-4 sm:p-6">
          <h2 class="text-base font-semibold text-[#8E8E93] mb-3">
            Not Yet Tested
            <span class="ml-2 text-sm font-normal">{length(untested)} topics remaining</span>
          </h2>
          <div class="space-y-0">
            <div
              :for={topic <- untested}
              class="flex items-center justify-between py-2 border-b border-[#F2F2F7] last:border-0"
            >
              <div>
                <p class="text-sm font-medium text-[#3A3A3C]">{topic.section_name}</p>
                <p class="text-xs text-[#8E8E93]">{topic.chapter_name}</p>
              </div>
              <span class="text-xs px-2 py-1 rounded-full bg-[#F2F2F7] text-[#8E8E93]">
                Not Tested
              </span>
            </div>
          </div>
        </div>

        <%!-- Mastered (collapsed) --%>
        <% mastered =
          @mastery_map
          |> Enum.flat_map(fn ch ->
            ch.topics
            |> Enum.filter(fn t -> t.status == :mastered end)
            |> Enum.map(fn t -> Map.put(t, :chapter_name, ch.chapter_name) end)
          end) %>

        <div :if={mastered != []} class="bg-white rounded-2xl shadow-md p-4 sm:p-6">
          <details>
            <summary class="cursor-pointer text-sm font-semibold text-[#4CD964] select-none">
              ✓ {length(mastered)} {if length(mastered) == 1, do: "topic", else: "topics"} ready
            </summary>
            <div class="mt-3 space-y-0">
              <div
                :for={topic <- mastered}
                class="flex items-center justify-between py-2 border-b border-[#F2F2F7] last:border-0"
              >
                <div>
                  <p class="text-sm font-medium text-[#3A3A3C]">{topic.section_name}</p>
                  <p class="text-xs text-[#8E8E93]">{topic.chapter_name}</p>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-xs font-semibold text-[#4CD964]">{round(topic.accuracy)}%</span>
                  <span class="text-xs px-2 py-1 rounded-full bg-[#E8F8EB] text-[#1D8234]">
                    Ready
                  </span>
                </div>
              </div>
            </div>
          </details>
        </div>
      </div>

      <%!-- State C: Complete --%>
      <div :if={@readiness_state == :complete} class="space-y-6 mb-6">
        <% all_topics =
          @mastery_map
          |> Enum.flat_map(fn ch ->
            ch.topics |> Enum.map(fn t -> Map.put(t, :chapter_name, ch.chapter_name) end)
          end)
          |> Enum.sort_by(& &1.accuracy) %>

        <%!-- Full ranked topic list --%>
        <div class="bg-white rounded-2xl shadow-md p-4 sm:p-6">
          <h2 class="text-lg font-semibold text-[#1C1C1E] mb-4">Topics by Readiness</h2>
          <div class="space-y-1">
            <.topic_row
              :for={topic <- all_topics}
              topic={topic}
              course_id={@course_id}
              schedule_id={@schedule.id}
            />
          </div>
        </div>

        <%!-- Chapter rollup --%>
        <div class="bg-white rounded-2xl shadow-md p-4 sm:p-6">
          <h2 class="text-lg font-semibold text-[#1C1C1E] mb-4">Chapter Summary</h2>
          <div class="space-y-1">
            <details :for={chapter <- @mastery_map} class="border-b border-[#F2F2F7] last:border-0 py-2">
              <% ch_score =
                if chapter.topics == [],
                  do: 0.0,
                  else:
                    Float.round(
                      Enum.sum(Enum.map(chapter.topics, & &1.accuracy)) / length(chapter.topics),
                      1
                    ) %>
              <summary class="cursor-pointer flex items-center justify-between select-none">
                <span class="font-medium text-[#1C1C1E] text-sm">{chapter.chapter_name}</span>
                <span class={"text-sm font-semibold #{score_text_color(ch_score)}"}>
                  {round(ch_score)}%
                </span>
              </summary>
              <div class="mt-2 ml-4 space-y-0">
                <div
                  :for={topic <- Enum.sort_by(chapter.topics, & &1.accuracy)}
                  class="flex items-center justify-between py-1.5 border-b border-[#F2F2F7] last:border-0"
                >
                  <p class="text-sm text-[#3A3A3C]">{topic.section_name}</p>
                  <div class="flex items-center gap-2">
                    <span class={"text-xs font-semibold #{status_color(topic.status)}"}>
                      {round(topic.accuracy)}%
                    </span>
                    <span class={"text-xs px-2 py-0.5 rounded-full #{status_bg(topic.status)}"}>
                      {status_label(topic.status)}
                    </span>
                  </div>
                </div>
              </div>
            </details>
          </div>
        </div>

        <%!-- Predicted score (only when confidence is not :low) --%>
        <% pred = Assessments.predicted_score_range(@readiness) %>
        <div :if={pred.confidence != :low} class="bg-white rounded-2xl shadow-md p-4 sm:p-6">
          <h2 class="text-base font-semibold text-[#1C1C1E] mb-1">Predicted Test Score</h2>
          <p class="text-sm text-[#8E8E93] mb-3">Based on your current readiness</p>
          <div class="flex items-center gap-6">
            <div class="text-center">
              <p class="text-2xl font-bold text-[#1C1C1E]">{pred.low}–{pred.high}%</p>
              <p class="text-xs text-[#8E8E93]">likely range</p>
            </div>
            <div class="text-center">
              <p class={"text-2xl font-bold #{score_text_color(pred.mid)}"}>{pred.mid}%</p>
              <p class="text-xs text-[#8E8E93]">most likely</p>
            </div>
          </div>
        </div>
      </div>

      <%!-- Actions (all states) --%>
      <div class="bg-white rounded-2xl shadow-md p-4 sm:p-6 mb-6">
        <div class="flex flex-wrap gap-2 sm:gap-3">
          <.link
            :if={@readiness_state == :untested}
            navigate={~p"/courses/#{@course_id}/tests/#{@schedule.id}/assess"}
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Start Assessment
          </.link>
          <.link
            :if={@readiness_state == :in_progress}
            navigate={~p"/courses/#{@course_id}/tests/#{@schedule.id}/assess"}
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Continue Assessment
          </.link>
          <.link
            :if={@readiness_state == :complete}
            navigate={~p"/courses/#{@course_id}/tests/#{@schedule.id}/assess"}
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Re-take Assessment
          </.link>
          <.link
            :if={@readiness_state != :untested}
            navigate={~p"/courses/#{@course_id}/practice?schedule_id=#{@schedule.id}"}
            class="bg-[#007AFF] hover:bg-blue-600 text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Practice Weak Areas
          </.link>
          <button
            :if={@readiness_state != :untested}
            phx-click="generate_study_guide"
            class="bg-white border border-[#007AFF] text-[#007AFF] hover:bg-blue-50 font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Generate Study Guide
          </button>
          <button
            phx-click="calculate_readiness"
            class="bg-white border border-[#4CD964] text-[#4CD964] hover:bg-[#E8F8EB] font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Recalculate
          </button>
          <.share_button
            :if={@readiness_state != :untested}
            title={"#{@schedule.name} - Readiness #{round(aggregate_score(@readiness))}%"}
            text={"I'm #{round(aggregate_score(@readiness))}% ready for #{@schedule.name} on Fun Sheep! #{readiness_share_message(aggregate_score(@readiness))}"}
            url={share_url(~p"/courses/#{@course_id}/tests/#{@schedule.id}/readiness")}
            label="Share Progress"
          />
        </div>
      </div>

      <%!-- Score History --%>
      <div :if={@history != []} class="bg-white rounded-2xl shadow-md p-4 sm:p-6">
        <h2 class="text-lg sm:text-xl font-semibold text-[#1C1C1E] mb-4">Score History</h2>
        <div class="space-y-2 sm:space-y-3">
          <div :for={score <- Enum.reverse(@history)} class="flex items-center gap-2 sm:gap-4">
            <p class="text-[10px] sm:text-xs text-[#8E8E93] w-20 sm:w-28 shrink-0">
              {Calendar.strftime(score.inserted_at, "%b %d, %H:%M")}
            </p>
            <div class="flex-1">
              <div class="w-full bg-[#E5E5EA] rounded-full h-3 sm:h-4">
                <div
                  class={"h-3 sm:h-4 rounded-full #{score_color(score.aggregate_score)} transition-all"}
                  style={"width: #{score.aggregate_score}%"}
                >
                </div>
              </div>
            </div>
            <span class={"font-semibold text-xs sm:text-sm w-10 sm:w-12 text-right shrink-0 #{score_text_color(score.aggregate_score)}"}>
              {round(score.aggregate_score)}%
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Topic row component (shared across States B and C) ---

  defp topic_row(assigns) do
    ~H"""
    <div class="flex items-center gap-3 py-2.5 border-b border-[#F2F2F7] last:border-0">
      <div class="flex-1 min-w-0">
        <p class="text-sm font-medium text-[#1C1C1E] truncate">{@topic.section_name}</p>
        <div class="flex items-center gap-2 mt-0.5">
          <p class="text-xs text-[#8E8E93] truncate">{@topic.chapter_name}</p>
          <span class="text-xs text-[#C7C7CC]">&middot;</span>
          <p class="text-xs text-[#8E8E93] shrink-0">
            {@topic.correct_count}/{@topic.attempts_count} correct
          </p>
        </div>
        <div class="mt-1.5 w-full bg-[#E5E5EA] rounded-full h-1.5">
          <div
            class={"h-1.5 rounded-full transition-all #{if @topic.accuracy >= 70, do: "bg-[#4CD964]", else: if(@topic.accuracy >= 40, do: "bg-[#FFCC00]", else: "bg-[#FF3B30]")}"}
            style={"width: #{@topic.accuracy}%"}
          >
          </div>
        </div>
      </div>
      <div class="flex flex-col items-end gap-1 shrink-0">
        <span class={"text-xs px-2 py-0.5 rounded-full font-medium #{status_bg(@topic.status)}"}>
          {status_label(@topic.status)}
        </span>
        <.link
          navigate={~p"/courses/#{@course_id}/practice?section_id=#{@topic.section_id}&schedule_id=#{@schedule_id}"}
          class="text-xs text-[#007AFF] hover:underline"
        >
          Practice →
        </.link>
      </div>
    </div>
    """
  end
end
