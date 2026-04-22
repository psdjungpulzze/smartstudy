defmodule FunSheepWeb.AdminAIUsageLive do
  @moduledoc """
  Admin AI usage dashboard: "where is the OpenAI bill going?"

  All data comes from the local `ai_calls` table — no Interactor calls made
  at page load. Filter state persists in URL params so admins can share
  links.
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Admin, AIUsage}
  alias FunSheep.AIUsage.Pricing

  @windows %{
    "1h" => 3_600,
    "24h" => 24 * 3_600,
    "7d" => 7 * 24 * 3_600,
    "30d" => 30 * 24 * 3_600
  }

  @default_window "24h"
  @envs ~w(prod staging dev test)
  @providers ~w(openai anthropic google interactor unknown)
  @statuses ~w(ok error timeout)

  @impl true
  def mount(_params, _session, socket) do
    audit_view(socket)

    {:ok,
     socket
     |> assign(:page_title, "AI usage · Admin")
     |> assign(:drawer_call, nil)
     |> assign(:custom_since, nil)
     |> assign(:custom_until, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    window = params["window"] || @default_window

    {custom_since, custom_until} =
      case window do
        "custom" -> {params["since"], params["until"]}
        _ -> {nil, nil}
      end

    env = normalize_multi(params["env"], @envs)
    provider = normalize_multi(params["provider"], @providers)
    status = normalize_multi(params["status"], @statuses)

    socket =
      socket
      |> assign(:window, window)
      |> assign(:custom_since_raw, custom_since)
      |> assign(:custom_until_raw, custom_until)
      |> assign(:env_filter, env)
      |> assign(:provider_filter, provider)
      |> assign(:status_filter, status)

    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("set_window", %{"window" => window}, socket) do
    params = current_params(socket) |> Map.put("window", window) |> Map.drop(["since", "until"])
    {:noreply, push_patch(socket, to: ~p"/admin/usage/ai?#{params}")}
  end

  def handle_event("set_custom_window", %{"since" => since, "until" => until_str}, socket) do
    params =
      current_params(socket)
      |> Map.put("window", "custom")
      |> Map.put("since", since)
      |> Map.put("until", until_str)

    {:noreply, push_patch(socket, to: ~p"/admin/usage/ai?#{params}")}
  end

  def handle_event("toggle_filter", %{"group" => group, "v" => value}, socket) do
    current =
      case group do
        "env" -> socket.assigns.env_filter
        "provider" -> socket.assigns.provider_filter
        "status" -> socket.assigns.status_filter
      end

    next =
      if value in current, do: List.delete(current, value), else: [value | current]

    params =
      current_params(socket)
      |> Map.put(group, Enum.join(next, ","))
      |> cleanup_empty()

    {:noreply, push_patch(socket, to: ~p"/admin/usage/ai?#{params}")}
  end

  def handle_event("clear_filter", %{"group" => group}, socket) do
    params =
      current_params(socket)
      |> Map.put(group, "")
      |> cleanup_empty()

    {:noreply, push_patch(socket, to: ~p"/admin/usage/ai?#{params}")}
  end

  def handle_event("open_drawer", %{"id" => id}, socket) do
    {:noreply, assign(socket, :drawer_call, AIUsage.get_call!(id))}
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, :drawer_call, nil)}
  end

  defp audit_view(socket) do
    Admin.record(%{
      actor_user_role_id: get_in(socket.assigns, [:current_user, "user_role_id"]),
      actor_label: "admin:#{get_in(socket.assigns, [:current_user, "email"]) || "unknown"}",
      action: "admin.usage.ai.view",
      metadata: %{}
    })
  end

  defp load_data(socket) do
    {since, until_dt} = window_to_range(socket)
    filters = build_filters(socket, since, until_dt)
    bucket = pick_bucket(since, until_dt)

    summary = AIUsage.summary_with_delta(filters)

    socket
    |> assign(:since, since)
    |> assign(:until, until_dt)
    |> assign(:filters, filters)
    |> assign(:bucket, bucket)
    |> assign(:summary, summary)
    |> assign(:series, AIUsage.time_series(filters, bucket))
    |> assign(:by_assistant, AIUsage.by_assistant(filters))
    |> assign(:by_source, AIUsage.by_source(filters))
    |> assign(:by_model, AIUsage.by_model(filters))
    |> assign(:recent_errors, AIUsage.recent_errors(filters, 25))
    |> assign(:top_calls, AIUsage.top_calls(filters, 25))
  end

  defp window_to_range(%{
         assigns: %{window: "custom", custom_since_raw: since, custom_until_raw: until_str}
       })
       when is_binary(since) and is_binary(until_str) do
    with {:ok, s} <- parse_naive(since),
         {:ok, u} <- parse_naive(until_str) do
      {s, u}
    else
      _ -> default_range()
    end
  end

  defp window_to_range(%{assigns: %{window: window}}) do
    seconds = Map.get(@windows, window, @windows[@default_window])
    now = DateTime.utc_now()
    {DateTime.add(now, -seconds, :second), now}
  end

  defp default_range do
    now = DateTime.utc_now()
    {DateTime.add(now, -@windows[@default_window], :second), now}
  end

  defp parse_naive(str) do
    # datetime-local gives "2026-04-22T08:00"
    case NaiveDateTime.from_iso8601(str <> ":00") do
      {:ok, ndt} -> {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}
      _ -> :error
    end
  end

  defp build_filters(socket, since, until_dt) do
    %{
      since: since,
      until: until_dt,
      env: socket.assigns.env_filter,
      provider: socket.assigns.provider_filter,
      status: socket.assigns.status_filter
    }
  end

  defp pick_bucket(since, until_dt) do
    span_seconds = DateTime.diff(until_dt, since)

    cond do
      span_seconds <= 24 * 3_600 -> :hour
      span_seconds <= 7 * 24 * 3_600 -> :day
      true -> :week
    end
  end

  defp normalize_multi(nil, _allowed), do: []
  defp normalize_multi("", _allowed), do: []

  defp normalize_multi(s, allowed) when is_binary(s) do
    s
    |> String.split(",", trim: true)
    |> Enum.filter(&(&1 in allowed))
    |> Enum.uniq()
  end

  defp current_params(socket) do
    %{
      "window" => socket.assigns.window,
      "env" => Enum.join(socket.assigns.env_filter, ","),
      "provider" => Enum.join(socket.assigns.provider_filter, ","),
      "status" => Enum.join(socket.assigns.status_filter, ",")
    }
    |> cleanup_empty()
    |> maybe_add_custom(socket)
  end

  defp maybe_add_custom(params, %{assigns: %{window: "custom"}} = socket) do
    params
    |> put_if_present("since", socket.assigns.custom_since_raw)
    |> put_if_present("until", socket.assigns.custom_until_raw)
  end

  defp maybe_add_custom(params, _), do: params

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, _key, ""), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  defp cleanup_empty(params) do
    params
    |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
    |> Enum.into(%{})
  end

  ## --- Render -----------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <div class="mb-6">
        <h1 class="text-2xl font-bold text-[#1C1C1E]">AI usage</h1>
        <p class="text-[#8E8E93] text-sm mt-1">
          Per-model / per-assistant / per-source token usage, cost estimates, and error rates.
        </p>
      </div>

      <.window_picker
        window={@window}
        custom_since={@custom_since_raw}
        custom_until={@custom_until_raw}
      />

      <.filter_chips
        env_filter={@env_filter}
        provider_filter={@provider_filter}
        status_filter={@status_filter}
      />

      <.summary_cards summary={@summary} />

      <.chart_section series={@series} bucket={@bucket} />

      <.group_tables
        by_assistant={@by_assistant}
        by_source={@by_source}
        by_model={@by_model}
      />

      <.errors_section recent_errors={@recent_errors} />

      <.top_calls_section top_calls={@top_calls} />

      <.detail_drawer :if={@drawer_call} call={@drawer_call} />
    </div>
    """
  end

  ## --- Function components ----------------------------------------------

  attr :window, :string, required: true
  attr :custom_since, :string, default: nil
  attr :custom_until, :string, default: nil

  defp window_picker(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-4 mb-4 sticky top-0 z-10">
      <div class="flex items-center flex-wrap gap-2">
        <span class="text-xs uppercase tracking-wide text-[#8E8E93] mr-2">Window</span>
        <button
          :for={w <- ~w(1h 24h 7d 30d)}
          type="button"
          phx-click="set_window"
          phx-value-window={w}
          class={window_pill_class(@window == w)}
        >
          {w}
        </button>

        <form
          phx-submit="set_custom_window"
          class="flex flex-wrap items-center gap-2 ml-2"
        >
          <input
            type="datetime-local"
            name="since"
            value={@custom_since}
            class="px-3 py-1 text-xs rounded-full bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] outline-none"
          />
          <span class="text-[#8E8E93] text-xs">→</span>
          <input
            type="datetime-local"
            name="until"
            value={@custom_until}
            class="px-3 py-1 text-xs rounded-full bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] outline-none"
          />
          <button
            type="submit"
            class={window_pill_class(@window == "custom")}
          >
            Custom
          </button>
        </form>
      </div>
    </div>
    """
  end

  attr :env_filter, :list, required: true
  attr :provider_filter, :list, required: true
  attr :status_filter, :list, required: true

  defp filter_chips(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-4 mb-6 space-y-2">
      <.chip_group label="Env" group="env" values={~w(prod staging dev test)} selected={@env_filter} />
      <.chip_group
        label="Provider"
        group="provider"
        values={~w(openai anthropic google interactor unknown)}
        selected={@provider_filter}
      />
      <.chip_group
        label="Status"
        group="status"
        values={~w(ok error timeout)}
        selected={@status_filter}
      />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :group, :string, required: true
  attr :values, :list, required: true
  attr :selected, :list, required: true

  defp chip_group(assigns) do
    ~H"""
    <div class="flex items-center flex-wrap gap-2">
      <span class="text-xs uppercase tracking-wide text-[#8E8E93] w-20">{@label}</span>
      <button
        type="button"
        phx-click="clear_filter"
        phx-value-group={@group}
        class={window_pill_class(@selected == [])}
      >
        All
      </button>
      <button
        :for={v <- @values}
        type="button"
        phx-click="toggle_filter"
        phx-value-group={@group}
        phx-value-v={v}
        class={window_pill_class(v in @selected)}
      >
        {v}
      </button>
    </div>
    """
  end

  attr :summary, :map, required: true

  defp summary_cards(assigns) do
    ~H"""
    <div class="grid grid-cols-2 md:grid-cols-5 gap-4 mb-6">
      <.metric_card
        label="Total calls"
        value={format_int(@summary.calls)}
        delta={@summary.calls_delta_pct}
      />
      <.metric_card
        label="Total tokens"
        value={format_int(@summary.total_tokens)}
        delta={@summary.tokens_delta_pct}
      />
      <.metric_card
        label="Est. cost"
        value={Pricing.format_cost_cents(@summary.est_cost_cents)}
        delta={@summary.cost_delta_pct}
      />
      <.metric_card
        label="Error rate"
        value={format_error_rate(@summary.errors, @summary.calls)}
        delta={@summary.errors_delta_pct}
        warn={error_rate_high?(@summary.errors, @summary.calls)}
      />
      <.metric_card
        label="Latency p50 / p95"
        value={format_latency(@summary.p50_ms, @summary.p95_ms)}
      />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :delta, :any, default: nil
  attr :warn, :boolean, default: false

  defp metric_card(assigns) do
    ~H"""
    <div class={[
      "bg-white rounded-2xl shadow-md p-5",
      @warn && "ring-2 ring-[#FF3B30]/40"
    ]}>
      <div class="text-xs uppercase tracking-wide text-[#8E8E93] font-medium">{@label}</div>
      <div class={["text-2xl font-bold mt-1", @warn && "text-[#FF3B30]"]}>{@value}</div>
      <div :if={@delta} class="text-xs mt-2">
        <span class={delta_class(@delta)}>{format_delta(@delta)}</span>
        <span class="text-[#8E8E93]"> vs prior</span>
      </div>
    </div>
    """
  end

  attr :series, :list, required: true
  attr :bucket, :atom, required: true

  defp chart_section(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-5 mb-6">
      <div class="flex items-center justify-between mb-3">
        <h2 class="font-semibold text-[#1C1C1E]">Token volume</h2>
        <span class="text-xs text-[#8E8E93]">
          Bucketed by {@bucket}. Blue = prompt, green = completion.
        </span>
      </div>
      <.token_chart series={@series} />
    </div>
    """
  end

  attr :series, :list, required: true

  defp token_chart(assigns) do
    max_total =
      assigns.series
      |> Enum.map(&((&1.prompt_tokens || 0) + (&1.completion_tokens || 0)))
      |> Enum.max(fn -> 0 end)
      |> max(1)

    bars =
      assigns.series
      |> Enum.with_index()
      |> Enum.map(fn {row, i} ->
        prompt = row.prompt_tokens || 0
        completion = row.completion_tokens || 0
        total = prompt + completion
        prompt_h = round(prompt / max_total * 200)
        completion_h = round(completion / max_total * 200)

        %{
          index: i,
          bucket_at: row.bucket_at,
          prompt: prompt,
          completion: completion,
          total: total,
          prompt_h: prompt_h,
          completion_h: completion_h
        }
      end)

    count = length(bars)
    bar_width = if count > 0, do: max(div(800, max(count, 1)) - 2, 4), else: 4

    assigns =
      assign(assigns, bars: bars, count: count, bar_width: bar_width, max_total: max_total)

    ~H"""
    <svg
      viewBox="0 0 800 240"
      width="100%"
      height="240"
      preserveAspectRatio="none"
      class="bg-[#F5F5F7] rounded-xl"
    >
      <g :for={bar <- @bars} transform={"translate(#{bar.index * (800 / max(@count, 1))}, 0)"}>
        <rect
          x="0"
          y={220 - bar.prompt_h - bar.completion_h}
          width={@bar_width}
          height={bar.prompt_h}
          fill="#007AFF"
          opacity="0.85"
        >
          <title>{format_bucket(bar.bucket_at)} — prompt {format_int(bar.prompt)} tokens</title>
        </rect>
        <rect
          x="0"
          y={220 - bar.completion_h}
          width={@bar_width}
          height={bar.completion_h}
          fill="#4CD964"
          opacity="0.85"
        >
          <title>
            {format_bucket(bar.bucket_at)} — completion {format_int(bar.completion)} tokens
          </title>
        </rect>
      </g>
      <line x1="0" y1="220" x2="800" y2="220" stroke="#E5E5EA" stroke-width="1" />
      <text x="6" y="14" class="text-[10px]" fill="#8E8E93" font-size="10">
        max {format_int(@max_total)} tokens / bucket
      </text>
    </svg>
    <p :if={@bars == []} class="text-sm text-[#8E8E93] text-center py-6">
      No calls in this window.
    </p>
    """
  end

  attr :by_assistant, :list, required: true
  attr :by_source, :list, required: true
  attr :by_model, :list, required: true

  defp group_tables(assigns) do
    ~H"""
    <div class="grid grid-cols-1 gap-6 mb-6">
      <.group_table
        title="By assistant"
        rows={@by_assistant}
        empty="No calls tagged with an assistant."
      />
      <.group_table title="By source" rows={@by_source} empty="No calls tagged with a source." />
      <.group_table title="By model" rows={@by_model} empty="No calls with a resolved model." />
    </div>
    """
  end

  attr :title, :string, required: true
  attr :rows, :list, required: true
  attr :empty, :string, required: true

  defp group_table(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md overflow-hidden">
      <h2 class="font-semibold text-[#1C1C1E] px-5 py-4">{@title}</h2>
      <div class="overflow-x-auto">
        <table class="w-full text-sm min-w-[640px]">
          <thead class="bg-[#F5F5F7] text-[#8E8E93] uppercase text-xs">
            <tr>
              <th class="text-left px-4 py-3">Key</th>
              <th class="text-right px-4 py-3">Calls</th>
              <th class="text-right px-4 py-3">Prompt</th>
              <th class="text-right px-4 py-3">Completion</th>
              <th class="text-right px-4 py-3">Total</th>
              <th class="text-right px-4 py-3">Est. cost</th>
              <th class="text-right px-4 py-3">Avg ms</th>
              <th class="text-right px-4 py-3">p95 ms</th>
              <th class="text-right px-4 py-3">Errors</th>
              <th class="text-left px-4 py-3">Last seen</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows} class="border-t border-[#F5F5F7]">
              <td class="px-4 py-3 font-medium text-[#1C1C1E]">{row.key || "—"}</td>
              <td class="px-4 py-3 text-right">{format_int(row.calls)}</td>
              <td class="px-4 py-3 text-right">{format_int(row.prompt_tokens)}</td>
              <td class="px-4 py-3 text-right">{format_int(row.completion_tokens)}</td>
              <td class="px-4 py-3 text-right font-medium">{format_int(row.total_tokens)}</td>
              <td class="px-4 py-3 text-right">{Pricing.format_cost_cents(row.est_cost_cents)}</td>
              <td class="px-4 py-3 text-right">{format_ms(row.avg_ms)}</td>
              <td class="px-4 py-3 text-right">{format_ms(row.p95_ms)}</td>
              <td class={[
                "px-4 py-3 text-right",
                row.errors > 0 && "text-[#FF3B30] font-medium"
              ]}>
                {format_int(row.errors)}
              </td>
              <td class="px-4 py-3 text-[#8E8E93]">{format_dt(row.last_seen)}</td>
            </tr>
            <tr :if={@rows == []}>
              <td colspan="10" class="px-4 py-8 text-center text-[#8E8E93]">{@empty}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr :recent_errors, :list, required: true

  defp errors_section(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md overflow-hidden mb-6">
      <h2 class="font-semibold text-[#1C1C1E] px-5 py-4">Recent errors</h2>
      <div class="overflow-x-auto">
        <table class="w-full text-sm min-w-[640px]">
          <thead class="bg-[#F5F5F7] text-[#8E8E93] uppercase text-xs">
            <tr>
              <th class="text-left px-4 py-3">When</th>
              <th class="text-left px-4 py-3">Assistant</th>
              <th class="text-left px-4 py-3">Source</th>
              <th class="text-left px-4 py-3">Error</th>
              <th class="text-right px-4 py-3">Duration</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={call <- @recent_errors}
              class="border-t border-[#F5F5F7] hover:bg-[#F5F5F7] cursor-pointer"
              phx-click="open_drawer"
              phx-value-id={call.id}
            >
              <td class="px-4 py-3 text-[#8E8E93]">{format_dt(call.inserted_at)}</td>
              <td class="px-4 py-3">{call.assistant_name || "—"}</td>
              <td class="px-4 py-3">{call.source}</td>
              <td class="px-4 py-3 text-[#FF3B30] truncate max-w-md">{truncate(call.error, 80)}</td>
              <td class="px-4 py-3 text-right">{format_ms(call.duration_ms)}</td>
            </tr>
            <tr :if={@recent_errors == []}>
              <td colspan="5" class="px-4 py-8 text-center text-[#8E8E93]">
                No errors in this window.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr :top_calls, :list, required: true

  defp top_calls_section(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md overflow-hidden mb-6">
      <h2 class="font-semibold text-[#1C1C1E] px-5 py-4">Top 25 most expensive calls</h2>
      <div class="overflow-x-auto">
        <table class="w-full text-sm min-w-[640px]">
          <thead class="bg-[#F5F5F7] text-[#8E8E93] uppercase text-xs">
            <tr>
              <th class="text-left px-4 py-3">When</th>
              <th class="text-left px-4 py-3">Assistant</th>
              <th class="text-left px-4 py-3">Source</th>
              <th class="text-right px-4 py-3">Tokens</th>
              <th class="text-right px-4 py-3">Est. cost</th>
              <th class="text-left px-4 py-3">Model</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={call <- @top_calls}
              class="border-t border-[#F5F5F7] hover:bg-[#F5F5F7] cursor-pointer"
              phx-click="open_drawer"
              phx-value-id={call.id}
            >
              <td class="px-4 py-3 text-[#8E8E93]">{format_dt(call.inserted_at)}</td>
              <td class="px-4 py-3">{call.assistant_name || "—"}</td>
              <td class="px-4 py-3">{call.source}</td>
              <td class="px-4 py-3 text-right font-medium">{format_int(call.total_tokens)}</td>
              <td class="px-4 py-3 text-right">
                {Pricing.format_cost_cents(
                  Pricing.cost_cents(call.model, call.prompt_tokens, call.completion_tokens)
                )}
              </td>
              <td class="px-4 py-3 text-[#8E8E93]">{call.model || "—"}</td>
            </tr>
            <tr :if={@top_calls == []}>
              <td colspan="6" class="px-4 py-8 text-center text-[#8E8E93]">
                No calls in this window.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr :call, :map, required: true

  defp detail_drawer(assigns) do
    ~H"""
    <div
      class="fixed inset-0 bg-black/40 z-40"
      phx-click="close_drawer"
      phx-window-keydown="close_drawer"
      phx-key="Escape"
    >
    </div>
    <aside class="fixed right-0 top-0 bottom-0 w-[480px] bg-white shadow-xl z-50 overflow-y-auto">
      <div class="p-6">
        <div class="flex items-center justify-between mb-4">
          <h3 class="font-semibold text-[#1C1C1E]">Call detail</h3>
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
          <.detail_row label="Inserted at" value={DateTime.to_iso8601(@call.inserted_at)} />
          <.detail_row label="Provider" value={@call.provider} />
          <.detail_row label="Model" value={@call.model || "—"} />
          <.detail_row label="Assistant" value={@call.assistant_name || "—"} />
          <.detail_row label="Source" value={@call.source} />
          <.detail_row label="Status" value={@call.status} />
          <.detail_row label="Env" value={@call.env} />
          <.detail_row label="Duration" value={format_ms(@call.duration_ms)} />
          <.detail_row label="Prompt tokens" value={format_int(@call.prompt_tokens)} />
          <.detail_row label="Completion tokens" value={format_int(@call.completion_tokens)} />
          <.detail_row label="Total tokens" value={format_int(@call.total_tokens)} />
          <.detail_row label="Token source" value={@call.token_source} />
          <.detail_row
            label="Est. cost"
            value={
              Pricing.format_cost_cents(
                Pricing.cost_cents(@call.model, @call.prompt_tokens, @call.completion_tokens)
              )
            }
          />
        </dl>

        <div :if={@call.error} class="mt-4">
          <h4 class="text-xs uppercase tracking-wide text-[#8E8E93] mb-1">Error</h4>
          <pre class="text-xs bg-[#FFE5E3] p-3 rounded-lg text-[#FF3B30] whitespace-pre-wrap break-all">{@call.error}</pre>
        </div>

        <div class="mt-4">
          <h4 class="text-xs uppercase tracking-wide text-[#8E8E93] mb-1">Metadata</h4>
          <pre class="text-xs bg-[#F5F5F7] p-3 rounded-lg whitespace-pre-wrap break-all">{Jason.encode!(@call.metadata, pretty: true)}</pre>
        </div>
      </div>
    </aside>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp detail_row(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-3">
      <dt class="text-[#8E8E93]">{@label}</dt>
      <dd class="text-[#1C1C1E] text-right break-all">{@value}</dd>
    </div>
    """
  end

  ## --- Presentation helpers --------------------------------------------

  defp window_pill_class(active?) do
    base = "px-3 py-1 rounded-full text-xs font-medium border transition-colors"

    if active? do
      "#{base} bg-[#4CD964] text-white border-[#4CD964]"
    else
      "#{base} bg-white text-[#1C1C1E] border-[#E5E5EA] hover:border-[#4CD964]/40"
    end
  end

  defp format_int(nil), do: "—"
  defp format_int(%Decimal{} = d), do: d |> Decimal.to_integer() |> format_int()

  defp format_int(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_int(_), do: "—"

  defp format_ms(nil), do: "—"
  defp format_ms(n) when is_integer(n), do: "#{format_int(n)}ms"
  defp format_ms(n) when is_float(n), do: "#{round(n) |> format_int()}ms"
  defp format_ms(%Decimal{} = d), do: format_ms(Decimal.to_float(d))
  defp format_ms(_), do: "—"

  defp format_dt(nil), do: "—"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_dt(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%Y-%m-%d %H:%M")
  defp format_dt(_), do: "—"

  defp format_bucket(nil), do: "—"
  defp format_bucket(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_bucket(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%Y-%m-%d %H:%M")
  defp format_bucket(_), do: "—"

  defp format_error_rate(_errors, 0), do: "—"

  defp format_error_rate(errors, calls)
       when is_integer(errors) and is_integer(calls) and calls > 0 do
    pct = errors / calls * 100.0
    :erlang.float_to_binary(pct, decimals: 1) <> "%"
  end

  defp format_error_rate(_, _), do: "—"

  defp error_rate_high?(errors, calls)
       when is_integer(errors) and is_integer(calls) and calls > 0,
       do: errors / calls > 0.05

  defp error_rate_high?(_, _), do: false

  defp format_latency(nil, nil), do: "—"

  defp format_latency(p50, p95) do
    "#{format_ms_compact(p50)} / #{format_ms_compact(p95)}"
  end

  defp format_ms_compact(nil), do: "—"
  defp format_ms_compact(%Decimal{} = d), do: format_ms_compact(Decimal.to_float(d))
  defp format_ms_compact(n) when is_number(n), do: "#{round(n)}ms"
  defp format_ms_compact(_), do: "—"

  defp format_delta(nil), do: "—"

  defp format_delta(pct) when is_number(pct) do
    sign = if pct >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(pct * 1.0, decimals: 1)}%"
  end

  defp delta_class(nil), do: "text-[#8E8E93]"

  defp delta_class(pct) when is_number(pct) do
    cond do
      pct > 5 -> "text-[#FF3B30] font-medium"
      pct < -5 -> "text-[#4CD964] font-medium"
      true -> "text-[#8E8E93]"
    end
  end

  defp truncate(nil, _n), do: "—"

  defp truncate(str, n) when is_binary(str) do
    if String.length(str) > n, do: String.slice(str, 0, n) <> "…", else: str
  end

  defp truncate(_, _), do: "—"
end
