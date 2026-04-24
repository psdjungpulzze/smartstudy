defmodule FunSheepWeb.MemorySpanLive do
  @moduledoc """
  LiveView for the memory span breakdown page.

  Shows a student how long they retain material for each chapter in a course,
  with color coding and trend arrows. Chapters are sorted shortest-span-first
  so the most at-risk topics appear at the top.

  Route: /courses/:course_id/memory-span
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Courses, MemorySpan}

  @impl true
  def mount(%{"course_id" => course_id}, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]

    course = Courses.get_course_with_chapters!(course_id)
    course_span = MemorySpan.get_course_span(user_role_id, course_id)
    chapter_spans = MemorySpan.list_chapter_spans(user_role_id, course_id)

    # Build a lookup map: chapter_id → span
    span_by_chapter =
      Map.new(chapter_spans, fn s -> {s.chapter_id, s} end)

    # Merge course chapters with their spans (preserving position order for the
    # chapter list, but list_chapter_spans already sorts by span_hours asc for
    # the at-risk view)
    {:ok,
     assign(socket,
       page_title: "Memory Span: #{course.name}",
       course: course,
       course_id: course_id,
       course_span: course_span,
       chapter_spans: chapter_spans,
       span_by_chapter: span_by_chapter
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto space-y-4 sm:space-y-6">
      <%!-- ── Header ── --%>
      <div class="flex items-center gap-3">
        <.link
          navigate={~p"/courses/#{@course_id}/practice"}
          class="text-gray-400 hover:text-gray-600 transition-colors"
        >
          <.icon name="hero-arrow-left" class="w-5 h-5" />
        </.link>
        <div>
          <p class="text-xs font-bold text-gray-400 uppercase tracking-wider">{@course.name}</p>
          <h1 class="text-xl font-extrabold text-gray-900">🧠 Memory Span</h1>
        </div>
      </div>

      <%!-- ── Course-level span card ── --%>
      <.course_span_card course_span={@course_span} course={@course} course_id={@course_id} />

      <%!-- ── Chapter breakdown ── --%>
      <div>
        <h2 class="text-sm font-extrabold text-gray-400 uppercase tracking-wider mb-3">
          By Chapter
        </h2>

        <div
          :if={@chapter_spans == []}
          class="bg-white rounded-2xl border border-gray-100 p-6 text-center"
        >
          <p class="text-gray-500 text-sm">
            No data yet — start practicing to unlock your memory span breakdown!
          </p>
        </div>

        <div :if={@chapter_spans != []} class="space-y-2">
          <.chapter_row
            :for={span <- @chapter_spans}
            span={span}
            course_id={@course_id}
          />
        </div>

        <%!-- Chapters with no span data yet --%>
        <% chapters_with_data_ids = MapSet.new(@chapter_spans, & &1.chapter_id) %>
        <div
          :if={Enum.any?(@course.chapters, fn c -> c.id not in chapters_with_data_ids end)}
          class="mt-2 space-y-2"
        >
          <.chapter_row_no_data
            :for={
              chapter <- Enum.reject(@course.chapters, fn c -> c.id in chapters_with_data_ids end)
            }
            chapter={chapter}
            course_id={@course_id}
          />
        </div>
      </div>
    </div>
    """
  end

  # ── Course-level span card ──────────────────────────────────────────────────

  attr :course_span, :any, required: true
  attr :course, :any, required: true
  attr :course_id, :string, required: true

  defp course_span_card(%{course_span: nil} = assigns) do
    ~H"""
    <div class="rounded-2xl bg-white shadow-sm border border-[#E5E5EA] p-6">
      <div class="flex items-center gap-3 mb-3">
        <div class="w-10 h-10 rounded-xl bg-gray-100 flex items-center justify-center text-xl">
          🧠
        </div>
        <div>
          <h2 class="font-bold text-gray-900">Overall Memory Span</h2>
          <p class="text-xs text-gray-400">{@course.name}</p>
        </div>
      </div>
      <p class="text-sm text-gray-500">
        Keep practicing to unlock your overall memory span!
      </p>
    </div>
    """
  end

  defp course_span_card(assigns) do
    span = assigns.course_span
    {_label, description} = MemorySpan.span_label(span.span_hours)
    color = MemorySpan.span_color(span.span_hours)
    formatted = MemorySpan.format_span(span.span_hours)
    trend_arrow = trend_arrow(span.trend)
    trend_delta = trend_delta(span)

    assigns =
      assigns
      |> assign(:description, description)
      |> assign(:color, color)
      |> assign(:formatted, formatted)
      |> assign(:trend_arrow, trend_arrow)
      |> assign(:trend_delta, trend_delta)

    ~H"""
    <div class="rounded-2xl bg-white shadow-sm border border-[#E5E5EA] p-6">
      <div class="flex items-center gap-3 mb-4">
        <div class="w-10 h-10 rounded-xl bg-gray-100 flex items-center justify-center text-xl">
          🧠
        </div>
        <div class="flex-1 min-w-0">
          <h2 class="font-bold text-gray-900">Memory Span</h2>
          <p class="text-xs text-gray-400">{@course.name}</p>
        </div>
      </div>

      <div class="flex items-center gap-3 mb-3">
        <span class={[
          "text-2xl font-extrabold",
          span_text_color(@color)
        ]}>
          {@formatted}
        </span>
        <span
          :if={@trend_arrow}
          class={[
            "text-sm font-bold",
            trend_color(@course_span.trend)
          ]}
        >
          {@trend_arrow} {@trend_delta}
        </span>
        <span class={[
          "text-xs font-bold px-2 py-1 rounded-full",
          span_badge_class(@color)
        ]}>
          {span_badge_label(@color)}
        </span>
      </div>

      <p class="text-sm text-gray-600 mb-4">{@description}</p>

      <.link
        navigate={~p"/courses/#{@course_id}/practice"}
        class="inline-flex items-center gap-1.5 text-sm font-semibold text-[#4CD964] hover:text-[#3DBF55] transition-colors"
      >
        Practice now <.icon name="hero-arrow-right" class="w-4 h-4" />
      </.link>
    </div>
    """
  end

  # ── Chapter row with span data ──────────────────────────────────────────────

  attr :span, :any, required: true
  attr :course_id, :string, required: true

  defp chapter_row(assigns) do
    span = assigns.span
    color = MemorySpan.span_color(span.span_hours)
    formatted = MemorySpan.format_span(span.span_hours)
    trend_arrow = trend_arrow(span.trend)
    chapter_name = if span.chapter, do: span.chapter.name, else: "Unknown Chapter"

    assigns =
      assigns
      |> assign(:color, color)
      |> assign(:formatted, formatted)
      |> assign(:trend_arrow, trend_arrow)
      |> assign(:chapter_name, chapter_name)

    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-4 flex items-center gap-3">
      <div class={[
        "w-3 h-3 rounded-full shrink-0",
        span_dot_class(@color)
      ]} />
      <div class="flex-1 min-w-0">
        <p class="font-semibold text-gray-900 text-sm truncate">{@chapter_name}</p>
      </div>
      <div class="flex items-center gap-2 shrink-0">
        <span class={["text-sm font-bold", span_text_color(@color)]}>
          {@formatted}
        </span>
        <span :if={@trend_arrow} class={["text-sm", trend_color(@span.trend)]}>
          {@trend_arrow} {trend_label(@span.trend)}
        </span>
      </div>
      <.link
        navigate={~p"/courses/#{@course_id}/practice"}
        class="text-xs font-semibold text-[#4CD964] hover:text-[#3DBF55] transition-colors shrink-0 ml-1"
      >
        Practice →
      </.link>
    </div>
    """
  end

  # ── Chapter row with no span data ──────────────────────────────────────────

  attr :chapter, :any, required: true
  attr :course_id, :string, required: true

  defp chapter_row_no_data(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-4 flex items-center gap-3 opacity-60">
      <div class="w-3 h-3 rounded-full bg-gray-300 shrink-0" />
      <div class="flex-1 min-w-0">
        <p class="font-semibold text-gray-500 text-sm truncate">{@chapter.name}</p>
      </div>
      <span class="text-xs text-gray-400 shrink-0">No data yet</span>
      <.link
        navigate={~p"/courses/#{@course_id}/practice"}
        class="text-xs font-semibold text-[#4CD964] hover:text-[#3DBF55] transition-colors shrink-0 ml-1"
      >
        Start practicing →
      </.link>
    </div>
    """
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  defp trend_arrow("improving"), do: "↑"
  defp trend_arrow("declining"), do: "↓"
  defp trend_arrow("stable"), do: "→"
  defp trend_arrow(_), do: nil

  defp trend_label("improving"), do: "improving"
  defp trend_label("declining"), do: "declining"
  defp trend_label("stable"), do: "stable"
  defp trend_label(_), do: ""

  defp trend_color("improving"), do: "text-[#4CD964]"
  defp trend_color("declining"), do: "text-red-500"
  defp trend_color("stable"), do: "text-gray-400"
  defp trend_color(_), do: "text-gray-400"

  defp trend_delta(%{span_hours: new, previous_span_hours: old})
       when is_integer(new) and is_integer(old) do
    diff_days = div(abs(new - old), 24)
    if diff_days > 0, do: "(#{diff_days}d)", else: ""
  end

  defp trend_delta(_), do: ""

  defp span_text_color("green"), do: "text-[#4CD964]"
  defp span_text_color("yellow"), do: "text-amber-500"
  defp span_text_color("red"), do: "text-red-500"
  defp span_text_color(_), do: "text-gray-400"

  defp span_dot_class("green"), do: "bg-[#4CD964]"
  defp span_dot_class("yellow"), do: "bg-amber-400"
  defp span_dot_class("red"), do: "bg-red-500"
  defp span_dot_class(_), do: "bg-gray-300"

  defp span_badge_class("green"), do: "bg-green-100 text-[#4CD964]"
  defp span_badge_class("yellow"), do: "bg-amber-100 text-amber-600"
  defp span_badge_class("red"), do: "bg-red-100 text-red-600"
  defp span_badge_class(_), do: "bg-gray-100 text-gray-500"

  defp span_badge_label("green"), do: "Strong"
  defp span_badge_label("yellow"), do: "Moderate"
  defp span_badge_label("red"), do: "At risk"
  defp span_badge_label(_), do: "No data"
end
