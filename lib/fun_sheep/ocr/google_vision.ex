defmodule FunSheep.OCR.GoogleVision do
  @moduledoc """
  Google Cloud Vision OCR client.
  Uses TEXT_DETECTION and DOCUMENT_TEXT_DETECTION APIs.
  """

  @base_url "https://vision.googleapis.com/v1"

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
  Detect text from a file on disk. Reads and base64-encodes the file
  before sending to the Vision API.
  """
  def detect_text_from_file(file_path) do
    case File.read(file_path) do
      {:ok, content} -> detect_text(Base.encode64(content))
      {:error, reason} -> {:error, reason}
    end
  end

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

    case Req.post("#{@base_url}/images:annotate?key=#{api_key}", json: body) do
      {:ok, %{status: 200, body: resp}} -> parse_response(resp)
      {:ok, %{status: status, body: resp_body}} -> {:error, {status, resp_body}}
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
