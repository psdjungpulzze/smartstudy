defmodule FunSheepWeb.AdminAuditLogLive do
  @moduledoc """
  Read-only feed of admin audit log entries. Every privileged action performed
  through an admin surface (UI, mix task) writes a row here.
  """
  use FunSheepWeb, :live_view

  alias FunSheep.Admin

  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Audit log · Admin")
     |> assign(:page, 0)
     |> load_logs()}
  end

  @impl true
  def handle_event("prev_page", _, socket) do
    {:noreply,
     socket
     |> assign(:page, max(socket.assigns.page - 1, 0))
     |> load_logs()}
  end

  def handle_event("next_page", _, socket) do
    next = socket.assigns.page + 1

    if next * @page_size >= socket.assigns.total do
      {:noreply, socket}
    else
      {:noreply, socket |> assign(:page, next) |> load_logs()}
    end
  end

  defp load_logs(socket) do
    opts = [
      limit: @page_size,
      offset: socket.assigns.page * @page_size
    ]

    logs = Admin.list_audit_logs(opts)
    total = Admin.count_audit_logs()

    socket
    |> assign(:logs, logs)
    |> assign(:total, total)
    |> assign(:page_size, @page_size)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-6xl mx-auto">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-[#1C1C1E]">Audit log</h1>
        <div class="text-sm text-[#8E8E93]">{@total} entries</div>
      </div>

      <div class="bg-white rounded-2xl shadow-md overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-[#F5F5F7] text-[#8E8E93] uppercase text-xs">
            <tr>
              <th class="text-left px-4 py-3">When</th>
              <th class="text-left px-4 py-3">Actor</th>
              <th class="text-left px-4 py-3">Action</th>
              <th class="text-left px-4 py-3">Target</th>
              <th class="text-left px-4 py-3">Details</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={log <- @logs} class="border-t border-[#F5F5F7] align-top">
              <td class="px-4 py-3 text-[#8E8E93] whitespace-nowrap">
                {Calendar.strftime(log.inserted_at, "%Y-%m-%d %H:%M:%S")}
              </td>
              <td class="px-4 py-3 font-medium text-[#1C1C1E]">
                {log.actor_label}
              </td>
              <td class="px-4 py-3">
                <code class="px-2 py-0.5 rounded-md bg-[#F5F5F7] text-[#1C1C1E] text-xs">
                  {log.action}
                </code>
              </td>
              <td class="px-4 py-3 text-[#1C1C1E]">
                <div :if={log.target_type} class="text-xs text-[#8E8E93]">
                  {log.target_type}
                </div>
                <div :if={log.target_id}>{log.target_id}</div>
                <div :if={is_nil(log.target_id)} class="text-[#8E8E93]">—</div>
              </td>
              <td class="px-4 py-3 text-[#8E8E93] text-xs">
                <pre :if={log.metadata != %{}} class="whitespace-pre-wrap">{Jason.encode!(log.metadata, pretty: true)}</pre>
                <span :if={log.metadata == %{}}>—</span>
              </td>
            </tr>
            <tr :if={@logs == []}>
              <td colspan="5" class="px-4 py-10 text-center text-[#8E8E93]">
                No entries yet.
              </td>
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
end
