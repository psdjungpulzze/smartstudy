defmodule FunSheep.OCR.PdfSplitterTest do
  use ExUnit.Case, async: false

  alias FunSheep.OCR.PdfSplitter

  @tmp_dir System.tmp_dir!()

  setup do
    Application.put_env(:fun_sheep, :ocr_mock, true)
    on_exit(fn -> Application.put_env(:fun_sheep, :ocr_mock, true) end)
    :ok
  end

  defp write_mock_pdf(pages) do
    path = Path.join(@tmp_dir, "splittertest_#{System.unique_integer([:positive])}.pdf")
    File.write!(path, ~s({"pages":#{pages}} rest-of-fake-pdf-bytes))
    on_exit(fn -> File.rm(path) end)
    path
  end

  describe "page_count/1 (mock mode)" do
    test "parses synthetic page count from marker file" do
      path = write_mock_pdf(347)
      assert {:ok, 347} = PdfSplitter.page_count(path)
    end

    test "defaults to 1 when no page marker is present" do
      path = Path.join(@tmp_dir, "plain_#{System.unique_integer([:positive])}.pdf")
      File.write!(path, "plain bytes")
      on_exit(fn -> File.rm(path) end)

      assert {:ok, 1} = PdfSplitter.page_count(path)
    end
  end

  describe "split/3 (mock mode)" do
    test "yields ceil(pages / chunk_size) chunks with global page numbers" do
      path = write_mock_pdf(450)
      out_dir = Path.join(@tmp_dir, "split_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf(out_dir) end)

      {:ok, chunks} = PdfSplitter.split(path, 200, out_dir)

      assert length(chunks) == 3

      # Chunk page ranges must be non-overlapping and cover the full range.
      assert Enum.map(chunks, & &1.start_page) == [1, 201, 401]
      assert Enum.map(chunks, & &1.page_count) == [200, 200, 50]
      # Deterministic filenames so a retry can resume.
      assert Enum.map(chunks, &Path.basename(&1.path)) == ["c0.pdf", "c1.pdf", "c2.pdf"]
      # Every chunk file is actually on disk.
      for c <- chunks, do: assert(File.exists?(c.path))
    end

    test "single chunk for PDFs smaller than chunk size" do
      path = write_mock_pdf(50)
      out_dir = Path.join(@tmp_dir, "split_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf(out_dir) end)

      {:ok, [chunk]} = PdfSplitter.split(path, 200, out_dir)
      assert chunk.start_page == 1
      assert chunk.page_count == 50
    end
  end
end
