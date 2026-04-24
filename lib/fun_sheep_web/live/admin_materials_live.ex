defmodule FunSheepWeb.AdminMaterialsLive do
  @moduledoc """
  Admin view of uploaded materials across every user. Search by filename,
  filter by OCR status, and per-row actions: re-run OCR, delete.
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Admin, Content}

  @page_size 25
  @statuses ~w(pending processing completed partial failed)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Materials · Admin")
     |> assign(:search, "")
     |> assign(:status_filter, nil)
     |> assign(:page, 0)
     |> load_materials()}
  end

  @impl true
  def handle_event("search", %{"search" => term}, socket) do
    {:noreply,
     socket
     |> assign(:search, term)
     |> assign(:page, 0)
     |> load_materials()}
  end

  def handle_event("filter_status", %{"status" => status}, socket) do
    status = if status in @statuses, do: status, else: nil

    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> assign(:page, 0)
     |> load_materials()}
  end

  def handle_event("prev_page", _, socket) do
    {:noreply,
     socket
     |> assign(:page, max(socket.assigns.page - 1, 0))
     |> load_materials()}
  end

  def handle_event("next_page", _, socket) do
    next = socket.assigns.page + 1

    if next * @page_size >= socket.assigns.total do
      {:noreply, socket}
    else
      {:noreply, socket |> assign(:page, next) |> load_materials()}
    end
  end

  def handle_event("rerun", %{"id" => id}, socket) do
    material = Content.get_uploaded_material!(id)

    case Admin.rerun_ocr(material, socket.assigns.current_user) do
      {:ok, _job} ->
        {:noreply,
         socket
         |> put_flash(:info, "OCR re-run queued for #{material.file_name}.")
         |> load_materials()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to enqueue OCR re-run.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    material = Content.get_uploaded_material!(id)

    case Admin.delete_material(material, socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Material deleted.") |> load_materials()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete material.")}
    end
  end

  defp load_materials(socket) do
    opts = [
      search: socket.assigns.search,
      status: socket.assigns.status_filter,
      limit: @page_size,
      offset: socket.assigns.page * @page_size
    ]

    materials = Content.list_materials_for_admin(opts)
    total = Content.count_materials_for_admin(Keyword.take(opts, [:search, :status]))

    socket
    |> assign(:materials, materials)
    |> assign(:total, total)
    |> assign(:page_size, @page_size)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-[#1C1C1E]">Materials</h1>
        <div class="text-sm text-[#8E8E93]">{@total} total</div>
      </div>

      <div class="bg-white rounded-2xl shadow-md p-4 mb-4">
        <form phx-change="search">
          <input
            type="text"
            name="search"
            value={@search}
            placeholder="Search by filename…"
            phx-debounce="300"
            class="w-full px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] focus:bg-white rounded-full outline-none transition-colors"
          />
        </form>

        <div class="mt-3 flex items-center gap-2 flex-wrap">
          <button
            type="button"
            phx-click="filter_status"
            phx-value-status=""
            class={pill_class(is_nil(@status_filter))}
          >
            All
          </button>
          <button
            :for={s <- ~w(pending processing completed partial failed)}
            type="button"
            phx-click="filter_status"
            phx-value-status={s}
            class={pill_class(@status_filter == s)}
          >
            {String.capitalize(s)}
          </button>
        </div>
      </div>

      <div class="bg-white rounded-2xl shadow-md overflow-hidden">
        <div class="overflow-x-auto">
          <table class="w-full text-sm min-w-[720px]">
            <thead class="bg-[#F5F5F7] text-[#8E8E93] uppercase text-xs">
              <tr>
                <th class="text-left px-4 py-3">File</th>
                <th class="text-left px-4 py-3">Uploaded by</th>
                <th class="text-left px-4 py-3">Course</th>
                <th class="text-left px-4 py-3">OCR</th>
                <th class="text-left px-4 py-3">Uploaded</th>
                <th class="text-right px-4 py-3">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={m <- @materials} class="border-t border-[#F5F5F7]">
                <td class="px-4 py-3 font-medium text-[#1C1C1E]">
                  {m.file_name}
                  <div :if={m.ocr_error} class="text-xs text-[#FF3B30] mt-0.5">
                    {String.slice(m.ocr_error, 0, 120)}
                  </div>
                </td>
                <td class="px-4 py-3 text-[#8E8E93]">
                  <%= if m.user_role do %>
                    {m.user_role.email}
                  <% else %>
                    —
                  <% end %>
                </td>
                <td class="px-4 py-3 text-[#1C1C1E]">
                  <%= if m.course do %>
                    <.link
                      navigate={~p"/courses/#{m.course_id}"}
                      class="text-[#4CD964] hover:text-[#3DBF55]"
                    >
                      {m.course.name}
                    </.link>
                  <% else %>
                    <span class="text-[#8E8E93]">—</span>
                  <% end %>
                </td>
                <td class="px-4 py-3"><.status_badge status={m.ocr_status} /></td>
                <td class="px-4 py-3 text-[#8E8E93] whitespace-nowrap">
                  {Calendar.strftime(m.inserted_at, "%Y-%m-%d")}
                </td>
                <td class="px-4 py-3 text-right">
                  <button
                    type="button"
                    phx-click="rerun"
                    phx-value-id={m.id}
                    class="px-3 py-1 rounded-full text-xs font-medium text-[#1C1C1E] border border-[#E5E5EA] hover:bg-[#F5F5F7] mr-2"
                  >
                    Re-run OCR
                  </button>
                  <button
                    type="button"
                    phx-click="delete"
                    phx-value-id={m.id}
                    data-confirm="Delete this material and its OCR output? Cannot be undone."
                    class="px-3 py-1 rounded-full text-xs font-medium text-[#FF3B30] border border-[#FF3B30]/30 hover:bg-[#FFE5E3]"
                  >
                    Delete
                  </button>
                </td>
              </tr>
              <tr :if={@materials == []}>
                <td colspan="6" class="px-4 py-10 text-center text-[#8E8E93]">
                  No materials match.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
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

  defp pill_class(active?) do
    base = "px-3 py-1 rounded-full text-xs font-medium border transition-colors"

    if active?,
      do: "#{base} bg-[#4CD964] text-white border-[#4CD964]",
      else: "#{base} bg-white text-[#1C1C1E] border-[#E5E5EA] hover:border-[#4CD964]/40"
  end

  attr :status, :atom, required: true

  defp status_badge(assigns) do
    {label, class} =
      case assigns.status do
        :completed -> {"Completed", "bg-[#E8F8EB] text-[#1C1C1E]"}
        :processing -> {"Processing", "bg-[#FFF4CC] text-[#1C1C1E]"}
        :partial -> {"Partial", "bg-[#FFF4CC] text-[#1C1C1E]"}
        :failed -> {"Failed", "bg-[#FFE5E3] text-[#FF3B30]"}
        :pending -> {"Pending", "bg-[#F5F5F7] text-[#1C1C1E]"}
        other -> {to_string(other), "bg-[#F5F5F7] text-[#1C1C1E]"}
      end

    assigns = assign(assigns, label: label, badge_class: class)

    ~H"""
    <span class={["inline-block px-2 py-0.5 rounded-full text-xs font-medium", @badge_class]}>
      {@label}
    </span>
    """
  end
end
