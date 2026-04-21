defmodule FunSheep.OCR.Pipeline do
  @moduledoc """
  OCR processing pipeline:
  1. Read uploaded file from storage
  2. Split PDF into pages (if PDF) -- future enhancement
  3. Send each page to Google Vision OCR
  4. Store extracted text + metadata per page in ocr_pages table
  5. Update material ocr_status
  """

  alias FunSheep.Content
  alias FunSheep.OCR.GoogleVision
  alias FunSheep.Storage.GCS

  require Logger

  @doc """
  Process a material by its ID.

  Reads the file from storage, runs OCR, stores the results as OcrPage
  records, and updates the material's `ocr_status` accordingly.
  """
  def process(material_id) do
    material = Content.get_uploaded_material!(material_id)

    Content.update_uploaded_material(material, %{ocr_status: :processing, ocr_error: nil})

    # Single-page model today: every retry rewrites the page record(s) from
    # scratch. When PDF splitting lands, switch to per-page upserts keyed on
    # (material_id, page_number) so already-completed pages aren't redone.
    Content.delete_ocr_pages_for_material(material.id)

    case do_process(material) do
      {:ok, pages} ->
        material_status = derive_material_status(pages)
        material_error = aggregate_error(pages)

        Content.update_uploaded_material(material, %{
          ocr_status: material_status,
          ocr_error: material_error
        })

        {:ok, pages}

      {:error, reason} ->
        formatted = format_error(reason)

        # Record the failure as a page so per-page UI has something to surface
        # and the unique-constraint slot is consumed (next retry deletes it).
        {:ok, _failed_page} =
          Content.create_ocr_page(%{
            material_id: material.id,
            page_number: 1,
            status: :failed,
            error: formatted
          })

        Content.update_uploaded_material(material, %{
          ocr_status: :failed,
          ocr_error: formatted
        })

        {:error, reason}
    end
  end

  # Derive the material-level status from its constituent pages. Used today
  # only with a single page, but ready for PDF splitting where some pages may
  # succeed while others fail.
  defp derive_material_status([]), do: :failed

  defp derive_material_status(pages) do
    statuses = Enum.map(pages, & &1.status)

    cond do
      Enum.all?(statuses, &(&1 == :completed)) -> :completed
      Enum.any?(statuses, &(&1 == :completed)) -> :partial
      true -> :failed
    end
  end

  # When any page failed, surface a one-line summary at the material level
  # (e.g. "3 of 8 pages failed"). For all-success cases, return nil so we
  # clear any stale error from a previous retry.
  defp aggregate_error(pages) do
    failed = Enum.filter(pages, &(&1.status == :failed))

    case {length(failed), length(pages)} do
      {0, _} ->
        nil

      {n, total} ->
        sample = failed |> List.first() |> Map.get(:error)
        "#{n} of #{total} page(s) failed: #{sample}"
    end
  end

  # Render an error term into a short, human-readable string we can surface in
  # the UI and store in the materials table. Vision API errors come back as a
  # `{status, body}` tuple where the body is a JSON map with a nested `error`
  # object — extract the message so users see "API key not valid" instead of
  # an opaque {400, %{...}}.
  defp format_error({status, %{"error" => %{"message" => msg}}}) when is_integer(status),
    do: "HTTP #{status}: #{msg}"

  defp format_error({status, %{"error" => error}}) when is_integer(status),
    do: "HTTP #{status}: #{inspect(error)}"

  defp format_error({:file_read_error, :not_found}),
    do: "File not found in storage"

  defp format_error({:file_read_error, reason}),
    do: "File read error: #{inspect(reason)}"

  defp format_error(:no_text_detected),
    do: "No text detected in image"

  defp format_error(reason) when is_binary(reason), do: reason

  defp format_error(reason), do: inspect(reason) |> String.slice(0, 500)

  defp do_process(material) do
    # For now, treat everything as a single "page"
    # In production, PDFs would be split into individual page images
    #
    # Send only the gs:// URI to Vision — it reads the bytes server-side
    # via Google's backbone, so our worker never has to base64-encode
    # a multi-MB image into a JSON body. That shrinks the Vision request
    # from ~3 MB to a few hundred bytes and removes the Finch socket
    # pressure that was causing :closed/:timeout cascades under concurrency.
    gcs_uri = GCS.gcs_uri(material.file_path)

    case GoogleVision.detect_text_from_gcs(gcs_uri) do
      {:ok, result} ->
        page = create_ocr_page(material, 1, result)
        maybe_extract_figures(material, page, result.blocks)
        {:ok, [page]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # TEMPORARILY DISABLED 2026-04-20 while stabilizing OCR throughput.
  # For a textbook where nearly every page has a "Figure N" caption, the
  # previous implementation still fired a 2 MB GCS GET per page, which —
  # combined with 8 concurrent Vision POSTs — produced a Finch socket
  # storm (:sndbuf :einval, :closed) that tanked OCR success rate.
  # The OCR text extraction is the primary goal; figure cropping is a
  # nice-to-have that can run later in a separate low-concurrency pass.
  # Re-enable once we give FigureExtractor its own Finch pool.
  defp maybe_extract_figures(_material, _page, _blocks), do: :ok

  defp create_ocr_page(material, page_number, ocr_result) do
    attrs = %{
      material_id: material.id,
      page_number: page_number,
      extracted_text: ocr_result.text,
      bounding_boxes: %{"blocks" => ocr_result.blocks},
      images: %{"pages" => ocr_result.pages},
      status: :completed,
      error: nil
    }

    {:ok, page} = Content.create_ocr_page(attrs)
    page
  end
end
