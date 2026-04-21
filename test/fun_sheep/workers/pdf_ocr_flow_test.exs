defmodule FunSheep.Workers.PdfOcrFlowTest do
  @moduledoc """
  End-to-end integration test for the async PDF OCR path.

  Strategy: drive each worker directly so we can stub Vision's output
  JSONs in-between. The real runtime flow (Oban enqueues chained inline)
  is exercised by the pipeline_test + dispatcher idempotency test below.

    1. Build an UploadedMaterial with a fake multi-page PDF in storage
    2. Run PdfOcrDispatchWorker → splits, "submits" mock Vision ops,
       records ocr_operations["chunks"], enqueues pollers (we ignore
       the enqueued pollers and drive them ourselves)
    3. Write synthetic Vision output JSONs to local storage
    4. Run PdfOcrPollerWorker for each chunk → upserts OcrPage rows with
       global page numbers, bumps ocr_pages_completed, finalizes material

  All external boundaries (Vision API, GCS list) are mocked.
  """

  use FunSheep.DataCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  alias FunSheep.{Content, Storage}
  alias FunSheep.Workers.{PdfOcrDispatchWorker, PdfOcrPollerWorker}

  import FunSheep.ContentFixtures

  setup do
    Application.put_env(:fun_sheep, :ocr_mock, true)
    on_exit(fn -> Application.put_env(:fun_sheep, :ocr_mock, true) end)
    :ok
  end

  # Oban's :inline mode would cascade dispatch → poller auto-executions
  # before we can stub Vision output. `with_testing_mode(:manual, fn -> ... end)`
  # only affects the calling process, so every test body that enqueues jobs
  # wraps its work in this helper.
  defp in_manual_oban(fun), do: Oban.Testing.with_testing_mode(:manual, fun)

  defp build_pdf_material(pages, opts \\ []) do
    batch_id = Ecto.UUID.generate()
    file_name = Keyword.get(opts, :file_name, "book.pdf")
    key = "staging/#{batch_id}/#{file_name}"
    body = ~s({"pages":#{pages}} pdf-body-bytes)

    {:ok, _} = Storage.put(key, body, content_type: "application/pdf")

    material =
      create_uploaded_material(%{
        file_path: key,
        file_name: file_name,
        file_type: "application/pdf",
        file_size: byte_size(body),
        batch_id: batch_id
      })

    on_exit(fn ->
      Storage.delete(key)
      base = String.replace_suffix(key, ".pdf", "")
      for idx <- 0..10, do: Storage.delete("#{base}.chunks/c#{idx}.pdf")
    end)

    material
  end

  # Write synthetic Vision output JSONs into the local storage prefix for a
  # single chunk. Each JSON file covers up to `batch_size` (20) pages.
  defp stub_vision_output(chunk_entry) do
    start_page = chunk_entry["start_page"]
    page_count = chunk_entry["page_count"]
    output_prefix = chunk_entry["output_prefix"]

    # Must mirror the poller's `strip_gs_prefix`: it strips only the gs://
    # scheme and the bucket segment, leaving the intra-bucket key intact.
    relative_prefix =
      output_prefix
      |> String.replace_prefix("gs://", "")
      |> strip_first_segment()

    batch_size = 20

    0..(page_count - 1)
    |> Enum.chunk_every(batch_size)
    |> Enum.with_index()
    |> Enum.each(fn {page_offsets, file_idx} ->
      responses =
        Enum.map(page_offsets, fn offset ->
          global = start_page + offset

          %{
            "context" => %{"pageNumber" => offset + 1},
            "fullTextAnnotation" => %{
              "text" => "page #{global} text",
              "pages" => [%{"width" => 612, "height" => 792, "blocks" => []}]
            }
          }
        end)

      json = Jason.encode!(%{"responses" => responses})
      path_key = Path.join(relative_prefix, "output-#{file_idx}.json")
      {:ok, _} = Storage.put(path_key, json, content_type: "application/json")
    end)
  end

  defp strip_first_segment(prefix) when is_binary(prefix) do
    case String.split(prefix, "/", parts: 2) do
      [_leading, rest] -> rest
      [_only] -> ""
    end
  end

  defp drive_dispatch(material) do
    # Must be called inside `in_manual_oban` so the dispatcher's enqueue of
    # pollers doesn't auto-run them before we stub Vision output.
    :ok =
      PdfOcrDispatchWorker.perform(%Oban.Job{
        args: %{"material_id" => material.id},
        attempt: 1
      })

    Content.get_uploaded_material!(material.id)
  end

  describe "dispatcher records per-chunk metadata" do
    test "small PDF → one chunk" do
      in_manual_oban(fn ->
        material = build_pdf_material(3)
        dispatched = drive_dispatch(material)

        assert dispatched.ocr_pages_expected == 3
        [chunk] = dispatched.ocr_operations["chunks"]
        assert chunk["start_page"] == 1
        assert chunk["page_count"] == 3
        assert chunk["status"] == "running"
        assert String.starts_with?(chunk["name"], "operations/mock-")
      end)
    end

    test "450-page PDF splits into 3 chunks" do
      in_manual_oban(fn ->
        material = build_pdf_material(450)
        dispatched = drive_dispatch(material)

        chunks = dispatched.ocr_operations["chunks"]
        assert length(chunks) == 3
        assert Enum.map(chunks, & &1["start_page"]) == [1, 201, 401]
        assert Enum.map(chunks, & &1["page_count"]) == [200, 200, 50]
        assert dispatched.ocr_pages_expected == 450
      end)
    end

    test "second dispatch is idempotent" do
      in_manual_oban(fn ->
        material = build_pdf_material(3)
        dispatched = drive_dispatch(material)
        original = dispatched.ocr_operations["chunks"]

        assert {:ok, :already_dispatched} =
                 PdfOcrDispatchWorker.perform(%Oban.Job{
                   args: %{"material_id" => material.id},
                   attempt: 1
                 })

        replayed = Content.get_uploaded_material!(material.id)
        assert replayed.ocr_operations["chunks"] == original
      end)
    end
  end

  describe "poller reads Vision output and inserts OcrPages" do
    test "single-chunk PDF completes to :completed with correct pages" do
      in_manual_oban(fn ->
        material = build_pdf_material(3)
        dispatched = drive_dispatch(material)

        [chunk] = dispatched.ocr_operations["chunks"]
        stub_vision_output(chunk)

        :ok =
          PdfOcrPollerWorker.perform(%Oban.Job{
            args: %{"material_id" => material.id, "chunk_index" => chunk["index"]},
            attempt: 1
          })

        final = Content.get_uploaded_material!(material.id)
        assert final.ocr_status == :completed
        assert final.ocr_pages_completed == 3

        pages = Content.list_ocr_pages_by_material(material.id)
        assert Enum.map(pages, & &1.page_number) == [1, 2, 3]
        assert Enum.all?(pages, &(&1.status == :completed))
      end)
    end

    test "multi-chunk PDF aggregates global page numbers across chunks" do
      in_manual_oban(fn ->
        material = build_pdf_material(450)
        dispatched = drive_dispatch(material)

        chunks = dispatched.ocr_operations["chunks"]
        Enum.each(chunks, &stub_vision_output/1)

        Enum.each(chunks, fn chunk ->
          :ok =
            PdfOcrPollerWorker.perform(%Oban.Job{
              args: %{"material_id" => material.id, "chunk_index" => chunk["index"]},
              attempt: 1
            })
        end)

        final = Content.get_uploaded_material!(material.id)
        assert final.ocr_status == :completed
        assert final.ocr_pages_completed == 450

        pages =
          Content.list_ocr_pages_by_material(material.id)
          |> Enum.map(& &1.page_number)
          |> Enum.sort()

        assert pages == Enum.to_list(1..450)

        assert Enum.all?(final.ocr_operations["chunks"], &(&1["status"] == "done"))
      end)
    end

    test "re-polling a done chunk is a no-op (no duplicate rows, no double count)" do
      in_manual_oban(fn ->
        material = build_pdf_material(5)
        dispatched = drive_dispatch(material)

        [chunk] = dispatched.ocr_operations["chunks"]
        stub_vision_output(chunk)

        :ok =
          PdfOcrPollerWorker.perform(%Oban.Job{
            args: %{"material_id" => material.id, "chunk_index" => chunk["index"]},
            attempt: 1
          })

        first_count = Content.get_uploaded_material!(material.id).ocr_pages_completed
        assert first_count == 5

        :ok =
          PdfOcrPollerWorker.perform(%Oban.Job{
            args: %{"material_id" => material.id, "chunk_index" => chunk["index"]},
            attempt: 2
          })

        final = Content.get_uploaded_material!(material.id)
        assert final.ocr_pages_completed == 5
        assert length(Content.list_ocr_pages_by_material(material.id)) == 5
      end)
    end
  end

  describe "Pipeline.process wiring" do
    test "sets material :processing and enqueues a dispatch job" do
      in_manual_oban(fn ->
        material = build_pdf_material(3)

        assert {:ok, :dispatched} = FunSheep.OCR.Pipeline.process(material.id)

        # In :manual mode the dispatch job is queued but not run, so the
        # material sits at :processing with no chunks recorded yet. The
        # dispatch worker test above covers the chunk-recording behavior.
        final = Content.get_uploaded_material!(material.id)
        assert final.ocr_status == :processing
        assert_enqueued(worker: PdfOcrDispatchWorker, args: %{"material_id" => material.id})
      end)
    end
  end
end
