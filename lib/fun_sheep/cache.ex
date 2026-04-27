defmodule FunSheep.Cache do
  @moduledoc """
  Shared Redis-backed cache for data that must be consistent across all instances.

  Falls back gracefully when Redis is not configured (REDIS_URL unset) — callers
  always get :miss and writes are silently dropped, so the app degrades to
  per-instance ETS caching rather than crashing.

  ## Usage

      # Store with TTL (seconds)
      FunSheep.Cache.put("cohort:\#{id}", data, 3600)

      # Retrieve
      case FunSheep.Cache.get("cohort:\#{id}") do
        {:ok, value} -> value
        :miss -> recompute_and_cache()
      end

      # Atomic rate-limit counter (returns new count after increment)
      FunSheep.Cache.incr("rate:anthropic", ttl_seconds: 60)

      # Delete
      FunSheep.Cache.delete("cohort:\#{id}")

  Values are JSON-encoded before storage so structured data (maps, lists)
  round-trips correctly.
  """

  require Logger

  @conn :funsheep_redis

  @doc "Retrieve a cached value. Returns {:ok, value} or :miss."
  @spec get(String.t()) :: {:ok, term()} | :miss
  def get(key) do
    with true <- redis_available?(),
         {:ok, raw} when not is_nil(raw) <- Redix.command(@conn, ["GET", key]),
         {:ok, decoded} <- Jason.decode(raw) do
      {:ok, decoded}
    else
      false -> :miss
      {:ok, nil} -> :miss
      _ -> :miss
    end
  rescue
    e ->
      Logger.warning("[Cache] get/1 failed for key=#{key}: #{inspect(e)}")
      :miss
  end

  @doc "Store a value with a TTL in seconds."
  @spec put(String.t(), term(), pos_integer()) :: :ok
  def put(key, value, ttl_seconds) do
    with true <- redis_available?(),
         {:ok, encoded} <- Jason.encode(value) do
      Redix.command(@conn, ["SETEX", key, ttl_seconds, encoded])
    end

    :ok
  rescue
    e ->
      Logger.warning("[Cache] put/3 failed for key=#{key}: #{inspect(e)}")
      :ok
  end

  @doc "Delete a key."
  @spec delete(String.t()) :: :ok
  def delete(key) do
    if redis_available?(), do: Redix.command(@conn, ["DEL", key])
    :ok
  rescue
    _ -> :ok
  end

  @doc """
  Increment a counter and optionally set a TTL on first write.
  Returns the new count, or 0 if Redis is unavailable.
  """
  @spec incr(String.t(), keyword()) :: non_neg_integer()
  def incr(key, opts \\ []) do
    ttl = Keyword.get(opts, :ttl_seconds)

    if redis_available?() do
      {:ok, count} = Redix.command(@conn, ["INCR", key])
      if ttl && count == 1, do: Redix.command(@conn, ["EXPIRE", key, ttl])
      count
    else
      0
    end
  rescue
    _ -> 0
  end

  defp redis_available? do
    Process.whereis(@conn) != nil
  end
end
