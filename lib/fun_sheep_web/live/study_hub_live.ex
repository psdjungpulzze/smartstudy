defmodule FunSheepWeb.StudyHubLive do
  @moduledoc """
  Topic Study Hub — supplementary materials for a specific skill section.

  Reached from: practice feedback (reveal phase), readiness weak-topic rows.

  Shows:
  - AI-generated concept overview (cached per student, regenerated after 30 days)
  - Video lessons from discovered sources
  - Recent wrong answers for review
  - CTA to practice the topic
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Assessments, Content, Courses, Learning}
  alias FunSheep.Interactor.Agents

  require Logger

  @overview_ttl_days 30

  @impl true
  def mount(%{"course_id" => course_id, "section_id" => section_id}, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]

    section = Courses.get_section!(section_id)
    course = Courses.get_course!(course_id)
    videos = Content.list_videos_for_section(section_id)
    cached_overview = Content.get_section_overview(section_id, user_role_id)
    recent_attempts = Assessments.recent_attempts_for_topic(user_role_id, section_id, 3)

    socket =
      socket
      |> assign(
        page_title: "Study: #{section.name}",
        section: section,
        course: course,
        videos: videos,
        overview: cached_overview,
        overview_loading: false,
        recent_attempts: recent_attempts,
        overview_error: nil,
        user_role_id: user_role_id
      )

    # Kick off AI generation if no cached overview or stale
    if is_nil(cached_overview) or overview_stale?(cached_overview) do
      send(self(), {:generate_overview, user_role_id, section, course})
    end

    {:ok, socket}
  end

  @impl true
  def handle_info({:generate_overview, user_role_id, section, course}, socket) do
    socket = assign(socket, overview_loading: true, overview_error: nil)
    hobbies = Learning.hobby_names_for_user(user_role_id)

    case generate_overview(section, course, hobbies) do
      {:ok, body} ->
        case Content.upsert_section_overview(section.id, user_role_id, body) do
          {:ok, _} ->
            overview = Content.get_section_overview(section.id, user_role_id)
            {:noreply, assign(socket, overview: overview, overview_loading: false)}

          {:error, reason} ->
            Logger.warning("[StudyHubLive] Failed to persist overview: #{inspect(reason)}")
            {:noreply, assign(socket, overview_loading: false, overview_error: :persist_failed)}
        end

      {:error, reason} ->
        Logger.warning("[StudyHubLive] Failed to generate overview: #{inspect(reason)}")
        {:noreply, assign(socket, overview_loading: false, overview_error: :generation_failed)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-6 space-y-6">
      <%!-- Header --%>
      <div>
        <.link
          navigate={~p"/practice?course_id=#{@course.id}"}
          class="inline-flex items-center gap-1 text-sm text-[#8E8E93] hover:text-[#1C1C1E] mb-4 transition-colors"
        >
          <.icon name="hero-chevron-left" class="w-4 h-4" /> Back to Practice
        </.link>
        <h1 class="text-2xl font-bold text-[#1C1C1E]">{@section.name}</h1>
        <p class="text-sm text-[#8E8E93] mt-1">{@course.name}</p>
      </div>

      <%!-- Concept Overview --%>
      <div class="bg-white rounded-2xl shadow-sm p-6 border border-[#E5E5EA]">
        <h2 class="text-sm font-semibold text-[#8E8E93] uppercase tracking-wide mb-3">
          Concept Overview
        </h2>
        <div :if={@overview_loading} class="flex items-center gap-2 text-[#8E8E93] text-sm">
          <span class="animate-spin inline-block w-4 h-4 border-2 border-[#4CD964] border-t-transparent rounded-full">
          </span>
          Generating overview...
        </div>
        <p :if={@overview && !@overview_loading} class="text-[#1C1C1E] leading-relaxed">
          {@overview.body}
        </p>
        <p
          :if={@overview_error == :generation_failed && !@overview_loading}
          class="text-[#FF3B30] text-sm"
        >
          Could not generate an overview right now. Try refreshing the page.
        </p>
        <p
          :if={!@overview && !@overview_loading && is_nil(@overview_error)}
          class="text-[#8E8E93] text-sm italic"
        >
          No overview available yet.
        </p>
      </div>

      <%!-- Video Lessons --%>
      <div :if={@videos != []} class="bg-white rounded-2xl shadow-sm p-6 border border-[#E5E5EA]">
        <h2 class="text-sm font-semibold text-[#8E8E93] uppercase tracking-wide mb-3">
          <.icon name="hero-video-camera" class="w-4 h-4 inline mr-1" /> Video Lessons
        </h2>
        <ul class="space-y-3">
          <li :for={video <- @videos}>
            <.link
              href={video.url}
              target="_blank"
              rel="noopener"
              class="flex items-center gap-3 p-3 rounded-xl bg-[#F5F5F7] hover:bg-[#E8F8EB] transition-colors group"
            >
              <span class="w-8 h-8 rounded-full bg-[#007AFF] flex items-center justify-center shrink-0 group-hover:bg-[#4CD964] transition-colors">
                <.icon name="hero-play" class="w-4 h-4 text-white" />
              </span>
              <span class="text-sm font-medium text-[#1C1C1E] line-clamp-2">{video.title}</span>
              <.icon
                name="hero-arrow-top-right-on-square"
                class="w-4 h-4 text-[#8E8E93] ml-auto shrink-0"
              />
            </.link>
          </li>
        </ul>
      </div>

      <%!-- Practice CTA --%>
      <div class="bg-[#E8F8EB] rounded-2xl p-6 flex items-center justify-between gap-4">
        <div>
          <p class="font-semibold text-[#1C1C1E]">Practice this topic</p>
          <p :if={wrong_count(@recent_attempts) > 0} class="text-sm text-[#8E8E93] mt-0.5">
            {wrong_count(@recent_attempts)} recent wrong answer(s) to review
          </p>
        </div>
        <.link
          navigate={~p"/practice?course_id=#{@course.id}"}
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-semibold px-5 py-2.5 rounded-full shadow-sm transition-colors whitespace-nowrap text-sm"
        >
          Practice Now
        </.link>
      </div>

      <%!-- Recent Wrong Answers --%>
      <div
        :if={@recent_attempts != []}
        class="bg-white rounded-2xl shadow-sm p-6 border border-[#E5E5EA]"
      >
        <h2 class="text-sm font-semibold text-[#8E8E93] uppercase tracking-wide mb-3">
          Recent Wrong Answers
        </h2>
        <div class="space-y-4">
          <details
            :for={attempt <- @recent_attempts}
            :if={!attempt.is_correct}
            class="rounded-xl border border-[#E5E5EA] overflow-hidden"
          >
            <summary class="px-4 py-3 text-sm font-medium text-[#1C1C1E] cursor-pointer select-none hover:bg-[#F5F5F7] transition-colors list-none flex items-center justify-between">
              <span class="line-clamp-2">{attempt.question.content}</span>
              <.icon name="hero-chevron-down" class="w-4 h-4 text-[#8E8E93] shrink-0 ml-2" />
            </summary>
            <div class="px-4 py-3 bg-[#F5F5F7] border-t border-[#E5E5EA] space-y-2">
              <div>
                <p class="text-xs font-medium text-[#FF3B30] uppercase tracking-wide">Your Answer</p>
                <p class="text-sm text-[#1C1C1E]">{attempt.answer_given || "(no answer)"}</p>
              </div>
              <div>
                <p class="text-xs font-medium text-[#4CD964] uppercase tracking-wide">
                  Correct Answer
                </p>
                <p class="text-sm text-[#1C1C1E]">{attempt.question.answer}</p>
              </div>
              <div :if={attempt.question.explanation}>
                <p class="text-xs font-medium text-[#8E8E93] uppercase tracking-wide">Explanation</p>
                <p class="text-sm text-[#8E8E93]">{attempt.question.explanation}</p>
              </div>
            </div>
          </details>
        </div>
      </div>
    </div>
    """
  end

  # ── Private helpers ──

  defp overview_stale?(overview) do
    cutoff = DateTime.add(DateTime.utc_now(), -@overview_ttl_days * 24 * 3600, :second)
    DateTime.before?(overview.generated_at, cutoff)
  end

  defp wrong_count(attempts) do
    Enum.count(attempts, &(!&1.is_correct))
  end

  defp generate_overview(section, course, hobbies) do
    hobby_instruction =
      if hobbies != [] do
        hobby_str = hobbies |> Enum.take(3) |> Enum.join(", ")

        "The student enjoys: #{hobby_str}. Use a brief analogy from their interests if it fits naturally."
      else
        ""
      end

    prompt = """
    You are a study coach helping a student prepare for #{course.name}.
    In 2-3 clear sentences, explain the concept: "#{section.name}".
    #{hobby_instruction}
    Do not introduce new vocabulary without defining it. Be concise and direct.
    """

    Agents.chat("study_guide", String.trim(prompt), %{source: "study_hub_overview"})
  end
end
