defmodule StudySmart.Storage.Local do
  @moduledoc """
  Local filesystem storage backend.

  Stores files under `priv/uploads/` relative to the application root.
  Suitable for development and testing environments.
  """

  @behaviour StudySmart.Storage

  @uploads_dir "priv/uploads"

  @impl true
  def put(path, content, _opts \\ []) do
    full_path = full_path(path)
    dir = Path.dirname(full_path)

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(full_path, content) do
      {:ok, path}
    end
  end

  @impl true
  def get(path, _opts \\ []) do
    path
    |> full_path()
    |> File.read()
  end

  @impl true
  def delete(path, _opts \\ []) do
    full_path = full_path(path)

    case File.rm(full_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def url(path, _opts \\ []) do
    "/uploads/#{path}"
  end

  @doc """
  Returns the base uploads directory path.
  """
  def uploads_dir do
    Path.join(Application.app_dir(:study_smart), @uploads_dir)
  end

  defp full_path(path) do
    Path.join(uploads_dir(), path)
  end
end
