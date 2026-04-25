defmodule FunSheep.Workers.EbookExtractWorkerTest do
  @moduledoc """
  Tests for EbookExtractWorker.

  Strategy: use the Local storage backend (automatically active in test env)
  so we can store fixture EPUB bytes and exercise the real worker logic.
  We use Oban's :inline testing mode so jobs run synchronously.
  """

  use FunSheep.DataCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  alias FunSheep.{Content, Storage}
  alias FunSheep.Workers.EbookExtractWorker

  import FunSheep.ContentFixtures
  alias FunSheep.EbookFixtures

  # Store a fixture EPUB in storage and create an UploadedMaterial pointing to it.
  defp setup_material(epub_bytes, opts \\ []) do
    batch_id = Ecto.UUID.generate()
    file_name = Keyword.get(opts, :file_name, "test_book.epub")
    key = "staging/#{batch_id}/#{file_name}"

    {:ok, _} = Storage.put(key, epub_bytes, content_type: "application/epub+zip")

    material =
      create_uploaded_material(%{
        file_path: key,
        file_name: file_name,
        file_type: "application/epub+zip",
        file_size: byte_size(epub_bytes),
        batch_id: batch_id
      })

    on_exit(fn -> Storage.delete(key) end)
    material
  end

  describe "perform/1 — valid EPUB 2" do
    test "marks material as completed after successful extraction" do
      bytes = EbookFixtures.minimal_epub2_bytes(title: "Test Biology Book")
      material = setup_material(bytes)

      assert :ok = perform_job(EbookExtractWorker, %{"material_id" => material.id})

      updated = Content.get_uploaded_material!(material.id)
      assert updated.ocr_status == :completed
      assert updated.ocr_error == nil
    end

    test "creates OcrPage records from spine items" do
      chapter_text = "The mitochondria is the powerhouse of the cell."
      bytes = EbookFixtures.minimal_epub2_bytes(chapter_text: chapter_text)
      material = setup_material(bytes)

      assert :ok = perform_job(EbookExtractWorker, %{"material_id" => material.id})

      pages = Content.list_ocr_pages_by_material(material.id)
      assert length(pages) >= 1

      all_text = Enum.map_join(pages, " ", & &1.extracted_text)
      assert String.contains?(all_text, "mitochondria")
    end

    test "persists ebook_metadata on the material" do
      bytes = EbookFixtures.minimal_epub2_bytes(title: "Chemistry 101", author: "Dr. Smith")
      material = setup_material(bytes)

      assert :ok = perform_job(EbookExtractWorker, %{"material_id" => material.id})

      updated = Content.get_uploaded_material!(material.id)
      assert updated.ebook_metadata != nil
      assert updated.ebook_metadata["title"] == "Chemistry 101"
    end

    test "OcrPage page_number starts at 1" do
      bytes = EbookFixtures.minimal_epub2_bytes()
      material = setup_material(bytes)

      assert :ok = perform_job(EbookExtractWorker, %{"material_id" => material.id})

      pages = Content.list_ocr_pages_by_material(material.id)
      page_numbers = Enum.map(pages, & &1.page_number)
      assert 1 in page_numbers
    end

    test "stores toc in ebook_metadata when TOC is present" do
      bytes = EbookFixtures.minimal_epub2_bytes()
      material = setup_material(bytes)

      assert :ok = perform_job(EbookExtractWorker, %{"material_id" => material.id})

      # Oban is in :inline mode in tests — the TOC import job runs immediately.
      # Verify the side-effect: ebook_metadata should include the toc key.
      updated = Content.get_uploaded_material!(material.id)
      assert updated.ebook_metadata != nil
      assert Map.has_key?(updated.ebook_metadata, "toc")
      toc = updated.ebook_metadata["toc"]
      assert is_list(toc)
      assert length(toc) >= 1
    end
  end

  describe "perform/1 — DRM-protected EPUB" do
    test "marks material as failed with DRM message and does not retry" do
      bytes = EbookFixtures.drm_epub_bytes()
      material = setup_material(bytes)

      # Should return :ok (no retry) even though DRM was detected
      assert :ok = perform_job(EbookExtractWorker, %{"material_id" => material.id})

      updated = Content.get_uploaded_material!(material.id)
      assert updated.ocr_status == :failed
      assert updated.ocr_error =~ "DRM"
    end

    test "does not create any OcrPage records for DRM EPUBs" do
      bytes = EbookFixtures.drm_epub_bytes()
      material = setup_material(bytes)

      perform_job(EbookExtractWorker, %{"material_id" => material.id})

      pages = Content.list_ocr_pages_by_material(material.id)
      assert pages == []
    end
  end

  describe "perform/1 — corrupt EPUB" do
    test "marks material as failed for unparseable EPUBs" do
      bytes = EbookFixtures.corrupt_epub_bytes()
      material = setup_material(bytes)

      # Corrupt EPUBs return {:error, reason} which Oban will retry
      result = perform_job(EbookExtractWorker, %{"material_id" => material.id})
      assert match?(:ok, result) or match?({:error, _}, result)

      updated = Content.get_uploaded_material!(material.id)
      # Either failed or still processing (if Oban would retry)
      assert updated.ocr_status in [:failed, :processing]
    end
  end

  describe "perform/1 — idempotency" do
    test "skips processing for already-completed materials" do
      bytes = EbookFixtures.minimal_epub2_bytes()
      material = setup_material(bytes)

      # First run
      assert :ok = perform_job(EbookExtractWorker, %{"material_id" => material.id})

      # Set up and complete manually to simulate completed state
      updated = Content.get_uploaded_material!(material.id)
      assert updated.ocr_status == :completed

      # Second run — should skip and return :ok
      assert :ok = perform_job(EbookExtractWorker, %{"material_id" => material.id})
    end
  end
end
