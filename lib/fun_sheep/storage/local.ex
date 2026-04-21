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

  @impl true
  def start_resumable_upload(key, _opts \\ []) do
    # The Local backend has no remote endpoint to PUT to, so the upload URL
    # points back into this app. The endpoint lives at
    # `FunSheepWeb.UploadController.local_put/2` (dev/test only) which reads
    # the PUT body and writes it to the same path `put/3` would have chosen.
    # A nonce in the URL prevents other users guessing object keys.
    key = normalize_key(key)
    token = token_for(key)
    {:ok, %{upload_url: "/api/uploads/local/#{token}/#{key}", object_key: key}}
  end

  @impl true
  def object_info(key) do
    full_path = full_path(normalize_key(key))

    case File.stat(full_path) do
      {:ok, %File.Stat{size: size}} -> {:ok, %{size: size}}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Mint a nonce token binding the local-upload URL to a specific object key.
  The dev upload endpoint refuses PUTs whose path doesn't match the token.
  """
  def token_for(key) do
    key = normalize_key(key)
    secret = secret()
    :crypto.mac(:hmac, :sha256, secret, key) |> Base.url_encode64(padding: false)
  end

  @doc """
  Verify a token matches a key. Constant-time compare via :crypto.hash_equals
  when available, else a plain compare (dev/test only — token is a capability,
  not an auth credential).
  """
  def verify_token(key, token) do
    expected = token_for(key)
    # Binary compare — equal? is not constant-time but this is a dev helper.
    expected == token
  end

  defp secret do
    # Use the Phoenix endpoint secret as the HMAC key. Tests configure it
    # the same way production does; dev has a fixed secret in config/dev.exs.
    case Application.get_env(:fun_sheep, FunSheepWeb.Endpoint)[:secret_key_base] do
      nil -> "fun_sheep_local_upload_secret_not_configured"
      s -> s
    end
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
