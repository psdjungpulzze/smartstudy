defmodule FunSheep.OCR.GoogleVision do
  @moduledoc """
  Google Cloud Vision OCR client.
  Uses TEXT_DETECTION and DOCUMENT_TEXT_DETECTION APIs.
  """

  @base_url "https://vision.googleapis.com/v1"

  # Vision async PDF caps we enforce at the call site. Each file can be
  # up to 2000 pages per Google's public docs, but throughput and output
  # size quality suffer long before that — 200-page chunks keep each
  # operation under ~5 minutes of wall clock, so a Cloud Run worker
  # restart while one chunk is mid-flight costs at most one chunk re-poll.
  @max_chunk_pages 2000
  def max_chunk_pages, do: @max_chunk_pages

  @doc """
  Detect text from base64-encoded image content.

  In dev/test mode with `:ocr_mock` enabled, returns a mock response
  without calling the actual API.
  """
  def detect_text(image_content, opts \\ []) do
    if Application.get_env(:fun_sheep, :ocr_mock, false) do
      mock_detect_text(image_content)
    else
      call_vision_api(image_content, "DOCUMENT_TEXT_DETECTION", opts)
    end
  end

  @doc """
  Detect text from an object already in Cloud Storage.

  Sends only the `gs://` URI — Vision reads the object server-side via
  Google's internal network. The request body is a few hundred bytes
  instead of several MB of base64, which eliminates Finch socket pressure
  when many OCR jobs run concurrently.

  Authenticates with OAuth (Goth/metadata server) rather than the API key
  used by `detect_text/2`, because `gcsImageUri` on a private bucket
  requires the caller's identity to have `storage.objects.get` on the
  bucket — API-key callers are treated as anonymous and would 403.
  """
  def detect_text_from_gcs(gcs_uri) when is_binary(gcs_uri) do
    if Application.get_env(:fun_sheep, :ocr_mock, false) do
      mock_detect_text(gcs_uri)
    else
      call_vision_api_gcs(gcs_uri, "DOCUMENT_TEXT_DETECTION")
    end
  end

  @doc """
  Detect text from a file on disk. Reads and base64-encodes the file
  before sending to the Vision API.
  """
  def detect_text_from_file(file_path) do
    case File.read(file_path) do
      {:ok, content} -> detect_text(Base.encode64(content))
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Kick off an async PDF OCR operation for `gcs_uri` (e.g. `gs://bucket/path.pdf`).

  Vision's `files:asyncBatchAnnotate` endpoint runs out-of-band and writes
  output JSONs into the GCS prefix given in `output_prefix`. Each output
  file contains up to `batch_size` pages of annotations.

  Returns `{:ok, operation_name}` (e.g. `"operations/aUhj..."`) that you poll
  with `fetch_operation/1`.

  In `:ocr_mock` mode returns a synthetic operation name that `fetch_operation/1`
  will report as already `:done` — this keeps the test suite independent of
  Vision availability.
  """
  def start_pdf_async(gcs_uri, opts \\ []) when is_binary(gcs_uri) do
    output_prefix = Keyword.fetch!(opts, :output_prefix)
    batch_size = Keyword.get(opts, :batch_size, 20)
    mime_type = Keyword.get(opts, :mime_type, "application/pdf")

    if Application.get_env(:fun_sheep, :ocr_mock, false) do
      # Deterministic fake operation name so tests can map back to the input.
      op = "operations/mock-" <> Base.url_encode64(:crypto.hash(:sha256, gcs_uri), padding: false)
      mock_remember_operation(op, gcs_uri, output_prefix, batch_size)
      {:ok, op}
    else
      body = %{
        "requests" => [
          %{
            "inputConfig" => %{
              "gcsSource" => %{"uri" => gcs_uri},
              "mimeType" => mime_type
            },
            "features" => [%{"type" => "DOCUMENT_TEXT_DETECTION"}],
            "outputConfig" => %{
              "gcsDestination" => %{"uri" => output_prefix},
              "batchSize" => batch_size
            }
          }
        ]
      }

      case fetch_oauth_token() do
        {:ok, token} ->
          headers = [{"authorization", "Bearer #{token}"}]

          case vision_post("#{@base_url}/files:asyncBatchAnnotate", body, headers) do
            {:ok, %{status: 200, body: %{"name" => name}}} ->
              {:ok, name}

            {:ok, %{status: status, body: resp_body}} ->
              {:error, {status, resp_body}}

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, {:oauth_token_error, reason}}
      end
    end
  end

  @doc """
  Poll an async operation. Returns one of:

    * `{:ok, :running}` — still in progress; caller should snooze and retry
    * `{:ok, :done}` — operation finished; read results from the
      `output_prefix` you passed to `start_pdf_async/2`
    * `{:error, reason}` — terminal failure (Vision reported an error
      in the operation body, or the HTTP call itself failed)

  We deliberately don't return the operation's embedded response — it
  contains pointers to the output files but the chunk poller already
  knows its own `output_prefix` and just lists objects under it. That
  keeps polling idempotent across Vision's internal schema tweaks.
  """
  def fetch_operation(name) when is_binary(name) do
    if Application.get_env(:fun_sheep, :ocr_mock, false) do
      mock_fetch_operation(name)
    else
      case fetch_oauth_token() do
        {:ok, token} ->
          headers = [{"authorization", "Bearer #{token}"}]

          case Req.get("#{@base_url}/#{name}",
                 headers: headers,
                 connect_options: [timeout: 10_000],
                 receive_timeout: 30_000,
                 retry: :transient,
                 max_retries: 3
               ) do
            {:ok, %{status: 200, body: %{"done" => true, "error" => error}}}
            when not is_nil(error) ->
              {:error, error}

            {:ok, %{status: 200, body: %{"done" => true}}} ->
              {:ok, :done}

            {:ok, %{status: 200, body: %{"done" => _} = _resp}} ->
              # `done` explicitly false or missing → still running.
              {:ok, :running}

            {:ok, %{status: 200, body: _}} ->
              {:ok, :running}

            {:ok, %{status: status, body: body}} ->
              {:error, {status, body}}

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, {:oauth_token_error, reason}}
      end
    end
  end

  @doc """
  Parse one of Vision's async output JSON files. Each file covers up to
  `batchSize` pages of the source PDF and has the shape:

      %{"responses" => [
         %{"context" => %{"pageNumber" => 1}, "fullTextAnnotation" => %{...}},
         %{"context" => %{"pageNumber" => 2}, ...},
         ...
      ]}

  Returns a list of `%{page_number, text, blocks, pages, error}` — one entry
  per page. `page_number` is 1-indexed *within the source PDF the op was
  submitted against*; callers that submitted a chunk starting at page `N`
  must offset by `N - 1` to get global page numbers.
  """
  def parse_async_output(%{"responses" => responses}) when is_list(responses) do
    Enum.map(responses, &parse_one_async_response/1)
  end

  def parse_async_output(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, parsed} -> parse_async_output(parsed)
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  def parse_async_output(_), do: []

  defp parse_one_async_response(%{"context" => ctx} = resp) do
    page_number = ctx["pageNumber"] || 1
    base = parse_one_async_response(Map.delete(resp, "context"))
    Map.put(base, :page_number, page_number)
  end

  defp parse_one_async_response(%{"fullTextAnnotation" => annotation}) do
    %{
      page_number: 1,
      text: annotation["text"] || "",
      pages: parse_pages(annotation["pages"] || []),
      blocks: parse_blocks(annotation["pages"] || []),
      error: nil
    }
  end

  defp parse_one_async_response(%{"error" => err}) do
    %{
      page_number: 1,
      text: "",
      pages: [],
      blocks: [],
      error: format_async_error(err)
    }
  end

  defp parse_one_async_response(_) do
    %{page_number: 1, text: "", pages: [], blocks: [], error: "empty response"}
  end

  defp format_async_error(%{"message" => msg}) when is_binary(msg), do: msg
  defp format_async_error(err), do: inspect(err)

  defp call_vision_api(base64_content, feature_type, _opts) do
    api_key = Application.get_env(:fun_sheep, :google_vision_api_key)

    body = %{
      "requests" => [
        %{
          "image" => %{"content" => base64_content},
          "features" => [%{"type" => feature_type}]
        }
      ]
    }

    case vision_post("#{@base_url}/images:annotate?key=#{api_key}", body, []) do
      {:ok, %{status: 200, body: resp}} -> parse_response(resp)
      {:ok, %{status: status, body: resp_body}} -> {:error, {status, resp_body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp call_vision_api_gcs(gcs_uri, feature_type) do
    body = %{
      "requests" => [
        %{
          "image" => %{"source" => %{"gcsImageUri" => gcs_uri}},
          "features" => [%{"type" => feature_type}]
        }
      ]
    }

    case fetch_oauth_token() do
      {:ok, token} ->
        headers = [{"authorization", "Bearer #{token}"}]

        case vision_post("#{@base_url}/images:annotate", body, headers) do
          {:ok, %{status: 200, body: resp}} -> parse_response(resp)
          {:ok, %{status: status, body: resp_body}} -> {:error, {status, resp_body}}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, {:oauth_token_error, reason}}
    end
  end

  # Use Req's default Finch pool — custom pool experiments (HTTP/1 pinned
  # then HTTP/2 multiplexed) both hit Erlang/OTP rejecting `sndbuf` as an
  # SSL connect option on Cloud Run. The default pool works well enough
  # that in-process retries (3 × transient) combined with Oban snooze
  # (5 max_attempts) are the real lever for getting success rate to >90%.
  defp vision_post(url, body, headers) do
    Req.post(url,
      json: body,
      headers: headers,
      connect_options: [timeout: 10_000],
      receive_timeout: 60_000,
      retry: :transient,
      max_retries: 3,
      retry_delay: fn attempt -> :timer.seconds(2 * (attempt + 1)) end
    )
  end

  defp fetch_oauth_token do
    goth_name =
      Application.get_env(:fun_sheep, FunSheep.Storage.GCS)[:goth_name] || FunSheep.Goth

    case Goth.fetch(goth_name) do
      {:ok, %{token: token}} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def parse_response(%{"responses" => [%{"fullTextAnnotation" => annotation} | _]}) do
    {:ok,
     %{
       text: annotation["text"],
       pages: parse_pages(annotation["pages"] || []),
       blocks: parse_blocks(annotation["pages"] || [])
     }}
  end

  def parse_response(%{"responses" => [%{"error" => error} | _]}), do: {:error, error}
  def parse_response(_), do: {:error, :no_text_detected}

  defp parse_pages(pages) do
    Enum.map(pages, fn page ->
      %{
        width: page["width"],
        height: page["height"],
        blocks: length(page["blocks"] || [])
      }
    end)
  end

  defp parse_blocks(pages) do
    pages
    |> Enum.flat_map(fn page -> page["blocks"] || [] end)
    |> Enum.map(fn block ->
      %{
        text: extract_block_text(block),
        bounding_box: block["boundingBox"],
        block_type: block["blockType"],
        confidence: block["confidence"]
      }
    end)
  end

  defp extract_block_text(block) do
    (block["paragraphs"] || [])
    |> Enum.flat_map(fn p -> p["words"] || [] end)
    |> Enum.map(fn w ->
      (w["symbols"] || []) |> Enum.map(& &1["text"]) |> Enum.join()
    end)
    |> Enum.join(" ")
  end

  # ── Mocks ─────────────────────────────────────────────────────────────
  # Synthetic async operations for tests. `start_pdf_async` records the
  # operation; `fetch_operation` returns :done immediately; the caller is
  # expected to write mock output JSON to GCS itself via the Local backend.

  defp mock_remember_operation(op, gcs_uri, output_prefix, batch_size) do
    :persistent_term.put(
      {__MODULE__, :mock_operation, op},
      %{gcs_uri: gcs_uri, output_prefix: output_prefix, batch_size: batch_size}
    )
  end

  defp mock_fetch_operation("operations/mock-" <> _ = op) do
    # In mock mode, the dispatch step already wrote fake output JSON to
    # the Local storage backend; the poller will read it. Report done.
    _ = :persistent_term.get({__MODULE__, :mock_operation, op}, nil)
    {:ok, :done}
  end

  defp mock_fetch_operation(_), do: {:ok, :done}

  @doc false
  def mock_operation_info(op), do: :persistent_term.get({__MODULE__, :mock_operation, op}, nil)

  # Mock for development/testing
  defp mock_detect_text(_content) do
    {:ok,
     %{
       text:
         "Sample extracted text from OCR.\nChapter 1: Introduction\nQuestion 1: What is biology?\nAnswer: Biology is the study of life.",
       pages: [%{width: 612, height: 792, blocks: 3}],
       blocks: [
         %{
           text: "Sample extracted text from OCR.",
           bounding_box: nil,
           block_type: "TEXT",
           confidence: 0.98
         },
         %{
           text: "Chapter 1: Introduction",
           bounding_box: nil,
           block_type: "TEXT",
           confidence: 0.97
         },
         %{
           text: "Question 1: What is biology? Answer: Biology is the study of life.",
           bounding_box: nil,
           block_type: "TEXT",
           confidence: 0.95
         }
       ]
     }}
  end
end
