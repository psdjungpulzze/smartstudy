defmodule FunSheep.Storage.Local do
  @moduledoc """
  Local filesystem storage backend.

  Stores files under `priv/uploads/` relative to the application root.
  Suitable for development and testing environments.

  Storage keys follow the same convention as the GCS backend: no leading
  slash and no bucket/prefix (e.g. `staging/<batch_id>/<filename>`).
  """

  @behaviour FunSheep.Storage

  @uploads_dir "priv/uploads"

  @impl true
  def put(key, content, _opts \\ []) do
    key = normalize_key(key)
    full_path = full_path(key)
    dir = Path.dirname(full_path)

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(full_path, content) do
      {:ok, key}
    end
  end

  @impl true
  def get(key, _opts \\ []) do
    key
    |> normalize_key()
    |> full_path()
    |> File.read()
  end

  @impl true
  def delete(key, _opts \\ []) do
    full_path = full_path(normalize_key(key))

    case File.rm(full_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def url(key, _opts \\ []) do
    "/uploads/#{normalize_key(key)}"
  end

  @doc """
  Returns the base uploads directory path.
  """
  def uploads_dir do
    Path.join(Application.app_dir(:fun_sheep), @uploads_dir)
  end

  defp full_path(key) do
    Path.join(uploads_dir(), key)
  end

  defp normalize_key("/" <> rest), do: normalize_key(rest)
  defp normalize_key(key) when is_binary(key), do: key
end
