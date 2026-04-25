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

  @doc """
  Returns the `gs://bucket/key` URI for a stored object. Used by Vision OCR
  to read the image server-side via `gcsImageUri`, avoiding a base64 upload.
  """
  def gcs_uri(key) do
    "gs://#{bucket()}/#{normalize_key(key)}"
  end

  @doc """
  Returns the bucket name configured for this backend.
  Exposed so Vision can specify `outputConfig.gcsDestination` against the
  same bucket the PDF was uploaded to.
  """
  def bucket_name, do: bucket()

  @impl true
  def start_resumable_upload(key, opts \\ []) do
    key = normalize_key(key)
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")
    content_length = Keyword.get(opts, :content_length)
    init_url = "#{@upload_url}/#{bucket()}/o?uploadType=resumable&name=#{encode_object_name(key)}"

    # GCS resumable-upload initiation: POST with the intended upload's
    # metadata in the headers. The server responds 200/201 with a `Location`
    # header that contains the session URI. The session URI is pre-authorized
    # for 7 days — the client PUTs chunks to it without additional auth.
    # Docs: https://cloud.google.com/storage/docs/performing-resumable-uploads
    headers =
      [
        {"content-type", "application/json; charset=UTF-8"},
        {"x-upload-content-type", content_type}
      ]
      |> maybe_put_header("x-upload-content-length", content_length)

    case request(:post, init_url, headers: headers, body: "{}") do
      {:ok, %{status: status, headers: resp_headers}} when status in 200..299 ->
        case find_header(resp_headers, "location") do
          nil -> {:error, {:gcs_error, status, :missing_session_uri}}
          session_uri -> {:ok, %{upload_url: session_uri, object_key: key}}
        end

      {:ok, resp} ->
        {:error, {:gcs_error, resp.status, resp.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def object_info(key) do
    key = normalize_key(key)
    url = "#{@base_url}/storage/v1/b/#{bucket()}/o/#{encode_object_name(key)}?fields=size"

    case request(:get, url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, %{"size" => size}} when is_binary(size) ->
            {:ok, %{size: String.to_integer(size)}}

          {:ok, %{"size" => size}} when is_integer(size) ->
            {:ok, %{size: size}}

          _ ->
            {:error, :invalid_metadata}
        end

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, resp} ->
        {:error, {:gcs_error, resp.status, resp.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  List objects under a key prefix. Used by the PDF chunk poller to enumerate
  Vision's async output JSON files under `ocr-output/<material>/cN/`.

  Returns `{:ok, [key1, key2, ...]}` — keys are returned as object names
  (no bucket prefix). Non-recursive semantics: GCS treats all `/` as
  literal so any depth under the prefix is returned.
  """
  def list_objects(prefix) do
    prefix = normalize_key(prefix)

    url =
      "#{@base_url}/storage/v1/b/#{bucket()}/o?prefix=#{URI.encode_www_form(prefix)}&fields=items(name)"

    case request(:get, url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, %{"items" => items}} when is_list(items) ->
            {:ok, Enum.map(items, & &1["name"])}

          {:ok, _} ->
            {:ok, []}

          _ ->
            {:error, :invalid_metadata}
        end

      {:ok, resp} ->
        {:error, {:gcs_error, resp.status, resp.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(method, url, opts \\ []) do
    headers =
      [{"authorization", "Bearer #{fetch_token!()}"}] ++
        Keyword.get(opts, :headers, [])

    req_opts =
      [method: method, url: url, headers: headers, decode_body: false, finch: FunSheep.Finch]
      |> maybe_put(:body, Keyword.get(opts, :body))

    Req.request(req_opts)
  end

  defp maybe_put(opts, _k, nil), do: opts
  defp maybe_put(opts, k, v), do: Keyword.put(opts, k, v)

  defp maybe_put_header(headers, _k, nil), do: headers

  defp maybe_put_header(headers, k, v) when is_integer(v),
    do: headers ++ [{k, Integer.to_string(v)}]

  defp maybe_put_header(headers, k, v), do: headers ++ [{k, to_string(v)}]

  # Req lower-cases response header names and returns them as a list of
  # 2-tuples keyed by lowercased name. `Req.get_header/2` also works but
  # we've got raw headers here from the map form, so do a case-insensitive
  # lookup by hand.
  defp find_header(headers, name) when is_list(headers) do
    lname = String.downcase(name)

    Enum.find_value(headers, fn
      {k, v} when is_binary(k) -> if String.downcase(k) == lname, do: to_string(v)
      _ -> nil
    end)
  end

  defp find_header(headers, name) when is_map(headers) do
    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(to_string(k)) == String.downcase(name), do: value_to_string(v)
    end)
  end

  defp value_to_string([v | _]), do: to_string(v)
  defp value_to_string(v), do: to_string(v)

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
