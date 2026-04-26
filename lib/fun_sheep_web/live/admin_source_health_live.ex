defmodule FunSheepWeb.AdminSourceHealthLive do
  @moduledoc """
  Phase 8 — admin source-health dashboard.

  Single page that surfaces the three signals the April audit made us
  wish we had:

    1. Per-course source-mix breakdown (how many questions per
       source_type, how many passed) — powered by Phase 1's
       `Questions.questions_by_source_type/2`.
    2. Coverage heatmap: chapters × difficulty × adaptive-eligible
       count — powered by Phase 1's `Questions.coverage_by_chapter/1`.
       Surfaces the same deficits the Phase 6 CoverageAuditWorker
       fires on, so admins can spot gaps before the nightly cron runs.
    3. Material mismatch queue — uploaded materials where the user-
       supplied `material_kind` disagrees with the AI-verified
       `classified_kind`. The Phase 0 \"answer-key image uploaded as
       textbook\" incident lives here — every such row gets flagged.
  """

  use FunSheepWeb, :live_view

  import FunSheepWeb.Components.AdminSidebar
  import Ecto.Query

  alias FunSheep.Content.UploadedMaterial
  alias FunSheep.Courses.Course
  alias FunSheep.{Courses, Questions, Repo}
  alias FunSheep.Workers.CoverageAuditWorker

  @source_order [:ai_generated, :user_uploaded, :web_scraped, :curated, :unknown]
  @difficulties [:easy, :medium, :hard]

  @impl true
  def mount(_params, _session, socket) do
    courses =
      from(c in Course, order_by: [desc: c.inserted_at], limit: 25)
      |> Repo.all()

    selected = List.first(courses)

    {:ok,
     socket
     |> assign(:page_title, "Source health")
     |> assign(:courses, courses)
     |> assign(:selected_course, selected)
     |> assign(:source_order, @source_order)
     |> assign(:difficulties, @difficulties)
     |> assign(:mismatches, list_mismatches())
     |> load_course_health(selected)}
  end

  @impl true
  def handle_event("select_course", %{"course_id" => id}, socket) do
    course = Enum.find(socket.assigns.courses, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:selected_course, course)
     |> load_course_health(course)}
  end

  def handle_event("trigger_audit", %{"course_id" => id}, socket) do
    CoverageAuditWorker.enqueue_for_course(id)

    {:noreply,
     socket
     |> put_flash(:info, "Coverage audit queued. It runs in the background.")}
  end

  defp load_course_health(socket, nil) do
    socket
    |> assign(:source_mix, %{})
    |> assign(:coverage_grid, [])
    |> assign(:target_per_tuple, CoverageAuditWorker.target_per_tuple())
  end

  defp load_course_health(socket, %Course{} = course) do
    source_mix = Questions.questions_by_source_type(course.id)
    raw_coverage = Questions.coverage_by_chapter(course.id)
    chapters = Courses.list_chapters_by_course(course.id)

    coverage_grid =
      Enum.map(chapters, fn ch ->
        counts = Enum.map(@difficulties, &Map.get(raw_coverage, {ch.id, &1}, 0))
        {ch, counts}
      end)

    socket
    |> assign(:source_mix, source_mix)
    |> assign(:coverage_grid, coverage_grid)
    |> assign(:target_per_tuple, CoverageAuditWorker.target_per_tuple())
  end

  # Materials where user-supplied `material_kind` and AI-verified
  # `classified_kind` disagree (not counting `:uncertain` /
  # `:unusable` — those are noise, not mismatches). Mirrors
  # `MaterialClassificationWorker.mismatch?/2`.
  defp list_mismatches do
    from(m in UploadedMaterial,
      where: not is_nil(m.classified_kind),
      where: m.classified_kind not in [:uncertain, :unusable],
      where:
        fragment(
          "NOT (
            (? = 'sample_questions' AND ?::text = 'question_bank') OR
            (? = 'textbook' AND ?::text = 'knowledge_content') OR
            (? = 'supplementary_book' AND ?::text = 'knowledge_content') OR
            (? = 'lecture_notes' AND ?::text = 'knowledge_content') OR
            (? = 'syllabus' AND ?::text = 'knowledge_content')
          )",
          m.material_kind,
          m.classified_kind,
          m.material_kind,
          m.classified_kind,
          m.material_kind,
          m.classified_kind,
          m.material_kind,
          m.classified_kind,
          m.material_kind,
          m.classified_kind
        ),
      order_by: [desc: m.kind_classified_at],
      limit: 50,
      preload: [:course]
    )
    |> Repo.all()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex">
      <.admin_sidebar current_path="/admin/source-health" />
      <div class="flex-1 max-w-6xl p-6 space-y-8">
        <header class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-semibold text-[#1C1C1E]">Source health</h1>
            <p class="text-sm text-[#8E8E93] mt-1">
              Provenance, coverage, and material-kind mismatches per course.
            </p>
          </div>
        </header>

        <section class="bg-white rounded-2xl shadow-md p-6">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-lg font-semibold text-[#1C1C1E]">Course</h2>
            <form phx-change="select_course" class="flex items-center gap-2">
              <select
                name="course_id"
                class="px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors text-sm"
              >
                <option
                  :for={course <- @courses}
                  value={course.id}
                  selected={@selected_course && @selected_course.id == course.id}
                >
                  {course.name} ({FunSheep.Courses.format_grades(course.grades)})
                </option>
              </select>
            </form>
          </div>

          <div :if={@selected_course}>
            <h3 class="text-sm font-medium text-[#1C1C1E] mb-3">Source mix (passed questions)</h3>
            <div class="grid grid-cols-2 md:grid-cols-5 gap-3 mb-6">
              <div
                :for={type <- @source_order}
                class="bg-[#F5F5F7] rounded-xl p-4 text-center"
                id={"source-#{type}"}
              >
                <p class="text-xs text-[#8E8E93] uppercase tracking-wide">
                  {humanize_source(type)}
                </p>
                <p class="text-2xl font-bold text-[#1C1C1E] mt-1">
                  {Map.get(@source_mix, type, 0)}
                </p>
              </div>
            </div>

            <div class="flex items-center justify-between mb-2">
              <h3 class="text-sm font-medium text-[#1C1C1E]">
                Coverage heatmap · target {@target_per_tuple} per (chapter, difficulty)
              </h3>
              <button
                phx-click="trigger_audit"
                phx-value-course_id={@selected_course.id}
                class="px-4 py-1.5 text-xs bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium rounded-full shadow-md transition-colors"
              >
                Run coverage audit
              </button>
            </div>

            <div :if={@coverage_grid != []} class="overflow-x-auto border border-[#E5E5EA] rounded-xl">
              <table class="min-w-full text-sm">
                <thead class="bg-[#F5F5F7] text-[#8E8E93] text-xs uppercase tracking-wide">
                  <tr>
                    <th class="px-4 py-2 text-left font-medium">Chapter</th>
                    <th
                      :for={d <- @difficulties}
                      class="px-4 py-2 text-center font-medium"
                      id={"diff-header-#{d}"}
                    >
                      {Atom.to_string(d)}
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-[#F5F5F7]">
                  <tr :for={{ch, counts} <- @coverage_grid}>
                    <td class="px-4 py-2 font-medium text-[#1C1C1E]">
                      {String.slice(ch.name, 0, 50)}
                    </td>
                    <td
                      :for={count <- counts}
                      class={["px-4 py-2 text-center", heatmap_class(count, @target_per_tuple)]}
                    >
                      {count}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p :if={@coverage_grid == []} class="text-sm text-[#8E8E93]">
              No chapters registered for this course yet.
            </p>
          </div>
        </section>

        <section class="bg-white rounded-2xl shadow-md p-6">
          <h2 class="text-lg font-semibold text-[#1C1C1E] mb-1">Material mismatches</h2>
          <p class="text-sm text-[#8E8E93] mb-4">
            Uploaded materials where the user-declared kind differs from the AI-verified kind.
            The Phase 0 incident (\"answer-key image uploaded as textbook\") surfaces here.
          </p>
          <div :if={@mismatches != []} class="overflow-x-auto border border-[#E5E5EA] rounded-xl">
            <table class="min-w-full text-sm">
              <thead class="bg-[#F5F5F7] text-[#8E8E93] text-xs uppercase tracking-wide">
                <tr>
                  <th class="px-4 py-2 text-left font-medium">File</th>
                  <th class="px-4 py-2 text-left font-medium">Course</th>
                  <th class="px-4 py-2 text-center font-medium">User said</th>
                  <th class="px-4 py-2 text-center font-medium">Classifier said</th>
                  <th class="px-4 py-2 text-center font-medium">Confidence</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-[#F5F5F7]">
                <tr :for={m <- @mismatches}>
                  <td class="px-4 py-2 font-medium text-[#1C1C1E] truncate max-w-xs">
                    {m.file_name}
                  </td>
                  <td class="px-4 py-2 text-[#8E8E93]">
                    {m.course && m.course.name}
                  </td>
                  <td class="px-4 py-2 text-center">
                    <span class="px-2 py-1 rounded-full text-xs bg-[#F5F5F7] text-[#1C1C1E]">
                      {m.material_kind}
                    </span>
                  </td>
                  <td class="px-4 py-2 text-center">
                    <span class={[
                      "px-2 py-1 rounded-full text-xs font-medium",
                      mismatch_badge(m.classified_kind)
                    ]}>
                      {m.classified_kind}
                    </span>
                  </td>
                  <td class="px-4 py-2 text-center text-[#8E8E93]">
                    {format_confidence(m.kind_confidence)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p :if={@mismatches == []} class="text-sm text-[#8E8E93]">
            No mismatches right now. Classifier and user labels agree on every classified material.
          </p>
        </section>
      </div>
    </div>
    """
  end

  defp humanize_source(:ai_generated), do: "AI-generated"
  defp humanize_source(:user_uploaded), do: "Uploaded"
  defp humanize_source(:web_scraped), do: "Web-scraped"
  defp humanize_source(:curated), do: "Curated"
  defp humanize_source(:unknown), do: "Unknown"

  # Cell color scales from red (empty) through amber (below target) to
  # green (at or above target). Rendered as Tailwind classes so it
  # reads at a glance.
  defp heatmap_class(count, target) when is_integer(count) and is_integer(target) do
    ratio = if target > 0, do: count / target, else: 0

    cond do
      ratio >= 1.0 -> "bg-[#E8F8EB] text-[#3DBF55] font-semibold"
      ratio >= 0.5 -> "bg-yellow-50 text-yellow-700"
      ratio >= 0.1 -> "bg-orange-50 text-orange-700"
      true -> "bg-red-50 text-[#FF3B30] font-semibold"
    end
  end

  # :answer_key is the dangerous one — the Phase 0 failure — so it
  # gets a red badge. Others get amber so admins notice but don't panic.
  defp mismatch_badge(:answer_key), do: "bg-red-100 text-[#FF3B30]"
  defp mismatch_badge(_), do: "bg-orange-50 text-orange-700"

  defp format_confidence(nil), do: "—"
  defp format_confidence(c) when is_float(c), do: "#{round(c * 100)}%"
  defp format_confidence(_), do: "—"
end
