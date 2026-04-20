defmodule FunSheep.Ingest.Cache do
  @moduledoc """
  Two-tier cache for raw ingestion payloads (NCES CSVs, IPEDS zips, NEIS
  bundles, GIAS extracts, ...).

  Tier 1: local filesystem at `priv/cache/ingest/` — used during parsing,
          fast, ephemeral.
  Tier 2: Google Cloud Storage under `ingest/<source>/<yyyy-mm-dd>/<filename>`
          — durable preservation so a refresh next year can diff against
          last year's snapshot, and so workers on cold Cloud Run instances
          can skip re-downloading a multi-hundred-MB dataset.

  `ensure_local/2` is the primary entry point: given a cache key, return a
  local filesystem path, pulling from GCS if needed. Writes go local-first,
  then async-copy to GCS when the bucket is configured.
  """

  require Logger

  alias FunSheep.Storage.GCS

  @doc """
  Build a deterministic cache key.

      iex> FunSheep.Ingest.Cache.build_key("nces_ccd", "ccd_lea_029_2324_w_0a_07012024.csv", ~D[2024-07-01])
      "ingest/nces_ccd/2024-07-01/ccd_lea_029_2324_w_0a_07012024.csv"
  """
  @spec build_key(String.t(), String.t(), Date.t()) :: String.t()
  def build_key(source, filename, %Date{} = date) do
    "ingest/#{source}/#{Date.to_iso8601(date)}/#{filename}"
  end

  def build_key(source, filename), do: build_key(source, filename, Date.utc_today())

  @doc """
  Return a local filesystem path containing the bytes for `key`.

  Resolution order:
    1. Local cache hit — return immediately.
    2. GCS hit (when bucket configured) — download to local, return path.
    3. Return `{:error, :not_cached}` — caller must `write_local/2` first.
  """
  @spec ensure_local(String.t()) :: {:ok, Path.t()} | {:error, term()}
  def ensure_local(key) do
    local = local_path(key)

    cond do
      File.exists?(local) ->
        {:ok, local}

      gcs_enabled?() ->
        pull_from_gcs(key, local)

      true ->
        {:error, :not_cached}
    end
  end

  @doc """
  Write bytes (from a local path) into the cache.

  After writing locally, upload to GCS asynchronously when a bucket is
  configured. The local path is the authoritative handle returned — GCS
  is preservation, not hot path.
  """
  @spec write_local(String.t(), Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def write_local(key, source_path) when is_binary(source_path) do
    local = local_path(key)
    File.mkdir_p!(Path.dirname(local))

    case File.cp(source_path, local) do
      :ok ->
        maybe_upload_to_gcs(key, local)
        {:ok, local}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Return the local filesystem path for `key` (does not create the file).
  """
  @spec local_path(String.t()) :: Path.t()
  def local_path(key) do
    Path.join([cache_root(), key])
  end

  defp cache_root do
    Application.get_env(:fun_sheep, __MODULE__)[:root] ||
      Path.join([File.cwd!(), "priv", "cache"])
  end

  defp gcs_enabled? do
    Application.get_env(:fun_sheep, FunSheep.Storage.GCS)[:bucket] != nil
  end

  defp pull_from_gcs(key, local) do
    case GCS.get(key) do
      {:ok, bytes} ->
        File.mkdir_p!(Path.dirname(local))
        File.write!(local, bytes)
        Logger.info("ingest.cache pulled from GCS", key: key, bytes: byte_size(bytes))
        {:ok, local}

      {:error, :not_found} ->
        {:error, :not_cached}

      {:error, reason} ->
        Logger.warning("ingest.cache GCS fetch failed", key: key, reason: inspect(reason))
        {:error, reason}
    end
  end

  defp maybe_upload_to_gcs(key, local) do
    if gcs_enabled?() do
      Task.start(fn ->
        content_type = guess_content_type(key)

        case GCS.put(key, File.read!(local), content_type: content_type) do
          {:ok, _} ->
            Logger.info("ingest.cache uploaded to GCS", key: key)

          {:error, reason} ->
            Logger.warning("ingest.cache GCS upload failed",
              key: key,
              reason: inspect(reason)
            )
        end
      end)
    end

    :ok
  end

  defp guess_content_type(key) do
    case Path.extname(key) do
      ".csv" -> "text/csv"
      ".zip" -> "application/zip"
      ".json" -> "application/json"
      ".tsv" -> "text/tab-separated-values"
      ".txt" -> "text/plain"
      _ -> "application/octet-stream"
    end
  end
end
