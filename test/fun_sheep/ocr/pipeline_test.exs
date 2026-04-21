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

    test "routes PDFs to async dispatch instead of running OCR synchronously" do
      material =
        create_uploaded_material(%{
          file_path: "test/#{Ecto.UUID.generate()}.pdf",
          file_name: "doc.pdf",
          file_type: "application/pdf"
        })

      # Pipeline enqueues the dispatcher; in :inline Oban mode the
      # dispatcher runs immediately. Manual mode here proves that the
      # Pipeline branches correctly without the inline chain polluting
      # the assertion.
      Oban.Testing.with_testing_mode(:manual, fn ->
        # Dispatch path returns :dispatched and enqueues the dispatch worker.
        # Pipeline does NOT touch OcrPage rows on the PDF path — that's the
        # poller's job after Vision completes.
        assert {:ok, :dispatched} = Pipeline.process(material.id)
        assert Content.list_ocr_pages_by_material(material.id) == []

        updated = Content.get_uploaded_material!(material.id)
        assert updated.ocr_status == :processing
      end)
    end
  end
end
