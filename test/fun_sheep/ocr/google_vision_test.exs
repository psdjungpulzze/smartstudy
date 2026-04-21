defmodule FunSheep.OCR.GoogleVisionTest do
  use ExUnit.Case, async: true

  alias FunSheep.OCR.GoogleVision

  setup do
    Application.put_env(:fun_sheep, :ocr_mock, true)

    on_exit(fn ->
      Application.put_env(:fun_sheep, :ocr_mock, true)
    end)

    :ok
  end

  describe "detect_text/2 (mock mode)" do
    test "returns {:ok, result} with expected structure" do
      assert {:ok, result} = GoogleVision.detect_text("base64encodedcontent")

      assert is_binary(result.text)
      assert result.text =~ "Sample extracted text"

      assert is_list(result.pages)
      assert length(result.pages) > 0

      page = hd(result.pages)
      assert is_integer(page.width)
      assert is_integer(page.height)
      assert is_integer(page.blocks)

      assert is_list(result.blocks)
      assert length(result.blocks) > 0

      block = hd(result.blocks)
      assert is_binary(block.text)
      assert is_binary(block.block_type)
      assert is_number(block.confidence)
    end
  end

  describe "parse_response/1" do
    test "parses a full Vision API response with fullTextAnnotation" do
      api_response = %{
        "responses" => [
          %{
            "fullTextAnnotation" => %{
              "text" => "Hello World",
              "pages" => [
                %{
                  "width" => 100,
                  "height" => 200,
                  "blocks" => [
                    %{
                      "blockType" => "TEXT",
                      "confidence" => 0.99,
                      "boundingBox" => %{"vertices" => [%{"x" => 0, "y" => 0}]},
                      "paragraphs" => [
                        %{
                          "words" => [
                            %{
                              "symbols" => [
                                %{"text" => "H"},
                                %{"text" => "i"}
                              ]
                            }
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          }
        ]
      }

      assert {:ok, result} = GoogleVision.parse_response(api_response)
      assert result.text == "Hello World"
      assert length(result.pages) == 1
      assert hd(result.pages).width == 100
      assert hd(result.pages).height == 200
      assert hd(result.pages).blocks == 1
      assert length(result.blocks) == 1
      assert hd(result.blocks).text == "Hi"
      assert hd(result.blocks).confidence == 0.99
    end

    test "returns error for API error response" do
      api_response = %{
        "responses" => [
          %{
            "error" => %{"code" => 3, "message" => "Bad image"}
          }
        ]
      }

      assert {:error, %{"code" => 3}} = GoogleVision.parse_response(api_response)
    end

    test "returns :no_text_detected for empty response" do
      assert {:error, :no_text_detected} = GoogleVision.parse_response(%{"responses" => [%{}]})
    end

    test "returns :no_text_detected for unexpected format" do
      assert {:error, :no_text_detected} = GoogleVision.parse_response(%{})
    end
  end

  describe "detect_text_from_file/1" do
    test "returns error for non-existent file" do
      assert {:error, :enoent} = GoogleVision.detect_text_from_file("/tmp/nonexistent_file.png")
    end

    test "reads file and processes through mock OCR" do
      # Create a temporary test file
      tmp_path =
        Path.join(System.tmp_dir!(), "ocr_test_#{System.unique_integer([:positive])}.txt")

      File.write!(tmp_path, "test image content")

      on_exit(fn -> File.rm(tmp_path) end)

      assert {:ok, result} = GoogleVision.detect_text_from_file(tmp_path)
      assert is_binary(result.text)
    end
  end

  describe "start_pdf_async/2 (mock mode)" do
    test "returns a deterministic mock operation name" do
      {:ok, op1} =
        GoogleVision.start_pdf_async("gs://bucket/a.pdf", output_prefix: "gs://bucket/out/")

      {:ok, op2} =
        GoogleVision.start_pdf_async("gs://bucket/a.pdf", output_prefix: "gs://bucket/out/")

      assert op1 == op2
      assert String.starts_with?(op1, "operations/mock-")

      {:ok, op3} =
        GoogleVision.start_pdf_async("gs://bucket/b.pdf", output_prefix: "gs://bucket/out/")

      refute op1 == op3
    end

    test "remembers operation metadata for later lookup" do
      {:ok, op} =
        GoogleVision.start_pdf_async("gs://bucket/x.pdf", output_prefix: "gs://bucket/out/x/")

      info = GoogleVision.mock_operation_info(op)
      assert info.gcs_uri == "gs://bucket/x.pdf"
      assert info.output_prefix == "gs://bucket/out/x/"
    end
  end

  describe "fetch_operation/1 (mock mode)" do
    test "reports done for any mock operation name" do
      {:ok, op} =
        GoogleVision.start_pdf_async("gs://bucket/y.pdf", output_prefix: "gs://bucket/out/")

      assert {:ok, :done} = GoogleVision.fetch_operation(op)
    end
  end

  describe "parse_async_output/1" do
    test "parses multi-page fullTextAnnotation output with per-page text" do
      raw = %{
        "responses" => [
          %{
            "context" => %{"pageNumber" => 1},
            "fullTextAnnotation" => %{
              "text" => "Page one text",
              "pages" => [
                %{
                  "width" => 612,
                  "height" => 792,
                  "blocks" => [
                    %{
                      "blockType" => "TEXT",
                      "confidence" => 0.9,
                      "paragraphs" => [
                        %{
                          "words" => [%{"symbols" => [%{"text" => "P"}, %{"text" => "1"}]}]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          },
          %{
            "context" => %{"pageNumber" => 2},
            "fullTextAnnotation" => %{
              "text" => "Page two text",
              "pages" => []
            }
          },
          %{
            "context" => %{"pageNumber" => 3},
            "error" => %{"code" => 3, "message" => "bad image"}
          }
        ]
      }

      results = GoogleVision.parse_async_output(raw)
      assert length(results) == 3
      [p1, p2, p3] = results

      assert p1.page_number == 1
      assert p1.text == "Page one text"
      assert p3.page_number == 3
      assert p3.error =~ "bad image"
      # Error pages carry no text so the poller marks them :failed.
      assert p3.text == ""
      assert p2.page_number == 2
      assert p2.text == "Page two text"
    end

    test "accepts raw JSON binary input" do
      raw_json =
        ~s({"responses":[{"context":{"pageNumber":42},"fullTextAnnotation":{"text":"hi","pages":[]}}]})

      [entry] = GoogleVision.parse_async_output(raw_json)
      assert entry.page_number == 42
      assert entry.text == "hi"
    end
  end
end
