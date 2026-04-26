defmodule FunSheep.Documents.TextExtractor do
  @moduledoc """
  Extracts plain text from Office Open XML document formats.

  All modern Office formats (DOCX, PPTX, XLSX) are ZIP archives containing
  XML files. This module unzips them in memory and pulls out the text content
  without requiring LibreOffice or any external converter.

  Old binary formats (.doc, .xls) are NOT supported — they require a converter.
  """

  @doc """
  Detects the document type from a file extension and extracts plain text.
  Returns `{:ok, text}` or `{:error, reason}`.
  """
  def extract(bytes, filename) when is_binary(bytes) and is_binary(filename) do
    case String.downcase(Path.extname(filename)) do
      ".docx" -> extract_docx(bytes)
      ".doc" -> {:error, :unsupported_binary_format}
      ".pptx" -> extract_pptx(bytes)
      ".ppt" -> {:error, :unsupported_binary_format}
      ".xlsx" -> extract_xlsx(bytes)
      ".xls" -> {:error, :unsupported_binary_format}
      ext -> {:error, {:unknown_extension, ext}}
    end
  end

  @doc """
  Extracts text from a DOCX file's `word/document.xml`.
  Paragraphs and runs are separated by newlines.
  """
  def extract_docx(bytes) do
    with {:ok, files} <- unzip(bytes) do
      case Map.get(files, "word/document.xml") do
        nil ->
          {:error, :missing_document_xml}

        xml ->
          text =
            xml
            # Paragraph boundaries → newline
            |> String.replace(~r/<w:p[ >]/, "\n")
            |> String.replace("<w:p/>", "\n")
            # Table cells and rows → tab/newline separators
            |> String.replace(~r/<w:tc[ >]/, "\t")
            |> String.replace(~r/<w:tr[ >]/, "\n")
            |> strip_xml()

          {:ok, text}
      end
    end
  end

  @doc """
  Extracts text from a PPTX file's slide XMLs (`ppt/slides/slide*.xml`).
  Each slide is separated by a blank line.
  """
  def extract_pptx(bytes) do
    with {:ok, files} <- unzip(bytes) do
      slide_text =
        files
        |> Enum.filter(fn {name, _} ->
          String.match?(name, ~r|^ppt/slides/slide\d+\.xml$|)
        end)
        |> Enum.sort_by(fn {name, _} ->
          Regex.run(~r/(\d+)\.xml$/, name) |> List.last() |> String.to_integer()
        end)
        |> Enum.map(fn {_, xml} ->
          xml
          # Shape text paragraphs
          |> String.replace(~r/<a:p[ >]/, "\n")
          |> String.replace("<a:p/>", "\n")
          |> strip_xml()
        end)
        |> Enum.join("\n\n")

      {:ok, slide_text}
    end
  end

  @doc """
  Extracts text from an XLSX file using the shared strings table and cell values.
  Cells are tab-separated, rows are newline-separated.
  """
  def extract_xlsx(bytes) do
    with {:ok, files} <- unzip(bytes) do
      shared_strings = parse_shared_strings(Map.get(files, "xl/sharedStrings.xml"))

      sheet_text =
        files
        |> Enum.filter(fn {name, _} ->
          String.match?(name, ~r|^xl/worksheets/sheet\d+\.xml$|)
        end)
        |> Enum.sort_by(fn {name, _} ->
          Regex.run(~r/(\d+)\.xml$/, name) |> List.last() |> String.to_integer()
        end)
        |> Enum.map(fn {_, xml} -> extract_sheet_text(xml, shared_strings) end)
        |> Enum.join("\n\n")

      {:ok, sheet_text}
    end
  end

  # --- Private helpers ---

  defp unzip(bytes) when is_binary(bytes) do
    case :zip.extract(bytes, [:memory]) do
      {:ok, file_list} ->
        files =
          Map.new(file_list, fn {name_charlist, content} ->
            {List.to_string(name_charlist), List.to_string(content)}
          end)

        {:ok, files}

      {:error, reason} ->
        {:error, {:zip_extract_failed, reason}}
    end
  end

  # Build a list of shared strings from `xl/sharedStrings.xml`.
  # XLSX cells reference strings by index into this list.
  defp parse_shared_strings(nil), do: []

  defp parse_shared_strings(xml) do
    # Each <si> element holds one string, possibly across multiple <t> tags
    Regex.scan(~r/<si>(.*?)<\/si>/s, xml)
    |> Enum.map(fn [_, inner] -> strip_xml(inner) end)
  end

  # Extract a flat text representation of one worksheet.
  defp extract_sheet_text(xml, shared_strings) do
    # Each <row> → newline-joined cells; each <c> → value
    Regex.scan(~r/<row[^>]*>(.*?)<\/row>/s, xml)
    |> Enum.map(fn [_, row_xml] ->
      Regex.scan(~r/<c[^>]*>(.*?)<\/c>/s, row_xml)
      |> Enum.map(fn [full_match, cell_xml] ->
        # t="s" means shared string reference; t="n" or default means inline number/string
        is_shared = String.contains?(full_match, ~s(t="s"))
        raw = strip_xml(Regex.replace(~r/<f>.*?<\/f>/s, cell_xml, ""))

        if is_shared do
          idx = String.to_integer(String.trim(raw))
          Enum.at(shared_strings, idx, "")
        else
          raw
        end
      end)
      |> Enum.join("\t")
    end)
    |> Enum.join("\n")
  end

  defp strip_xml(xml) when is_binary(xml) do
    xml
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
