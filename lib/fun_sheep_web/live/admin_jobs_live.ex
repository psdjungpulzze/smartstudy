defmodule FunSheepWeb.AdminJobsLive do
  @moduledoc """
  /admin/jobs/failures — FunSheep-domain drill-down for failed Oban jobs.

  Oban Web (`/admin/jobs`) shows raw jobs; this page layers FunSheep context
  (course name, material filename, error category) on top so admins can
  triage without chasing IDs through the console.
  """
  use FunSheepWeb, :live_view

  alias FunSheep.Admin.Jobs

  @page_size 50

  @categories [
    {:interactor_unavailable, "Interactor down"},
    {:ocr_failed, "OCR failed"},
    {:validation_rejected, "Validation rejected"},
    {:rate_limited, "Rate limited"},
    {:timeout, "Timeout"},
    {:other, "Other"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Job failures · Admin")
     |> assign(:page, 0)
     |> assign(:worker_filter, nil)
     |> assign(:category_filter, nil)
     |> assign(:drawer_row, nil)
     |> load_data()}
  end

  @impl true
  def handle_event("filter_worker", %{"worker" => worker}, socket) do
    worker = if worker == "", do: nil, else: worker

    {:noreply,
     socket
     |> assign(:worker_filter, worker)
     |> assign(:page, 0)
     |> load_data()}
  end

  def handle_event("filter_category", %{"category" => cat}, socket) do
    category = if cat == "", do: nil, else: String.to_existing_atom(cat)

    {:noreply,
     socket
     |> assign(:category_filter, category)
     |> assign(:page, 0)
     |> load_data()}
  end

  def handle_event("prev_page", _, socket) do
    {:noreply, socket |> assign(:page, max(socket.assigns.page - 1, 0)) |> load_data()}
  end

  def handle_event("next_page", _, socket) do
    next = socket.assigns.page + 1

    if next * @page_size >= socket.assigns.total do
      {:noreply, socket}
    else
      {:noreply, socket |> assign(:page, next) |> load_data()}
    end
  end

  def handle_event("retry", %{"id" => id}, socket) do
    case Jobs.retry_job(id, socket.assigns.current_user) do
      :ok ->
        {:noreply, socket |> put_flash(:info, "Job re-queued.") |> load_data()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to retry: #{inspect(reason)}")}
    end
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    case Jobs.cancel_job(id, socket.assigns.current_user) do
      :ok ->
        {:noreply, socket |> put_flash(:info, "Job cancelled.") |> load_data()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel: #{inspect(reason)}")}
    end
  end

  def handle_event("open_drawer", %{"id" => id}, socket) do
    {:noreply, assign(socket, :drawer_row, Jobs.get_failed_job!(id))}
  end

  def handle_event("close_drawer", _, socket) do
    {:noreply, assign(socket, :drawer_row, nil)}
  end

  defp load_data(socket) do
    filters =
      %{}
      |> maybe_put(:worker, socket.assigns.worker_filter)
      |> maybe_put(:category, socket.assigns.category_filter)

    offset = socket.assigns.page * @page_size

    rows = Jobs.list_failed(filters, limit: @page_size, offset: offset)

    # Category filter has to happen post-hoc since it's derived from job.errors.
    filtered_rows =
      case socket.assigns.category_filter do
        nil -> rows
        cat -> Enum.filter(rows, &(&1.category == cat))
      end

    total = Jobs.count_filtered(filters)
    failures_24h = Jobs.count_failures()
    by_worker = Jobs.count_by_worker()
    by_category = Jobs.count_by_category()

    worker_options =
      by_worker
      |> Enum.map(& &1.worker)
      |> Enum.reject(&is_nil/1)

    socket
    |> assign(:rows, filtered_rows)
    |> assign(:total, total)
    |> assign(:page_size, @page_size)
    |> assign(:failures_24h, failures_24h)
    |> assign(:by_worker, by_worker)
    |> assign(:by_category, by_category)
    |> assign(:worker_options, worker_options)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold text-[#1C1C1E]">Job failures</h1>
          <p class="text-[#8E8E93] text-sm mt-1">
            Retryable, discarded, and cancelled Oban jobs with FunSheep context.
          </p>
        </div>
        <.link
          navigate="/admin/jobs"
          class="text-sm text-[#4CD964] font-medium"
        >
          Oban Web →
        </.link>
      </div>

      <.summary_cards
        failures_24h={@failures_24h}
        by_worker={@by_worker}
        by_category={@by_category}
      />

      <.filters
        worker_filter={@worker_filter}
        category_filter={@category_filter}
        worker_options={@worker_options}
      />

      <.failures_table rows={@rows} />

      <.pagination page={@page} page_size={@page_size} total={@total} />

      <.detail_drawer :if={@drawer_row} row={@drawer_row} />
    </div>
    """
  end

  attr :failures_24h, :integer, required: true
  attr :by_worker, :list, required: true
  attr :by_category, :list, required: true

  defp summary_cards(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
      <div class={[
        "bg-white rounded-2xl shadow-md p-5",
        @failures_24h > 0 && "ring-2 ring-[#FF3B30]/30"
      ]}>
        <div class="text-xs uppercase tracking-wide text-[#8E8E93] font-medium">
          Failed last 24h
        </div>
        <div class={[
          "text-3xl font-bold mt-1",
          @failures_24h > 0 && "text-[#FF3B30]",
          @failures_24h == 0 && "text-[#4CD964]"
        ]}>
          {@failures_24h}
        </div>
      </div>

      <div class="bg-white rounded-2xl shadow-md p-5">
        <div class="text-xs uppercase tracking-wide text-[#8E8E93] font-medium">
          Top workers (24h)
        </div>
        <ul :if={@by_worker != []} class="mt-2 space-y-1 text-sm">
          <li :for={row <- @by_worker} class="flex items-center justify-between">
            <code class="text-[#1C1C1E] truncate">{short_worker(row.worker)}</code>
            <span class="text-[#8E8E93] ml-2">{row.count}</span>
          </li>
        </ul>
        <p :if={@by_worker == []} class="text-sm text-[#8E8E93] mt-3">
          No failures in this window.
        </p>
      </div>

      <div class="bg-white rounded-2xl shadow-md p-5">
        <div class="text-xs uppercase tracking-wide text-[#8E8E93] font-medium">
          By category (24h)
        </div>
        <ul :if={@by_category != []} class="mt-2 space-y-1 text-sm">
          <li :for={row <- @by_category} class="flex items-center justify-between">
            <span class="text-[#1C1C1E]">{category_label(row.category)}</span>
            <span class="text-[#8E8E93] ml-2">{row.count}</span>
          </li>
        </ul>
        <p :if={@by_category == []} class="text-sm text-[#8E8E93] mt-3">
          No failures in this window.
        </p>
      </div>
    </div>
    """
  end

  attr :worker_filter, :any, required: true
  attr :category_filter, :any, required: true
  attr :worker_options, :list, required: true

  defp filters(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-4 mb-4 flex items-center gap-4 flex-wrap">
      <form phx-change="filter_worker" class="flex items-center gap-2">
        <label class="text-xs uppercase tracking-wide text-[#8E8E93]">Worker</label>
        <select
          name="worker"
          class="px-3 py-1 text-sm rounded-full bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] outline-none"
        >
          <option value="" selected={is_nil(@worker_filter)}>All</option>
          <option
            :for={w <- @worker_options}
            value={w}
            selected={@worker_filter == w}
          >
            {short_worker(w)}
          </option>
        </select>
      </form>

      <form phx-change="filter_category" class="flex items-center gap-2">
        <label class="text-xs uppercase tracking-wide text-[#8E8E93]">Category</label>
        <select
          name="category"
          class="px-3 py-1 text-sm rounded-full bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] outline-none"
        >
          <option value="" selected={is_nil(@category_filter)}>All</option>
          <option
            :for={{cat, label} <- category_options()}
            value={Atom.to_string(cat)}
            selected={@category_filter == cat}
          >
            {label}
          </option>
        </select>
      </form>
    </div>
    """
  end

  attr :rows, :list, required: true

  defp failures_table(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md overflow-hidden mb-4">
      <div class="overflow-x-auto">
        <table class="w-full text-sm min-w-[720px]">
          <thead class="bg-[#F5F5F7] text-[#8E8E93] uppercase text-xs">
            <tr>
              <th class="text-left px-4 py-3">When</th>
              <th class="text-left px-4 py-3">Worker</th>
              <th class="text-left px-4 py-3">Summary</th>
              <th class="text-left px-4 py-3">Category</th>
              <th class="text-right px-4 py-3">Attempt</th>
              <th class="text-right px-4 py-3">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={row <- @rows}
              class="border-t border-[#F5F5F7] hover:bg-[#F5F5F7] cursor-pointer"
              phx-click="open_drawer"
              phx-value-id={row.job.id}
            >
              <td class="px-4 py-3 text-[#8E8E93] whitespace-nowrap">
                {format_dt(row.job.discarded_at || row.job.attempted_at || row.job.inserted_at)}
              </td>
              <td class="px-4 py-3 font-medium text-[#1C1C1E]">{row.worker_short}</td>
              <td class="px-4 py-3 text-[#1C1C1E] truncate max-w-md">{row.summary}</td>
              <td class="px-4 py-3">
                <.category_badge category={row.category} />
              </td>
              <td class="px-4 py-3 text-right">
                {row.job.attempt}/{row.job.max_attempts}
              </td>
              <td class="px-4 py-3 text-right">
                <div class="inline-flex items-center gap-2" phx-click-away={nil}>
                  <button
                    type="button"
                    phx-click="retry"
                    phx-value-id={row.job.id}
                    data-confirm="Re-queue this job?"
                    class="px-3 py-1 rounded-full text-xs font-medium text-[#4CD964] border border-[#4CD964]/40 hover:bg-[#E8F8EB]"
                  >
                    Retry
                  </button>
                  <button
                    type="button"
                    phx-click="cancel"
                    phx-value-id={row.job.id}
                    data-confirm="Cancel this job? It will be marked discarded."
                    class="px-3 py-1 rounded-full text-xs font-medium text-[#FF3B30] border border-[#FF3B30]/30 hover:bg-[#FFE5E3]"
                  >
                    Cancel
                  </button>
                </div>
              </td>
            </tr>
            <tr :if={@rows == []}>
              <td colspan="6" class="px-4 py-10 text-center text-[#8E8E93]">
                No failed jobs match these filters.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr :page, :integer, required: true
  attr :page_size, :integer, required: true
  attr :total, :integer, required: true

  defp pagination(assigns) do
    ~H"""
    <div class="flex items-center justify-between text-sm text-[#8E8E93]">
      <div>
        Page {@page + 1} of {max(div(@total - 1, @page_size) + 1, 1)} · {@total} total
      </div>
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
    """
  end

  attr :row, :map, required: true

  defp detail_drawer(assigns) do
    ~H"""
    <div
      class="fixed inset-0 bg-black/40 z-40"
      phx-click="close_drawer"
      phx-window-keydown="close_drawer"
      phx-key="Escape"
    >
    </div>
    <aside class="fixed right-0 top-0 bottom-0 w-[520px] bg-white shadow-xl z-50 overflow-y-auto">
      <div class="p-6 space-y-4">
        <div class="flex items-center justify-between">
          <h3 class="font-semibold text-[#1C1C1E]">Job #{@row.job.id}</h3>
          <button
            type="button"
            phx-click="close_drawer"
            aria-label="Close drawer"
            class="w-8 h-8 rounded-lg hover:bg-[#F5F5F7] flex items-center justify-center"
          >
            ✕
          </button>
        </div>

        <dl class="text-sm space-y-2">
          <.detail_row label="Worker" value={@row.job.worker} />
          <.detail_row label="Queue" value={@row.job.queue} />
          <.detail_row label="State" value={@row.job.state} />
          <.detail_row label="Inserted" value={format_dt(@row.job.inserted_at)} />
          <.detail_row
            label="Last attempt"
            value={format_dt(@row.job.attempted_at)}
          />
          <.detail_row label="Attempt" value={"#{@row.job.attempt}/#{@row.job.max_attempts}"} />
          <.detail_row label="Summary" value={@row.summary} />
          <.detail_row label="Category" value={category_label(@row.category)} />
        </dl>

        <div>
          <h4 class="text-xs uppercase tracking-wide text-[#8E8E93] mb-1">Args</h4>
          <pre class="text-xs bg-[#F5F5F7] p-3 rounded-lg whitespace-pre-wrap break-all">{Jason.encode!(@row.job.args, pretty: true)}</pre>
        </div>

        <div :if={@row.job.errors != []}>
          <h4 class="text-xs uppercase tracking-wide text-[#8E8E93] mb-1">Error history</h4>
          <div class="space-y-2">
            <div
              :for={err <- @row.job.errors}
              class="text-xs bg-[#FFE5E3] p-3 rounded-lg text-[#FF3B30] whitespace-pre-wrap break-all"
            >
              <div class="text-[10px] text-[#8E8E93] mb-1">
                attempt {err["attempt"] || err[:attempt] || "?"} · {err["at"] || err[:at] || "?"}
              </div>
              {err["error"] || err[:error] || inspect(err)}
            </div>
          </div>
        </div>
      </div>
    </aside>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp detail_row(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-3">
      <dt class="text-[#8E8E93]">{@label}</dt>
      <dd class="text-[#1C1C1E] text-right break-all">{to_string(@value)}</dd>
    </div>
    """
  end

  attr :category, :atom, required: true

  defp category_badge(%{category: cat} = assigns) do
    {label, class} =
      case cat do
        :interactor_unavailable -> {"Interactor", "bg-[#FFE5E3] text-[#FF3B30]"}
        :ocr_failed -> {"OCR", "bg-[#FFF4CC] text-[#1C1C1E]"}
        :validation_rejected -> {"Validation", "bg-[#FFF4CC] text-[#1C1C1E]"}
        :rate_limited -> {"Rate", "bg-[#E8F8EB] text-[#1C1C1E]"}
        :timeout -> {"Timeout", "bg-[#FFE5E3] text-[#FF3B30]"}
        _ -> {"Other", "bg-[#F5F5F7] text-[#8E8E93]"}
      end

    assigns = assign(assigns, label: label, badge_class: class)

    ~H"""
    <span class={["inline-block px-2 py-0.5 rounded-full text-xs font-medium", @badge_class]}>
      {@label}
    </span>
    """
  end

  defp category_options, do: @categories

  defp category_label(cat) do
    Enum.find_value(@categories, "Other", fn
      {^cat, label} -> label
      _ -> nil
    end)
  end

  defp short_worker(nil), do: "—"
  defp short_worker(worker) when is_binary(worker), do: worker |> String.split(".") |> List.last()

  defp format_dt(nil), do: "—"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp format_dt(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%Y-%m-%d %H:%M:%S")
  defp format_dt(_), do: "—"
end
