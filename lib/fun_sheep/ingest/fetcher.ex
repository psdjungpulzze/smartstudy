defmodule FunSheep.Ingest.Fetcher do
  @moduledoc """
  HTTP downloader that streams a remote URL into the ingestion cache.

  Uses `Req` with `into: File.stream!/1` so a 500 MB NCES bundle never
  lives entirely in memory. Downloaded bytes are written to a temp file
  first, then atomically moved into the cache via
  `FunSheep.Ingest.Cache.write_local/2`.
  """

  require Logger

  alias FunSheep.Ingest.Cache

  @default_timeout :timer.minutes(10)

  @doc """
  Fetch `url` into the cache under `key`.

  Returns `{:ok, local_path}` once the file is readable on local disk.

  Options:
    * `:headers` — extra request headers (list of `{k, v}` tuples)
    * `:timeout` — receive timeout in ms, default 10 minutes
    * `:force` — skip cache and re-download
  """
  @spec fetch(String.t(), String.t(), keyword()) :: {:ok, Path.t()} | {:error, term()}
  def fetch(url, key, opts \\ []) do
    if Keyword.get(opts, :force, false) do
      download(url, key, opts)
    else
      case Cache.ensure_local(key) do
        {:ok, path} ->
          Logger.info("ingest.fetcher cache hit", key: key, path: path)
          {:ok, path}

        {:error, :not_cached} ->
          download(url, key, opts)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp download(url, key, opts) do
    tmp_path =
      Path.join(System.tmp_dir!(), "fun_sheep_ingest_#{System.unique_integer([:positive])}")

    Logger.info("ingest.fetcher downloading", url: url, to: tmp_path)

    headers = Keyword.get(opts, :headers, [])
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    try do
      case Req.get(url,
             headers: headers,
             receive_timeout: timeout,
             redirect: true,
             into: File.stream!(tmp_path)
           ) do
        {:ok, %{status: status}} when status in 200..299 ->
          bytes = File.stat!(tmp_path).size
          Logger.info("ingest.fetcher downloaded", url: url, bytes: bytes)
          result = Cache.write_local(key, tmp_path)
          File.rm(tmp_path)
          result

        {:ok, %{status: status}} ->
          File.rm(tmp_path)
          {:error, {:http_error, status, url}}

        {:error, reason} ->
          File.rm(tmp_path)
          {:error, reason}
      end
    rescue
      e ->
        File.rm(tmp_path)
        {:error, {:exception, Exception.message(e)}}
    end
  end
end
