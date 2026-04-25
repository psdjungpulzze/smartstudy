defmodule FunSheep.Workers.MobiConvertWorker do
  @moduledoc """
  Oban worker that converts a MOBI or AZW3 file to EPUB via calibre's
  `ebook-convert` CLI, then hands the resulting EPUB to `EbookExtractWorker`
  for text and TOC extraction.

  Invoked by `OCRMaterialWorker` when format detection identifies a MOBI or
  AZW3 file.

  Failure scenarios:
  - calibre not installed → marks material as `:failed` with an actionable message
  - DRM detected → marks material as `:failed` (no retry)
  - Conversion error → returns `{:error, reason}` so Oban retries

  Job args:
  - `"uploaded_material_id"` — UUID of the UploadedMaterial to convert
  """

  use Oban.Worker, queue: :ebook, max_attempts: 2

  alias FunSheep.Content
  alias FunSheep.Ebook.{FormatDetector, MobiConverter}
  alias FunSheep.Storage

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"uploaded_material_id" => material_id}}) do
    material = Content.get_uploaded_material!(material_id)

    if material.ocr_status == :completed do
      Logger.info("[MobiConvert] Material #{material_id} already completed, skipping")
      :ok
    else
      do_convert(material)
    end
  end

  defp do_convert(material) do
    unless MobiConverter.calibre_available?() do
      Logger.error("[MobiConvert] calibre is not installed — cannot convert MOBI/AZW3")

      Content.update_uploaded_material(material, %{
        ocr_status: :failed,
        ocr_error:
          "MOBI/AZW3 conversion requires calibre, which is not installed on this server. " <>
            "Please convert your file to EPUB before uploading."
      })

      # Return :ok — calibre absence won't fix itself on retry.
      return_ok()
    else
      {:ok, _} =
        Content.update_uploaded_material(material, %{ocr_status: :processing, ocr_error: nil})

      do_download_and_convert(material)
    end
  end

  defp do_download_and_convert(material) do
    tmp_dir = Path.join(System.tmp_dir!(), "funsheep_mobi_#{material.id}")
    File.mkdir_p!(tmp_dir)

    try do
      case Storage.get(material.file_path) do
        {:ok, bytes} ->
          ext =
            (material.file_name || material.file_path || "")
            |> Path.extname()
            |> String.downcase()

          input_path = Path.join(tmp_dir, "source#{ext}")
          File.write!(input_path, bytes)
          run_conversion(material, input_path, tmp_dir)

        {:error, reason} ->
          Logger.error("[MobiConvert] Download failed material=#{material.id}: #{inspect(reason)}")

          Content.update_uploaded_material(material, %{
            ocr_status: :failed,
            ocr_error: "Download failed: #{inspect(reason)}"
          })

          {:error, {:download_failed, reason}}
      end
    after
      File.rm_rf(tmp_dir)
    end
  end

  defp run_conversion(material, input_path, tmp_dir) do
    # Verify format before calling calibre (cheap sanity check)
    detected =
      case File.open(input_path, [:read, :binary]) do
        {:ok, io} ->
          bytes = IO.read(io, 16)
          File.close(io)
          ext = input_path |> Path.extname() |> String.trim_leading(".") |> String.downcase()
          FormatDetector.detect(bytes, ext)

        {:error, _} ->
          :unknown
      end

    unless detected in [:mobi, :azw3] do
      Logger.warning(
        "[MobiConvert] Format detection returned #{detected} for material #{material.id} — proceeding anyway"
      )
    end

    case MobiConverter.convert(input_path, tmp_dir) do
      {:ok, epub_path} ->
        Logger.info("[MobiConvert] Conversion succeeded for material #{material.id}")
        enqueue_epub_extraction(material, epub_path, tmp_dir)

      {:error, :drm_protected} ->
        Logger.warning("[MobiConvert] DRM detected material=#{material.id}")

        Content.update_uploaded_material(material, %{
          ocr_status: :failed,
          ocr_error:
            "This Kindle file is DRM-protected. Only DRM-free Kindle files can be uploaded."
        })

        # :ok — DRM will not resolve on retry
        return_ok()

      {:error, :calibre_not_found} ->
        Content.update_uploaded_material(material, %{
          ocr_status: :failed,
          ocr_error: "MOBI conversion tool (calibre) is not available on this server."
        })

        return_ok()

      {:error, reason} ->
        Logger.error(
          "[MobiConvert] Conversion failed material=#{material.id}: #{inspect(reason)}"
        )

        Content.update_uploaded_material(material, %{
          ocr_status: :failed,
          ocr_error: "eBook conversion timed out or failed. The file may be too large or malformed."
        })

        {:error, reason}
    end
  end

  # After successful calibre conversion, upload the EPUB back to storage and
  # enqueue EbookExtractWorker to process it like any other EPUB.
  defp enqueue_epub_extraction(material, epub_path, _tmp_dir) do
    case File.read(epub_path) do
      {:ok, epub_bytes} ->
        # Store the converted EPUB under a new key derived from the original
        epub_storage_key =
          "#{Path.dirname(material.file_path)}/converted_#{material.id}.epub"

        case Storage.put(epub_storage_key, epub_bytes) do
          {:ok, _} ->
            # Update material to reference the EPUB file so EbookExtractWorker
            # can download it via the standard Storage.get path
            {:ok, updated_material} =
              Content.update_uploaded_material(material, %{
                file_path: epub_storage_key,
                material_format: "epub"
              })

            %{"material_id" => updated_material.id}
            |> FunSheep.Workers.EbookExtractWorker.new()
            |> Oban.insert()

            :ok

          {:error, reason} ->
            Logger.error(
              "[MobiConvert] Failed to upload converted EPUB material=#{material.id}: #{inspect(reason)}"
            )

            Content.update_uploaded_material(material, %{
              ocr_status: :failed,
              ocr_error: "Failed to store converted eBook. Please try again."
            })

            {:error, {:storage_put_failed, reason}}
        end

      {:error, reason} ->
        Logger.error("[MobiConvert] Cannot read converted EPUB file: #{inspect(reason)}")

        Content.update_uploaded_material(material, %{
          ocr_status: :failed,
          ocr_error: "Conversion produced an unreadable file."
        })

        {:error, {:epub_unreadable, reason}}
    end
  end

  # Tiny helper to keep clauses readable. Returns :ok for Oban.
  defp return_ok, do: :ok
end
