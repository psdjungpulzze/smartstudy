defmodule FunSheepWeb.AdminCoursesLive do
  @moduledoc """
  Admin-wide course browser. Lists courses across every user with owner,
  processing status, and a delete action.
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Admin, Courses, Questions}

  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Courses · Admin")
     |> assign(:search, "")
     |> assign(:page, 0)
     |> load_courses()}
  end

  @impl true
  def handle_event("search", %{"search" => term}, socket) do
    {:noreply,
     socket
     |> assign(:search, term)
     |> assign(:page, 0)
     |> load_courses()}
  end

  def handle_event("prev_page", _, socket) do
    {:noreply,
     socket
     |> assign(:page, max(socket.assigns.page - 1, 0))
     |> load_courses()}
  end

  def handle_event("next_page", _, socket) do
    next = socket.assigns.page + 1

    if next * @page_size >= socket.assigns.total do
      {:noreply, socket}
    else
      {:noreply, socket |> assign(:page, next) |> load_courses()}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    course = Courses.get_course!(id)

    case Admin.delete_course(course, socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Course deleted.")
         |> load_courses()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete course.")}
    end
  end

  def handle_event("requeue_pending", %{"id" => course_id}, socket) do
    {:ok, count} = Questions.requeue_pending_validations(course_id)

    {:noreply,
     socket
     |> put_flash(:info, "Re-enqueued validation for #{count} pending question(s).")
     |> load_courses()}
  end

  # Enqueues the EnrichDiscoveryWorker which:
  #   1. Re-runs AI discovery over the course's OCR'd materials
  #   2. Calls TOCRebase.propose → compare → apply (attempt-safe)
  #   3. Fires per-chapter question generation for any brand-new chapters
  # Use this to recover courses whose TOC got locked in before the rebasing
  # system existed (e.g., stuck at 16 web-discovered chapters when the
  # textbook has 42).
  def handle_event("rediscover_toc", %{"id" => course_id}, socket) do
    case %{course_id: course_id}
         |> FunSheep.Workers.EnrichDiscoveryWorker.new()
         |> Oban.insert() do
      {:ok, _job} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Re-running TOC discovery. Check the course in a minute for updated chapters."
         )
         |> load_courses()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not enqueue rediscovery: #{inspect(reason)}")}
    end
  end

  defp load_courses(socket) do
    opts = [
      search: socket.assigns.search,
      limit: @page_size,
      offset: socket.assigns.page * @page_size
    ]

    courses = Courses.list_courses_for_admin(opts)
    total = Courses.count_courses_for_admin(Keyword.take(opts, [:search]))

    course_ids = Enum.map(courses, & &1.id)
    question_counts = Questions.count_all_by_courses(course_ids)
    pending_counts = Questions.count_pending_by_courses(course_ids)

    socket
    |> assign(:courses, courses)
    |> assign(:question_counts, question_counts)
    |> assign(:pending_counts, pending_counts)
    |> assign(:total, total)
    |> assign(:page_size, @page_size)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-[#1C1C1E]">Courses</h1>
        <div class="text-sm text-[#8E8E93]">{@total} total</div>
      </div>

      <div class="bg-white rounded-2xl shadow-md p-4 mb-4">
        <form phx-change="search">
          <input
            type="text"
            name="search"
            value={@search}
            placeholder="Search by name or subject…"
            phx-debounce="300"
            class="w-full px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] focus:bg-white rounded-full outline-none transition-colors"
          />
        </form>
      </div>

      <div class="bg-white rounded-2xl shadow-md overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-[#F5F5F7] text-[#8E8E93] uppercase text-xs">
            <tr>
              <th class="text-left px-4 py-3">Name</th>
              <th class="text-left px-4 py-3">Subject</th>
              <th class="text-left px-4 py-3">Owner</th>
              <th class="text-left px-4 py-3">Status</th>
              <th class="text-right px-4 py-3">Questions</th>
              <th class="text-right px-4 py-3">Pending</th>
              <th class="text-left px-4 py-3">Created</th>
              <th class="text-right px-4 py-3">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={c <- @courses} class="border-t border-[#F5F5F7]">
              <td class="px-4 py-3 font-medium text-[#1C1C1E]">{c.name}</td>
              <td class="px-4 py-3 text-[#1C1C1E]">{c.subject || "—"}</td>
              <td class="px-4 py-3 text-[#8E8E93]">
                <%= if c.created_by do %>
                  {c.created_by.email}
                <% else %>
                  —
                <% end %>
              </td>
              <td class="px-4 py-3">
                <.status_badge status={c.processing_status} />
              </td>
              <td class="px-4 py-3 text-right text-[#1C1C1E]">
                {Map.get(@question_counts, c.id, 0)}
              </td>
              <td class="px-4 py-3 text-right">
                <.pending_badge count={Map.get(@pending_counts, c.id, 0)} />
              </td>
              <td class="px-4 py-3 text-[#8E8E93]">
                {Calendar.strftime(c.inserted_at, "%Y-%m-%d")}
              </td>
              <td class="px-4 py-3 text-right">
                <.link
                  navigate={~p"/courses/#{c.id}"}
                  class="px-3 py-1 rounded-full text-xs font-medium text-[#1C1C1E] border border-[#E5E5EA] hover:bg-[#F5F5F7] mr-2"
                >
                  View
                </.link>
                <button
                  :if={Map.get(@pending_counts, c.id, 0) > 0}
                  type="button"
                  phx-click="requeue_pending"
                  phx-value-id={c.id}
                  data-confirm={"Re-enqueue validation for #{Map.get(@pending_counts, c.id, 0)} pending question(s) on this course?"}
                  class="px-3 py-1 rounded-full text-xs font-medium text-[#4CD964] border border-[#4CD964]/30 hover:bg-[#E8F8EB] mr-2"
                  title="Re-enqueues validation jobs for every :pending question on this course. Use after an Interactor outage leaves questions stuck."
                >
                  Requeue
                </button>
                <button
                  type="button"
                  phx-click="rediscover_toc"
                  phx-value-id={c.id}
                  data-confirm="Re-run TOC discovery from uploaded textbook? Preserved chapters keep existing questions; new chapters will trigger AI question generation."
                  class="px-3 py-1 rounded-full text-xs font-medium text-[#007AFF] border border-[#007AFF]/30 hover:bg-blue-50 mr-2"
                  title="Enqueues EnrichDiscoveryWorker: re-discovers chapters from OCR'd textbook, rebases TOC non-destructively (attempts preserved), generates questions for any brand-new chapters."
                >
                  Rediscover
                </button>
                <button
                  type="button"
                  phx-click="delete"
                  phx-value-id={c.id}
                  data-confirm="Delete this course and ALL its questions, materials, and tests? This cannot be undone."
                  class="px-3 py-1 rounded-full text-xs font-medium text-[#FF3B30] border border-[#FF3B30]/30 hover:bg-[#FFE5E3]"
                >
                  Delete
                </button>
              </td>
            </tr>
            <tr :if={@courses == []}>
              <td colspan="8" class="px-4 py-10 text-center text-[#8E8E93]">No courses match.</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="mt-4 flex items-center justify-between text-sm text-[#8E8E93]">
        <div>Page {@page + 1} of {max(div(@total - 1, @page_size) + 1, 1)}</div>
        <div class="flex gap-2">
          <button
            type="button"
            phx-click="prev_page"
            disabled={@page == 0}
            class="px-4 py-2 rounded-full border border-[#E5E5EA] bg-white disabled:opacity-40"
          >
            Prev
          </button>
          <button
            type="button"
            phx-click="next_page"
            disabled={(@page + 1) * @page_size >= @total}
            class="px-4 py-2 rounded-full border border-[#E5E5EA] bg-white disabled:opacity-40"
          >
            Next
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :count, :integer, required: true

  # Pill showing pending-validation count. Zero renders as "—" in neutral
  # grey; >0 gets the warning yellow so stuck courses stand out at a glance.
  defp pending_badge(%{count: 0} = assigns) do
    ~H"""
    <span class="text-[#8E8E93]">—</span>
    """
  end

  defp pending_badge(assigns) do
    ~H"""
    <span class="inline-block px-2 py-0.5 rounded-full text-xs font-medium bg-[#FFF4CC] text-[#1C1C1E]">
      {@count}
    </span>
    """
  end

  attr :status, :any, required: true

  defp status_badge(assigns) do
    {label, class} =
      case to_string(assigns.status) do
        "ready" -> {"Ready", "bg-[#E8F8EB] text-[#1C1C1E]"}
        "processing" -> {"Processing", "bg-[#FFF4CC] text-[#1C1C1E]"}
        "failed" -> {"Failed", "bg-[#FFE5E3] text-[#FF3B30]"}
        "" -> {"—", "bg-[#F5F5F7] text-[#8E8E93]"}
        other -> {other, "bg-[#F5F5F7] text-[#1C1C1E]"}
      end

    assigns = assign(assigns, label: label, badge_class: class)

    ~H"""
    <span class={["inline-block px-2 py-0.5 rounded-full text-xs font-medium", @badge_class]}>
      {@label}
    </span>
    """
  end
end
