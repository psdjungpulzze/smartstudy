defmodule FunSheep.Assessments.StateCache do
  @moduledoc """
  ETS-backed cache for in-progress assessment state.

  Prevents assessment resets on LiveView reconnects by storing engine state
  keyed by {user_role_id, schedule_id}. Entries expire after 2 hours.
  """

  use GenServer

  @table :assessment_state_cache
  @ttl_seconds 2 * 60 * 60
  @cleanup_interval_ms 10 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Store assessment state for a user+schedule."
  def put(user_role_id, schedule_id, state) do
    :ets.insert(@table, {{user_role_id, schedule_id}, state, System.monotonic_time(:second)})
    :ok
  end

  @doc "Retrieve assessment state if it exists and hasn't expired."
  def get(user_role_id, schedule_id) do
    case :ets.lookup(@table, {user_role_id, schedule_id}) do
      [{_key, state, stored_at}] ->
        if System.monotonic_time(:second) - stored_at < @ttl_seconds do
          {:ok, state}
        else
          delete(user_role_id, schedule_id)
          :miss
        end

      [] ->
        :miss
    end
  end

  @doc "Remove assessment state (on completion or explicit reset)."
  def delete(user_role_id, schedule_id) do
    :ets.delete(@table, {user_role_id, schedule_id})
    :ok
  end

  @doc "Store exam simulation state."
  def put_exam(user_role_id, session_id, state) do
    :ets.insert(
      @table,
      {{:exam, user_role_id, session_id}, state, System.monotonic_time(:second)}
    )

    :ok
  end

  @doc "Retrieve exam simulation state if not expired."
  def get_exam(user_role_id, session_id) do
    case :ets.lookup(@table, {:exam, user_role_id, session_id}) do
      [{_key, state, stored_at}] ->
        if System.monotonic_time(:second) - stored_at < @ttl_seconds do
          {:ok, state}
        else
          delete_exam(user_role_id, session_id)
          :miss
        end

      [] ->
        :miss
    end
  end

  @doc "Remove exam simulation state."
  def delete_exam(user_role_id, session_id) do
    :ets.delete(@table, {:exam, user_role_id, session_id})
    :ok
  end

  # GenServer callbacks

  @impl true
  def init(_) do
    table = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:second)

    :ets.foldl(
      fn {key, _state, stored_at}, acc ->
        if now - stored_at >= @ttl_seconds, do: :ets.delete(@table, key)
        acc
      end,
      nil,
      @table
    )

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end
