defmodule FunSheep.Storage.GCS do
  @moduledoc """
  Google Cloud Storage backend.

  Reads/writes objects in the configured bucket using the JSON API.
  Authentication is handled by `Goth` — on Cloud Run this uses the
  Workload Identity metadata server, so no JSON key file is required.

  ## Configuration

      config :fun_sheep, FunSheep.Storage.GCS,
        bucket: System.get_env("GCS_BUCKET"),
        goth_name: FunSheep.Goth

  ## Object keys

  Keys must not start with `/` and must not include the bucket name.
  Examples:
    * `staging/<batch_id>/<file.pdf>`
    * `courses/<course_id>/<folder>/<file.pdf>`
  """

  @behaviour FunSheep.Storage

  @base_url "https://storage.googleapis.com"
  @upload_url "https://storage.googleapis.com/upload/storage/v1/b"

  @impl true
  def put(key, content, opts \\ []) do
    key = normalize_key(key)
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")
    url = "#{@upload_url}/#{bucket()}/o?uploadType=media&name=#{encode_object_name(key)}"

    case request(:post, url,
           headers: [{"content-type", content_type}],
           body: content
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, key}

      {:ok, resp} ->
        {:error, {:gcs_error, resp.status, resp.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get(key, _opts \\ []) do
    key = normalize_key(key)
    url = "#{@base_url}/storage/v1/b/#{bucket()}/o/#{encode_object_name(key)}?alt=media"

    case request(:get, url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, resp} ->
        {:error, {:gcs_error, resp.status, resp.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def delete(key, _opts \\ []) do
    key = normalize_key(key)
    url = "#{@base_url}/storage/v1/b/#{bucket()}/o/#{encode_object_name(key)}"

    case request(:delete, url) do
      {:ok, %{status: status}} when status in [200, 204, 404] ->
        :ok

      {:ok, resp} ->
        {:error, {:gcs_error, resp.status, resp.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def url(key, _opts \\ []) do
    "/uploads/#{normalize_key(key)}"
  end

  defp request(method, url, opts \\ []) do
    headers =
      [{"authorization", "Bearer #{fetch_token!()}"}] ++
        Keyword.get(opts, :headers, [])

    req_opts =
      [method: method, url: url, headers: headers, decode_body: false]
      |> maybe_put(:body, Keyword.get(opts, :body))

    Req.request(req_opts)
  end

  defp maybe_put(opts, _k, nil), do: opts
  defp maybe_put(opts, k, v), do: Keyword.put(opts, k, v)

  defp fetch_token! do
    name = Application.get_env(:fun_sheep, __MODULE__)[:goth_name] || FunSheep.Goth
    %{token: token} = Goth.fetch!(name)
    token
  end

  defp bucket do
    Application.get_env(:fun_sheep, __MODULE__)[:bucket] ||
      raise """
      GCS bucket is not configured. Set GCS_BUCKET env var or:

          config :fun_sheep, FunSheep.Storage.GCS, bucket: "your-bucket"
      """
  end

  defp normalize_key("/" <> rest), do: normalize_key(rest)
  defp normalize_key(key) when is_binary(key), do: key

  # Percent-encode the object name for use in a URL path segment.
  # `URI.encode_www_form/1` is for form bodies and encodes spaces as `+`,
  # which GCS interprets as a literal `+` in a URL path — causing 404s
  # on keys containing spaces.
  @doc false
  def encode_object_name(key), do: URI.encode(key, &URI.char_unreserved?/1)
end
