defmodule FunSheep.Assessments.SessionStore do
  @moduledoc """
  Database-backed persistence for in-progress assessment sessions.

  Works alongside ETS-backed `StateCache`. ETS is the fast path for
  mid-session continuity; this store handles recovery after a server
  restart when ETS has been cleared.

  The `engine_state` is serialized via JSON round-trip. Atom-keyed maps
  survive the round-trip via `Jason.decode!/2` with `keys: :atoms!` on
  load. The `enabled_sources` MapSet is serialized as a list of strings.

  ## Responsibility split

  - `StateCache` — fast, in-memory, cleared on restart
  - `SessionStore` — slow, durable, survives restarts
  - `AssessmentLive` — writes both on every state change; reads ETS first,
    falls back to DB only on cache miss after restart
  """

  import Ecto.Query

  alias FunSheep.Assessments.AssessmentSessionState
  alias FunSheep.Repo

  require Logger

  @doc """
  Persists assessment state for a user+schedule pair.

  Upserts on the composite key (user_role_id, schedule_id). The engine_state
  map and enabled_sources MapSet are serialized to JSON-compatible structures.
  """
  @spec save(String.t(), String.t(), map()) :: :ok
  def save(user_role_id, schedule_id, state) do
    serialized_engine = serialize_engine_state(state[:engine_state])
    enabled_sources = serialize_enabled_sources(state[:enabled_sources])

    attrs = %{
      user_role_id: user_role_id,
      schedule_id: schedule_id,
      engine_state: serialized_engine,
      question_number: state[:question_number] || 0,
      phase: to_string(state[:phase] || "testing"),
      enabled_sources: enabled_sources,
      selected_answer: state[:selected_answer],
      assessment_complete: state[:assessment_complete] || false
    }

    %AssessmentSessionState{}
    |> AssessmentSessionState.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :engine_state,
           :question_number,
           :phase,
           :enabled_sources,
           :selected_answer,
           :assessment_complete,
           :updated_at
         ]},
      conflict_target: [:user_role_id, :schedule_id]
    )
    |> case do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("[SessionStore] Failed to save session state: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Loads persisted session state for a user+schedule pair.

  Returns `{:ok, state_map}` where the state_map mirrors the structure stored
  by `StateCache`, with the engine_state rehydrated from JSON. Atom-keyed maps
  are restored via `keys: :atoms!`.

  Returns `:miss` if no record exists.
  """
  @spec load(String.t(), String.t()) :: {:ok, map()} | :miss
  def load(user_role_id, schedule_id) do
    case Repo.get_by(AssessmentSessionState,
           user_role_id: user_role_id,
           schedule_id: schedule_id
         ) do
      nil ->
        :miss

      record ->
        engine_state = deserialize_engine_state(record.engine_state)
        enabled_sources = deserialize_enabled_sources(record.enabled_sources)

        state = %{
          engine_state: engine_state,
          current_question: nil,
          current_question_stats: nil,
          selected_answer: record.selected_answer,
          feedback: nil,
          question_number: record.question_number,
          enabled_sources: enabled_sources,
          assessment_complete: record.assessment_complete,
          summary: nil,
          phase: String.to_existing_atom(record.phase)
        }

        {:ok, state}
    end
  rescue
    e ->
      Logger.error("[SessionStore] Failed to load session state: #{inspect(e)}")
      :miss
  end

  @doc """
  Deletes the persisted session state for a user+schedule pair.

  Called when an assessment completes or is explicitly reset.
  """
  @spec delete(String.t(), String.t()) :: :ok
  def delete(user_role_id, schedule_id) do
    from(s in AssessmentSessionState,
      where: s.user_role_id == ^user_role_id and s.schedule_id == ^schedule_id
    )
    |> Repo.delete_all()

    :ok
  rescue
    e ->
      Logger.error("[SessionStore] Failed to delete session state: #{inspect(e)}")
      :ok
  end

  defp serialize_engine_state(nil), do: nil

  defp serialize_engine_state(engine_state) do
    engine_state
    |> atomize_for_json()
    |> Jason.encode!()
    |> Jason.decode!()
  rescue
    e ->
      Logger.warning("[SessionStore] Could not serialize engine_state: #{inspect(e)}")
      nil
  end

  defp deserialize_engine_state(nil), do: nil

  defp deserialize_engine_state(engine_map) when is_map(engine_map) do
    engine_map
    |> Jason.encode!()
    |> Jason.decode!(keys: :atoms!)
  rescue
    e ->
      Logger.warning("[SessionStore] Could not deserialize engine_state: #{inspect(e)}")
      nil
  end

  defp serialize_enabled_sources(nil), do: []
  defp serialize_enabled_sources(%MapSet{} = set), do: MapSet.to_list(set)
  defp serialize_enabled_sources(list) when is_list(list), do: list

  defp deserialize_enabled_sources(nil), do: MapSet.new()
  defp deserialize_enabled_sources(list) when is_list(list), do: MapSet.new(list)

  # Convert any atoms in the engine state to strings for JSON serialization.
  # Jason handles atom keys/values natively, but we encode then decode to get
  # a clean string-keyed map for the DB column, then decode back with atoms!
  # on load. This function just ensures the value is JSON-encodable.
  defp atomize_for_json(value)
       when is_atom(value) and not is_nil(value) and not is_boolean(value),
       do: Atom.to_string(value)

  defp atomize_for_json(value) when is_map(value) do
    Map.new(value, fn {k, v} -> {atomize_for_json(k), atomize_for_json(v)} end)
  end

  defp atomize_for_json(value) when is_list(value), do: Enum.map(value, &atomize_for_json/1)
  defp atomize_for_json(value), do: value
end
