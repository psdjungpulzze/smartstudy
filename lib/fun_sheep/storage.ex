defmodule FunSheep.Storage do
  @moduledoc """
  Storage abstraction. Swap between local and S3 via config.
  """

  @callback put(path :: String.t(), content :: binary(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}
  @callback get(path :: String.t(), opts :: keyword()) ::
              {:ok, binary()} | {:error, term()}
  @callback delete(path :: String.t(), opts :: keyword()) ::
              :ok | {:error, term()}
  @callback url(path :: String.t(), opts :: keyword()) :: String.t()

  @doc """
  Initiate a resumable upload session and return a URL the client can PUT
  directly to. For GCS this is a session URI returned by the storage API;
  for the Local backend it's a route on this app that accepts PUT.

  Returns `{:ok, %{upload_url: String.t(), object_key: String.t()}}`.
  """
  @callback start_resumable_upload(path :: String.t(), opts :: keyword()) ::
              {:ok, %{upload_url: String.t(), object_key: String.t()}} | {:error, term()}

  @doc """
  Check whether an object exists. Returns `{:ok, size_in_bytes}` if present,
  `{:error, :not_found}` if missing, other `{:error, reason}` on failure.
  """
  @callback object_info(path :: String.t()) ::
              {:ok, %{size: non_neg_integer()}} | {:error, :not_found} | {:error, term()}

  def impl, do: Application.get_env(:fun_sheep, :storage_backend, FunSheep.Storage.Local)

  def put(path, content, opts \\ []), do: impl().put(path, content, opts)
  def get(path, opts \\ []), do: impl().get(path, opts)
  def delete(path, opts \\ []), do: impl().delete(path, opts)
  def url(path, opts \\ []), do: impl().url(path, opts)
  def start_resumable_upload(path, opts \\ []), do: impl().start_resumable_upload(path, opts)
  def object_info(path), do: impl().object_info(path)
end
