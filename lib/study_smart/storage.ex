defmodule StudySmart.Storage do
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

  def impl, do: Application.get_env(:study_smart, :storage_backend, StudySmart.Storage.Local)

  def put(path, content, opts \\ []), do: impl().put(path, content, opts)
  def get(path, opts \\ []), do: impl().get(path, opts)
  def delete(path, opts \\ []), do: impl().delete(path, opts)
  def url(path, opts \\ []), do: impl().url(path, opts)
end
