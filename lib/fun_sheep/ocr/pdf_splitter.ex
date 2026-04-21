defmodule FunSheep.OCR.PdfSplitter do
  @moduledoc """
  Thin wrappers around `pdfinfo` (poppler-utils) and `qpdf` for counting and
  splitting PDF files. These CLIs are installed in the worker container;
  the web container never invokes them.

  Why CLIs and not a pure-Elixir library: the native `qpdf` handles PDFs up
  to 500+ MB at a few hundred MB/s without blowing up the BEAM heap, and
  `pdfinfo` returns page count in under 100 ms even on huge files. Pure-
  Elixir PDF libraries exist but are either slow or incomplete for the
  textbook-style PDFs students upload.

  In `:ocr_mock` mode (tests) we short-circuit to a fake counter and a
  bytes-split strategy so the test suite doesn't need the CLIs installed.
  """

  require Logger

  @default_chunk_pages 200

  @doc "Chunk size (pages) used by the dispatcher. Exposed so tests can inspect it."
  def default_chunk_pages, do: @default_chunk_pages

  @doc """
  Count pages in a PDF at `path`. Returns `{:ok, n}` on success.
  """
  def page_count(path) do
    if Application.get_env(:fun_sheep, :ocr_mock, false) do
      mock_page_count(path)
    else
      case System.cmd("pdfinfo", [path], stderr_to_stdout: true) do
        {output, 0} -> parse_pdfinfo_pages(output)
        {output, code} -> {:error, {:pdfinfo_failed, code, String.trim(output)}}
      end
    end
  rescue
    e in ErlangError ->
      {:error, {:pdfinfo_missing, Exception.message(e)}}
  end

  @doc """
  Split `path` into chunks of `chunk_pages` pages each, writing the chunks
  into `out_dir`. Returns `{:ok, [%{index: 0, start_page: 1, page_count: 200, path: "/tmp/.../c0.pdf"}, ...]}`.

  The chunk filenames are `c<index>.pdf` — deterministic so a worker retry
  picks up where it left off.
  """
  def split(path, chunk_pages \\ @default_chunk_pages, out_dir) do
    with {:ok, total} <- page_count(path),
         :ok <- File.mkdir_p(out_dir) do
      if Application.get_env(:fun_sheep, :ocr_mock, false) do
        mock_split(path, total, chunk_pages, out_dir)
      else
        real_split(path, total, chunk_pages, out_dir)
      end
    end
  end

  defp real_split(path, total, chunk_pages, out_dir) do
    chunks =
      Stream.iterate(1, &(&1 + chunk_pages))
      |> Stream.take_while(&(&1 <= total))
      |> Enum.with_index()
      |> Enum.map(fn {start_page, index} ->
        end_page = min(start_page + chunk_pages - 1, total)
        chunk_path = Path.join(out_dir, "c#{index}.pdf")

        # `qpdf input.pdf --pages input.pdf 1-200 -- chunk.pdf`
        # Idempotent: if chunk already exists (retry after crash), skip.
        if File.exists?(chunk_path) do
          %{
            index: index,
            start_page: start_page,
            page_count: end_page - start_page + 1,
            path: chunk_path
          }
        else
          page_spec = "#{start_page}-#{end_page}"

          case System.cmd("qpdf", [path, "--pages", path, page_spec, "--", chunk_path],
                 stderr_to_stdout: true
               ) do
            {_, 0} ->
              %{
                index: index,
                start_page: start_page,
                page_count: end_page - start_page + 1,
                path: chunk_path
              }

            {output, code} ->
              throw({:qpdf_failed, index, code, String.trim(output)})
          end
        end
      end)

    {:ok, chunks}
  catch
    {:qpdf_failed, index, code, msg} ->
      {:error, {:qpdf_failed, index, code, msg}}
  end

  defp parse_pdfinfo_pages(output) do
    # pdfinfo emits "Pages:          N" — one line among many. We grep just
    # that line to tolerate variations in other lines (encryption warnings,
    # localized formats) that would break a rigid full-output parse.
    output
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case Regex.run(~r/^Pages:\s+(\d+)/, line) do
        [_, n] -> {:ok, String.to_integer(n)}
        _ -> nil
      end
    end)
    |> case do
      {:ok, _} = ok -> ok
      nil -> {:error, {:pdfinfo_parse_failed, output}}
    end
  end

  # ── Mock mode ────────────────────────────────────────────────────────────
  # Tests place a marker file (see test/support/pdf_splitter_stub.ex) at the
  # same path; we read the marker JSON to decide the synthetic page count
  # and simply copy the source bytes into each chunk path so downstream code
  # that expects real files works.

  defp mock_page_count(path) do
    # In mock mode the content of the file is expected to start with a
    # JSON line `{"pages":N}` (plus arbitrary bytes after). If not present
    # we default to 1, matching the existing single-page mock in GoogleVision.
    case File.read(path) do
      {:ok, "{\"pages\":" <> rest} ->
        [n_str | _] = String.split(rest, "}", parts: 2)

        case Integer.parse(n_str) do
          {n, _} when n > 0 -> {:ok, n}
          _ -> {:ok, 1}
        end

      {:ok, _} ->
        {:ok, 1}

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  defp mock_split(path, total, chunk_pages, out_dir) do
    {:ok, content} = File.read(path)

    chunks =
      1
      |> Stream.iterate(&(&1 + chunk_pages))
      |> Stream.take_while(&(&1 <= total))
      |> Enum.with_index()
      |> Enum.map(fn {start_page, index} ->
        end_page = min(start_page + chunk_pages - 1, total)
        chunk_path = Path.join(out_dir, "c#{index}.pdf")
        File.write!(chunk_path, content)

        %{
          index: index,
          start_page: start_page,
          page_count: end_page - start_page + 1,
          path: chunk_path
        }
      end)

    {:ok, chunks}
  end
end
