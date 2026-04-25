defmodule FunSheep.Workers.EbookExtractWorker do
  @moduledoc """
  Oban worker that extracts text and TOC from an EPUB file.

  Invoked by OCRMaterialWorker when format detection identifies an EPUB.
  Downloads the EPUB from storage, parses it with EpubParser, persists the
  spine items as OcrPage rows (mirroring the PDF OCR pipeline), records
  the EPUB metadata on the UploadedMaterial, and enqueues EbookTocImportWorker
  to persist the navigation structure as a DiscoveredTOC candidate.

  DRM-protected EPUBs are failed permanently — no retry, no fake content.
  Other errors are returned as `{:error, reason}` so Oban retries.

  Job args:
    - `"material_id"` — UUID of the UploadedMaterial to process
  """

  use Oban.Worker, queue: :ebook, max_attempts: 3

  alias FunSheep.Content
  alias FunSheep.Ebook.EpubParser
  alias FunSheep.Storage

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"material_id" => material_id}}) do
    material = Content.get_uploaded_material!(material_id)

    if material.ocr_status == :completed do
      Logger.info("[EbookExtract] Material #{material_id} already completed, skipping")
      :ok
    else
      do_extract(material)
    end
  end

  defp do_extract(material) do
    {:ok, _} =
      Content.update_uploaded_material(material, %{ocr_status: :processing, ocr_error: nil})

    case download_to_tmp(material) do
      {:ok, local_path, cleanup} ->
        try do
          process_epub(material, local_path)
        after
          cleanup.()
        end

      {:error, reason} ->
        Logger.error("[EbookExtract] Download failed material=#{material.id}: #{inspect(reason)}")

        Content.update_uploaded_material(material, %{
          ocr_status: :failed,
          ocr_error: "Download failed: #{inspect(reason)}"
        })

        {:error, {:download_failed, reason}}
    end
  end

  defp process_epub(material, local_path) do
    case EpubParser.extract(local_path) do
      {:ok, %{metadata: metadata, toc: toc, spine_items: spine_items}} ->
        Logger.info(
          "[EbookExtract] Parsed EPUB material=#{material.id}: " <>
            "#{length(spine_items)} spine items, #{length(toc)} TOC entries"
        )

        # 1. Delete any previously extracted pages (idempotent on retry)
        Content.delete_ocr_pages_for_material(material.id)

        # 2. Create an OcrPage for each spine document
        upsert_spine_pages(material, spine_items)

        # 3. Persist metadata on the material and mark completed
        {:ok, _} =
          Content.update_uploaded_material(material, %{
            ebook_metadata: Map.merge(metadata, %{"toc" => toc}),
            ocr_status: :completed,
            ocr_error: nil
          })

        # 4. Enqueue TOC import if there are TOC entries
        if toc != [] do
          toc_serializable =
            Enum.map(toc, fn entry ->
              %{"title" => entry.title, "depth" => entry.depth, "href" => entry.href}
            end)

          %{
            "material_id" => material.id,
            "course_id" => material.course_id,
            "toc" => toc_serializable
          }
          |> FunSheep.Workers.EbookTocImportWorker.new()
          |> Oban.insert()
        end

        :ok

      {:error, :drm_protected} ->
        Logger.warning("[EbookExtract] DRM-protected EPUB material=#{material.id}")

        Content.update_uploaded_material(material, %{
          ocr_status: :failed,
          ocr_error: "DRM-protected EPUB: cannot extract text. Please use a DRM-free EPUB file."
        })

        # Return :ok so Oban does NOT retry — DRM is a permanent condition.
        :ok

      {:error, reason} ->
        Logger.error("[EbookExtract] Parse failed material=#{material.id}: #{inspect(reason)}")

        Content.update_uploaded_material(material, %{
          ocr_status: :failed,
          ocr_error: "EPUB parse error: #{inspect(reason)}"
        })

        {:error, reason}
    end
  end

  defp upsert_spine_pages(material, spine_items) do
    Enum.each(spine_items, fn item ->
      # page_number is 1-based; index is 0-based
      page_number = item.index + 1

      attrs = %{
        material_id: material.id,
        page_number: page_number,
        extracted_text: item.text,
        bounding_boxes: %{},
        images: %{},
        status: if(item.text in ["", nil], do: :failed, else: :completed),
        error: nil
      }

      case Content.upsert_ocr_page(attrs) do
        {_tag, _page} ->
          :ok

        {:error, cs} ->
          Logger.warning(
            "[EbookExtract] Failed to upsert page #{page_number} for material #{material.id}: #{inspect(cs.errors)}"
          )
      end
    end)
  end

  defp download_to_tmp(%{file_path: key, id: id}) do
    case Storage.get(key) do
      {:ok, bytes} ->
        tmp_dir = Path.join(System.tmp_dir!(), "funsheep_epub_#{id}")
        File.mkdir_p!(tmp_dir)
        local_path = Path.join(tmp_dir, "source.epub")
        File.write!(local_path, bytes)
        cleanup = fn -> File.rm_rf(tmp_dir) end
        {:ok, local_path, cleanup}

      {:error, reason} ->
        {:error, {:storage_get_failed, reason}}
    end
  end
end
