defmodule FunSheep.OCR.PipelineTest do
  use FunSheep.DataCase, async: false

  alias FunSheep.OCR.Pipeline
  alias FunSheep.{Content, Storage}

  import FunSheep.ContentFixtures

  setup do
    Application.put_env(:fun_sheep, :ocr_mock, true)

    on_exit(fn ->
      Application.put_env(:fun_sheep, :ocr_mock, true)
    end)

    :ok
  end

  describe "process/1" do
    test "processes a material and creates OCR page records" do
      material = create_uploaded_material()

      # Store a test file at the material's file_path
      Storage.put(material.file_path, "fake image content")

      on_exit(fn -> Storage.delete(material.file_path) end)

      assert {:ok, [page]} = Pipeline.process(material.id)

      assert page.material_id == material.id
      assert page.page_number == 1
      assert is_binary(page.extracted_text)
      assert page.extracted_text =~ "Sample extracted text"

      # Verify the material status was updated to completed
      updated_material = Content.get_uploaded_material!(material.id)
      assert updated_material.ocr_status == :completed
    end

    test "updates material status to completed on success" do
      material = create_uploaded_material()
      Storage.put(material.file_path, "fake image content")

      on_exit(fn -> Storage.delete(material.file_path) end)

      Pipeline.process(material.id)

      updated = Content.get_uploaded_material!(material.id)
      assert updated.ocr_status == :completed
    end

    test "creates OcrPage records that can be listed by material" do
      material = create_uploaded_material()
      Storage.put(material.file_path, "fake image content")

      on_exit(fn -> Storage.delete(material.file_path) end)

      Pipeline.process(material.id)

      pages = Content.list_ocr_pages_by_material(material.id)
      assert length(pages) == 1
      assert hd(pages).page_number == 1
    end

    test "updates material status to failed when file not found" do
      material = create_uploaded_material(%{file_path: "nonexistent/path.pdf"})

      assert {:error, {:fatal, {:file_read_error, _}}} = Pipeline.process(material.id)

      updated = Content.get_uploaded_material!(material.id)
      assert updated.ocr_status == :failed
    end
  end
end
