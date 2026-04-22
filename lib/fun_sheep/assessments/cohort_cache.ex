defmodule FunSheep.Assessments.CohortCache do
  @moduledoc """
  Tiny ETS cache for `Assessments.cohort_percentile_bands/2` (spec §6.3).

  Keyed on `{course_id, grade}` with a 15-minute TTL. Plain ETS was
  chosen over Cachex to avoid adding a dependency; the access pattern
  (short-lived reads on dashboard mount, occasional writes on miss) is
  a perfect fit for a read-heavy public table.
  """

  use GenServer

  @table :fun_sheep_cohort_cache
  @default_ttl_ms 15 * 60 * 1_000

  ## ── Public API ───────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Looks up `key` in the cache. If present and fresh, returns the value;
  otherwise calls `miss.()` to compute it, stores it, and returns the
  result. The cache is process-safe via the GenServer writer; readers go
  straight to ETS to avoid a bottleneck.
  """
  def fetch(key, miss) when is_function(miss, 0) do
    ensure_table()

    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] ->
        if monotonic_ms() < expires_at do
          value
        else
          store_and_return(key, miss)
        end

      [] ->
        store_and_return(key, miss)
    end
  end

  @doc "Clears a single key. Primarily for tests."
  def invalidate(key) do
    ensure_table()
    :ets.delete(@table, key)
    :ok
  end

  @doc "Clears everything. Primarily for tests."
  def flush do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  ## ── Internal ─────────────────────────────────────────────────────────────

  defp store_and_return(key, miss) do
    value = miss.()
    expires_at = monotonic_ms() + @default_ttl_ms
    :ets.insert(@table, {key, value, expires_at})
    value
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        GenServer.call(__MODULE__, :ensure_table)

      _ ->
        :ok
    end
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)

  ## ── GenServer callbacks ──────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    create_table()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:ensure_table, _from, state) do
    create_table()
    {:reply, :ok, state}
  end

  defp create_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :named_table,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        :ok
    end
  end
end
