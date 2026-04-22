defmodule FunSheep.AIUsage.Guard do
  @moduledoc """
  Opt-in safeguards against runaway AI spend. Two complementary limits:

    * **Circuit breaker** — per-source failure counter in ETS. After
      `circuit_threshold` failures inside `circuit_window_ms`, the circuit
      trips OPEN for `circuit_cooldown_ms`. New calls from that source are
      short-circuited with `{:error, :circuit_open}` so the app stops
      burning tokens against a throttled / degraded upstream.

    * **Daily token budget** — per-source cap on total tokens consumed in
      the current UTC day, computed from `FunSheep.AIUsage` rows. When the
      cap is exceeded, new calls return `{:error, :budget_exceeded}` until
      UTC midnight.

  Both are wired into `FunSheep.Interactor.Agents.chat/3`; callers that
  want to bypass can pass `guard: false` in opts (used sparingly — the
  per-session tutor flow bypasses because its cost is inherently bounded
  by user interaction rate).

  ## Configuration

      config :fun_sheep, FunSheep.AIUsage.Guard,
        circuit_threshold: 10,
        circuit_window_ms: 60_000,
        circuit_cooldown_ms: 120_000,
        daily_budget_tokens: %{
          "question_quality_reviewer" => 1_000_000,
          "question_skill_tagger" => 500_000
          # any source not listed has no budget cap
        }

  All values are overridable per-environment. Defaults are conservative
  (high enough not to bite normal operation, low enough to stop a runaway).
  """

  use GenServer

  alias FunSheep.AIUsage

  require Logger

  @ets __MODULE__.State

  # ETS row shape: {source_key, fail_count, window_started_at_ms, tripped_until_ms, budget_cached_at_ms, budget_used_tokens}
  # - source_key: binary, the :source label (assistant_name or explicit opts[:source])
  # - fail_count: int, failures in current window
  # - window_started_at_ms: monotonic time the current window began
  # - tripped_until_ms: monotonic time the circuit should reopen (0 if closed)
  # - budget_cached_at_ms: monotonic time of last AIUsage query
  # - budget_used_tokens: total_tokens observed at that query

  @budget_cache_ttl_ms 60_000

  ## --- Public API -------------------------------------------------------

  @doc """
  Start link — registered under `__MODULE__`. Creates the backing ETS
  table on first start. Safe to call multiple times (returns `{:ok, pid}`
  or `{:error, {:already_started, pid}}`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check whether a call is permitted right now. Returns `:ok` on pass,
  `{:error, reason}` on block. Cheap — one ETS lookup plus (at most) one
  AIUsage query per `#{div(@budget_cache_ttl_ms, 1000)}s` per source.
  """
  @spec check(String.t()) :: :ok | {:error, :circuit_open | :budget_exceeded}
  def check(source) when is_binary(source) do
    now_ms = monotonic_ms()

    cond do
      circuit_open?(source, now_ms) -> {:error, :circuit_open}
      budget_exceeded?(source, now_ms) -> {:error, :budget_exceeded}
      true -> :ok
    end
  end

  def check(_), do: :ok

  @doc """
  Record a successful call — resets the circuit-breaker window for this
  source so a stale failure count from an earlier spike can't carry
  forward indefinitely.
  """
  @spec record_success(String.t()) :: :ok
  def record_success(source) when is_binary(source) do
    _ = ensure_row(source)
    # Clear fail count + any prior trip.
    :ets.update_element(@ets, source, [{2, 0}, {3, 0}, {4, 0}])
    :ok
  end

  def record_success(_), do: :ok

  @doc """
  Record a failure. `reason` is stored only in logs — the ETS row just
  carries a counter. If the count crosses `circuit_threshold` inside the
  window, the circuit trips open for `circuit_cooldown_ms`.
  """
  @spec record_failure(String.t(), term()) :: :ok
  def record_failure(source, reason) when is_binary(source) do
    now_ms = monotonic_ms()
    cfg = config()
    _ = ensure_row(source)

    case :ets.lookup(@ets, source) do
      [{^source, count, window_start, _tripped, _cached_at, _budget}] ->
        {new_count, new_window_start} = bump_window(count, window_start, now_ms, cfg)

        if new_count >= cfg.circuit_threshold do
          trip_until = now_ms + cfg.circuit_cooldown_ms

          :ets.update_element(@ets, source, [
            {2, new_count},
            {3, new_window_start},
            {4, trip_until}
          ])

          Logger.warning(
            "[Guard] #{source}: circuit OPENED after #{new_count} failures " <>
              "(latest: #{inspect(reason)}); cooling down for " <>
              "#{div(cfg.circuit_cooldown_ms, 1000)}s"
          )
        else
          :ets.update_element(@ets, source, [
            {2, new_count},
            {3, new_window_start}
          ])
        end

        :ok

      [] ->
        :ok
    end
  end

  def record_failure(_, _), do: :ok

  @doc false
  def reset_all do
    :ets.delete_all_objects(@ets)
    :ok
  end

  ## --- GenServer --------------------------------------------------------

  @impl true
  def init(_opts) do
    :ets.new(@ets, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    {:ok, %{}}
  end

  ## --- Internals --------------------------------------------------------

  # Trip state is encoded in a `tripped_until_ms` stored as system (wall)
  # time. Wall clock is always positive, so `0` is a safe never-tripped
  # sentinel. A trip is active iff `tripped_until != 0` AND
  # `now_ms < tripped_until`.
  defp circuit_open?(source, now_ms) do
    _ = ensure_row(source)

    case :ets.lookup(@ets, source) do
      [{^source, _count, _win, tripped_until, _cached_at, _budget}]
      when tripped_until != 0 ->
        if now_ms < tripped_until do
          true
        else
          # Cooldown elapsed — half-open: clear trip, let the next call try.
          :ets.update_element(@ets, source, [{2, 0}, {3, 0}, {4, 0}])
          false
        end

      _ ->
        false
    end
  end

  defp budget_exceeded?(source, now_ms) do
    cfg = config()
    cap = Map.get(cfg.daily_budget_tokens, source)

    cond do
      is_nil(cap) or cap <= 0 ->
        false

      true ->
        used = cached_budget_usage(source, now_ms, cfg)

        if used >= cap do
          Logger.warning(
            "[Guard] #{source}: daily budget exceeded — used=#{used} cap=#{cap}. " <>
              "Rejecting calls until next UTC midnight."
          )

          true
        else
          false
        end
    end
  end

  # Cache the AIUsage lookup per source so we don't query on every call.
  # TTL is short (60s by default) so a freshly-paid invoice shows up
  # quickly — we're not trying to be precise about the minute boundary,
  # just stop the bleeding inside the order-of-a-minute.
  defp cached_budget_usage(source, now_ms, _cfg) do
    _ = ensure_row(source)

    case :ets.lookup(@ets, source) do
      [{^source, _c, _w, _t, cached_at, used}]
      when cached_at > 0 and now_ms - cached_at < @budget_cache_ttl_ms ->
        used

      _ ->
        used = fetch_daily_tokens(source)
        :ets.update_element(@ets, source, [{5, now_ms}, {6, used}])
        used
    end
  end

  defp fetch_daily_tokens(source) do
    {:ok, today_midnight} =
      Date.utc_today()
      |> DateTime.new(~T[00:00:00.000], "Etc/UTC")

    AIUsage.summary(%{source: source, since: today_midnight})
    |> Map.get(:total_tokens, 0)
  rescue
    e ->
      Logger.warning("[Guard] budget lookup crashed for #{source}: #{Exception.message(e)}")
      0
  end

  defp bump_window(count, window_start, now_ms, cfg) do
    if window_start == 0 or now_ms - window_start > cfg.circuit_window_ms do
      # Fresh window.
      {1, now_ms}
    else
      {count + 1, window_start}
    end
  end

  defp ensure_row(source) do
    :ets.insert_new(@ets, {source, 0, 0, 0, 0, 0})
  end

  # Wall-clock millis — always positive, so `0` is a safe sentinel for
  # "no trip active" / "no budget query yet".
  defp monotonic_ms, do: System.system_time(:millisecond)

  defp config do
    env = Application.get_env(:fun_sheep, __MODULE__, [])

    %{
      circuit_threshold: Keyword.get(env, :circuit_threshold, 10),
      circuit_window_ms: Keyword.get(env, :circuit_window_ms, 60_000),
      circuit_cooldown_ms: Keyword.get(env, :circuit_cooldown_ms, 120_000),
      daily_budget_tokens: Keyword.get(env, :daily_budget_tokens, %{})
    }
  end
end
