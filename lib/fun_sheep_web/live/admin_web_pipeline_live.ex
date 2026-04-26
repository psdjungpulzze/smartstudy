defmodule FunSheepWeb.AdminWebPipelineLive do
  @moduledoc """
  Phase 0 — read-only pipeline observability dashboard.

  Shows per-course stats for the web question extraction pipeline:
    - Queries fired and URL discovery counts
    - URL probe pass/fail breakdown
    - Questions extracted per domain
    - Extraction gate rejection reasons
    - Validation pass/fail by source_type

  All data comes from the database — no in-memory telemetry aggregation.
  The telemetry events emitted by the workers feed a future time-series
  reporter; this panel uses DB queries so it works even after a restart.
  """

  use FunSheepWeb, :live_view

  import Ecto.Query
  import FunSheepWeb.Components.AdminSidebar

  alias FunSheep.Repo
  alias FunSheep.Content.DiscoveredSource
  alias FunSheep.Courses.Course
  alias FunSheep.Questions.Question

  @impl true
  def mount(_params, _session, socket) do
    courses =
      from(c in Course,
        where: not is_nil(c.catalog_test_type) or c.processing_status in ["ready", "processing"],
        order_by: [desc: c.inserted_at],
        limit: 50
      )
      |> Repo.all()

    selected = List.first(courses)

    if selected && connected?(socket) do
      Phoenix.PubSub.subscribe(FunSheep.PubSub, "course:#{selected.id}:pipeline")
    end

    {:ok,
     socket
     |> assign(:page_title, "Web pipeline")
     |> assign(:courses, courses)
     |> assign(:selected_course, selected)
     |> load_pipeline_stats(selected)}
  end

  @impl true
  def handle_event("select_course", %{"course_id" => id}, socket) do
    if prev = socket.assigns.selected_course do
      Phoenix.PubSub.unsubscribe(FunSheep.PubSub, "course:#{prev.id}:pipeline")
    end

    course = Enum.find(socket.assigns.courses, &(&1.id == id))

    if course && connected?(socket) do
      Phoenix.PubSub.subscribe(FunSheep.PubSub, "course:#{course.id}:pipeline")
    end

    {:noreply,
     socket
     |> assign(:selected_course, course)
     |> load_pipeline_stats(course)}
  end

  @impl true
  def handle_info({:source_complete, _payload}, socket) do
    {:noreply, load_pipeline_stats(socket, socket.assigns.selected_course)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex min-h-screen bg-gray-50">
      <.admin_sidebar current_path={@current_path} />

      <div class="flex-1 ml-64 p-8">
        <h1 class="text-2xl font-semibold text-gray-900 mb-6">Web Pipeline</h1>

        <%!-- Course selector --%>
        <div class="mb-6">
          <label class="block text-sm font-medium text-gray-700 mb-1">Course</label>
          <select
            phx-change="select_course"
            name="course_id"
            class="w-full max-w-md px-4 py-2 border border-gray-200 rounded-xl bg-white text-sm"
          >
            <option value="">— select a course —</option>
            <%= for c <- @courses do %>
              <option value={c.id} selected={@selected_course && @selected_course.id == c.id}>
                {c.name} ({c.catalog_test_type || "school"})
              </option>
            <% end %>
          </select>
        </div>

        <%= if @selected_course do %>
          <%!-- Three-criteria check --%>
          <div class="mb-8 bg-white rounded-2xl shadow-sm p-6 border border-gray-100">
            <h2 class="text-lg font-semibold text-gray-800 mb-4">Three-Criteria Check</h2>
            <div class="grid grid-cols-3 gap-4">
              <.criteria_card
                number="1"
                label="Reputable sources found?"
                value={@top_domains |> length() |> to_string()}
                unit="domains"
                note={
                  if length(@top_domains) == 0,
                    do: "❌ No sources discovered yet",
                    else: "✅ Check domains below"
                }
              />
              <.criteria_card
                number="2"
                label="Extracted (not created)?"
                value={@web_scraped_total |> to_string()}
                unit="web_scraped questions"
                note="Spot-check source_url links to verify verbatim extraction"
              />
              <.criteria_card
                number="3"
                label="Volume — sources queued?"
                value={@sources_total |> to_string()}
                unit="sources discovered"
                note={volume_note(@sources_total, @web_scraped_passed)}
              />
            </div>
          </div>

          <%!-- Discovery stats --%>
          <div class="grid grid-cols-2 gap-6 mb-6">
            <div class="bg-white rounded-2xl shadow-sm p-6 border border-gray-100">
              <h2 class="text-base font-semibold text-gray-800 mb-4">Discovery</h2>
              <dl class="space-y-2 text-sm">
                <.stat label="Sources discovered" value={@sources_total} />
                <.stat label="Sources scraped" value={@sources_scraped} />
                <.stat label="Sources failed" value={@sources_failed} />
                <.stat label="Sources skipped" value={@sources_skipped} />
                <.stat label="Sources pending" value={@sources_pending} />
              </dl>
            </div>

            <div class="bg-white rounded-2xl shadow-sm p-6 border border-gray-100">
              <h2 class="text-base font-semibold text-gray-800 mb-4">Extraction Results</h2>
              <dl class="space-y-2 text-sm">
                <.stat label="Total questions (web_scraped)" value={@web_scraped_total} />
                <.stat
                  label="Passed validation"
                  value={@web_scraped_passed}
                  class="text-green-700 font-medium"
                />
                <.stat label="Needs review" value={@web_scraped_review} class="text-yellow-700" />
                <.stat label="Failed validation" value={@web_scraped_failed} class="text-red-700" />
                <.stat label="Pending validation" value={@web_scraped_pending} />
              </dl>
            </div>
          </div>

          <%!-- Top domains --%>
          <div class="bg-white rounded-2xl shadow-sm p-6 border border-gray-100 mb-6">
            <h2 class="text-base font-semibold text-gray-800 mb-4">
              Top Domains by Questions Extracted
            </h2>
            <%= if @top_domains == [] do %>
              <p class="text-sm text-gray-500">No web-scraped questions yet for this course.</p>
            <% else %>
              <table class="w-full text-sm">
                <thead>
                  <tr class="text-left text-gray-500 border-b border-gray-100">
                    <th class="pb-2 font-medium">Domain</th>
                    <th class="pb-2 font-medium text-right">Extracted</th>
                    <th class="pb-2 font-medium text-right">Passed</th>
                    <th class="pb-2 font-medium text-right">Pass rate</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for {domain, extracted, passed} <- @top_domains do %>
                    <tr class="border-b border-gray-50">
                      <td class="py-2 text-gray-800">{domain}</td>
                      <td class="py-2 text-right">{extracted}</td>
                      <td class="py-2 text-right text-green-700">{passed}</td>
                      <td class="py-2 text-right">
                        <span class={pass_rate_class(passed, extracted)}>
                          {pass_rate(passed, extracted)}%
                        </span>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>

          <%!-- Validation breakdown by source type --%>
          <div class="bg-white rounded-2xl shadow-sm p-6 border border-gray-100">
            <h2 class="text-base font-semibold text-gray-800 mb-4">
              Validation Breakdown by Source Type
            </h2>
            <table class="w-full text-sm">
              <thead>
                <tr class="text-left text-gray-500 border-b border-gray-100">
                  <th class="pb-2 font-medium">Source type</th>
                  <th class="pb-2 font-medium text-right">Total</th>
                  <th class="pb-2 font-medium text-right">Passed</th>
                  <th class="pb-2 font-medium text-right">Review</th>
                  <th class="pb-2 font-medium text-right">Failed</th>
                  <th class="pb-2 font-medium text-right">Pending</th>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @validation_by_source do %>
                  <tr class="border-b border-gray-50">
                    <td class="py-2">
                      <span class={source_badge_class(row.source_type)}>
                        {row.source_type}
                      </span>
                    </td>
                    <td class="py-2 text-right">{row.total}</td>
                    <td class="py-2 text-right text-green-700">{row.passed}</td>
                    <td class="py-2 text-right text-yellow-700">{row.review}</td>
                    <td class="py-2 text-right text-red-700">{row.failed}</td>
                    <td class="py-2 text-right text-gray-500">{row.pending}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% else %>
          <div class="bg-white rounded-2xl shadow-sm p-12 text-center text-gray-400">
            Select a course above to view its pipeline stats.
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # --- Sub-components ---

  defp criteria_card(assigns) do
    ~H"""
    <div class="rounded-xl border border-gray-200 p-4">
      <div class="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1">
        Criterion {@number}
      </div>
      <div class="text-sm font-medium text-gray-700 mb-2">{@label}</div>
      <div class="text-2xl font-bold text-gray-900">
        {@value} <span class="text-sm font-normal text-gray-500">{@unit}</span>
      </div>
      <div class="text-xs text-gray-500 mt-1">{@note}</div>
    </div>
    """
  end

  defp stat(assigns) do
    assigns = Map.put_new(assigns, :class, "text-gray-700")

    ~H"""
    <div class="flex justify-between">
      <dt class="text-gray-500">{@label}</dt>
      <dd class={@class}>{@value}</dd>
    </div>
    """
  end

  # --- Data loading ---

  defp load_pipeline_stats(socket, nil) do
    socket
    |> assign(:sources_total, 0)
    |> assign(:sources_scraped, 0)
    |> assign(:sources_failed, 0)
    |> assign(:sources_skipped, 0)
    |> assign(:sources_pending, 0)
    |> assign(:web_scraped_total, 0)
    |> assign(:web_scraped_passed, 0)
    |> assign(:web_scraped_review, 0)
    |> assign(:web_scraped_failed, 0)
    |> assign(:web_scraped_pending, 0)
    |> assign(:top_domains, [])
    |> assign(:validation_by_source, [])
  end

  defp load_pipeline_stats(socket, %Course{id: course_id}) do
    source_counts = source_status_counts(course_id)
    web_counts = web_question_counts(course_id)
    top_domains = top_domains_by_questions(course_id)
    validation_by_source = validation_breakdown_by_source(course_id)

    socket
    |> assign(:sources_total, Map.values(source_counts) |> Enum.sum())
    |> assign(:sources_scraped, Map.get(source_counts, "processed", 0))
    |> assign(:sources_failed, Map.get(source_counts, "failed", 0))
    |> assign(:sources_skipped, Map.get(source_counts, "skipped", 0))
    |> assign(
      :sources_pending,
      Map.get(source_counts, "discovered", 0) + Map.get(source_counts, "scraping", 0)
    )
    |> assign(:web_scraped_total, web_counts.total)
    |> assign(:web_scraped_passed, web_counts.passed)
    |> assign(:web_scraped_review, web_counts.review)
    |> assign(:web_scraped_failed, web_counts.failed)
    |> assign(:web_scraped_pending, web_counts.pending)
    |> assign(:top_domains, top_domains)
    |> assign(:validation_by_source, validation_by_source)
  end

  defp source_status_counts(course_id) do
    from(s in DiscoveredSource,
      where: s.course_id == ^course_id,
      group_by: s.status,
      select: {s.status, count(s.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp web_question_counts(course_id) do
    rows =
      from(q in Question,
        where: q.course_id == ^course_id and q.source_type == :web_scraped,
        group_by: q.validation_status,
        select: {q.validation_status, count(q.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      total: Map.values(rows) |> Enum.sum(),
      passed: Map.get(rows, :passed, 0),
      review: Map.get(rows, :needs_review, 0),
      failed: Map.get(rows, :failed, 0),
      pending: Map.get(rows, :pending, 0)
    }
  end

  defp top_domains_by_questions(course_id) do
    from(q in Question,
      where: q.course_id == ^course_id and q.source_type == :web_scraped,
      where: not is_nil(q.source_url),
      select: {q.source_url, q.validation_status}
    )
    |> Repo.all()
    |> Enum.group_by(fn {url, _} -> extract_domain(url) end)
    |> Enum.map(fn {domain, entries} ->
      total = length(entries)
      passed = Enum.count(entries, fn {_, status} -> status == :passed end)
      {domain, total, passed}
    end)
    |> Enum.sort_by(fn {_, total, _} -> total end, :desc)
    |> Enum.take(15)
  end

  defp extract_domain(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> String.replace_prefix(host, "www.", "")
      _ -> url
    end
  end

  defp extract_domain(_), do: "unknown"

  defp validation_breakdown_by_source(course_id) do
    rows =
      from(q in Question,
        where: q.course_id == ^course_id,
        group_by: [q.source_type, q.validation_status],
        select: {q.source_type, q.validation_status, count(q.id)}
      )
      |> Repo.all()

    rows
    |> Enum.group_by(fn {source_type, _, _} -> source_type end)
    |> Enum.map(fn {source_type, entries} ->
      by_status = Map.new(entries, fn {_, status, count} -> {status, count} end)

      %{
        source_type: source_type || :unknown,
        total: Map.values(by_status) |> Enum.sum(),
        passed: Map.get(by_status, :passed, 0),
        review: Map.get(by_status, :needs_review, 0),
        failed: Map.get(by_status, :failed, 0),
        pending: Map.get(by_status, :pending, 0)
      }
    end)
    |> Enum.sort_by(& &1.total, :desc)
  end

  # --- Helpers ---

  defp pass_rate(0, _), do: 0
  defp pass_rate(_, 0), do: 0
  defp pass_rate(passed, total), do: Float.round(passed / total * 100, 1)

  defp pass_rate_class(passed, total) do
    rate = pass_rate(passed, total)

    cond do
      rate >= 80 -> "text-green-700 font-medium"
      rate >= 50 -> "text-yellow-700"
      true -> "text-red-700"
    end
  end

  defp source_badge_class(:web_scraped),
    do: "inline-block px-2 py-0.5 rounded-full text-xs bg-blue-50 text-blue-700"

  defp source_badge_class(:ai_generated),
    do: "inline-block px-2 py-0.5 rounded-full text-xs bg-purple-50 text-purple-700"

  defp source_badge_class(:user_uploaded),
    do: "inline-block px-2 py-0.5 rounded-full text-xs bg-green-50 text-green-700"

  defp source_badge_class(_),
    do: "inline-block px-2 py-0.5 rounded-full text-xs bg-gray-100 text-gray-600"

  defp volume_note(sources, passed) do
    cond do
      sources == 0 -> "❌ No sources discovered"
      sources < 500 -> "⚠️  #{sources} sources — target ≥ 2,000 after Phase 1"
      passed < 1000 -> "⚠️  #{passed} passed questions — target ≥ 1,000 after Phase 2"
      passed < 5000 -> "🟡 #{passed} passed — target ≥ 5,000 after Phase 3"
      true -> "✅ #{passed} passed questions"
    end
  end
end
