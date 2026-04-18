defmodule FunSheep.OCR.Pipeline do
  @moduledoc """
  OCR processing pipeline:
  1. Read uploaded file from storage
  2. Split PDF into pages (if PDF) -- future enhancement
  3. Send each page to Google Vision OCR
  4. Store extracted text + metadata per page in ocr_pages table
  5. Update material ocr_status
  """

  alias FunSheep.{Content, Storage}
  alias FunSheep.OCR.GoogleVision

  @doc """
  Process a material by its ID.

  Reads the file from storage, runs OCR, stores the results as OcrPage
  records, and updates the material's `ocr_status` accordingly.
  """
  def process(material_id) do
    material = Content.get_uploaded_material!(material_id)

    Content.update_uploaded_material(material, %{ocr_status: :processing})

    case do_process(material) do
      {:ok, pages} ->
        Content.update_uploaded_material(material, %{ocr_status: :completed})
        {:ok, pages}

      {:error, reason} ->
        Content.update_uploaded_material(material, %{ocr_status: :failed})
        {:error, reason}
    end
  end

  defp do_process(material) do
    # For now, treat everything as a single "page"
    # In production, PDFs would be split into individual page images
    case Storage.get(material.file_path) do
      {:ok, content} ->
        case GoogleVision.detect_text(Base.encode64(content)) do
          {:ok, result} ->
            page = create_ocr_page(material, 1, result)
            {:ok, [page]}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  defp create_ocr_page(material, page_number, ocr_result) do
    attrs = %{
      material_id: material.id,
      page_number: page_number,
      extracted_text: ocr_result.text,
      bounding_boxes: %{"blocks" => ocr_result.blocks},
      images: %{"pages" => ocr_result.pages}
    }

    {:ok, page} = Content.create_ocr_page(attrs)
    page
  end
end
