defmodule FunSheep.Ingest.CsvParser do
  @moduledoc """
  Streaming CSV parser wrapper.

  Wraps `NimbleCSV.RFC4180` to yield each row as a `%{column_name => value}`
  map, with header-name awareness. Keeps memory flat — built for 100K+ row
  NCES extracts.

  Handles quoted fields, embedded newlines, and UTF-8 BOM stripping.
  Korean NEIS CSVs arrive in UTF-8; legacy KERIS bundles occasionally use
  EUC-KR — pass `encoding: :euc_kr` to transcode on the fly.
  """

  NimbleCSV.define(__MODULE__.RFC4180, separator: ",", escape: "\"")
  NimbleCSV.define(__MODULE__.Tab, separator: "\t", escape: "\"")
  NimbleCSV.define(__MODULE__.Pipe, separator: "|", escape: "\"")

  @doc """
  Stream rows from `path`, yielding maps keyed by header name.

  Options:
    * `:separator` — `:comma` (default), `:tab`, `:pipe`
    * `:encoding` — `:utf8` (default), `:euc_kr`, `:latin1`
    * `:headers` — provide an explicit header list (bypasses file's first row)
  """
  @spec stream(Path.t(), keyword()) :: Enumerable.t()
  def stream(path, opts \\ []) do
    separator = Keyword.get(opts, :separator, :comma)
    encoding = Keyword.get(opts, :encoding, :utf8)
    explicit_headers = Keyword.get(opts, :headers)

    parser =
      case separator do
        :comma -> __MODULE__.RFC4180
        :tab -> __MODULE__.Tab
        :pipe -> __MODULE__.Pipe
      end

    raw_stream =
      path
      |> File.stream!(read_ahead: 65_536)
      |> transcode(encoding)
      |> strip_bom()
      |> parser.parse_stream(skip_headers: explicit_headers != nil)

    case explicit_headers do
      nil ->
        # First emitted row is the header, zip subsequent rows against it.
        raw_stream
        |> Stream.transform(nil, fn
          row, nil -> {[], row}
          row, headers -> {[rowmap(headers, row)], headers}
        end)

      headers when is_list(headers) ->
        raw_stream |> Stream.map(&rowmap(headers, &1))
    end
  end

  defp rowmap(headers, row) do
    headers
    |> Enum.zip(row)
    |> Map.new(fn {h, v} -> {normalize_key(h), nilify(v)} end)
  end

  defp normalize_key(h) when is_binary(h) do
    h |> String.trim() |> String.trim_leading("\uFEFF")
  end

  defp nilify(""), do: nil
  defp nilify(nil), do: nil
  defp nilify(v) when is_binary(v), do: String.trim(v)
  defp nilify(v), do: v

  # Encoding helpers. NimbleCSV wants UTF-8; legacy KR files come in EUC-KR.
  defp transcode(stream, :utf8), do: stream

  defp transcode(stream, :latin1) do
    Stream.map(stream, &:unicode.characters_to_binary(&1, :latin1, :utf8))
  end

  defp transcode(stream, :euc_kr) do
    # Codepagex is optional; if absent, caller must pre-convert the file
    # (iconv -f EUC-KR -t UTF-8). Log loudly so ops notices.
    if Code.ensure_loaded?(Codepagex) do
      Stream.map(stream, fn chunk ->
        case apply(Codepagex, :to_string, [chunk, "VENDORS/MICSFT/WINDOWS/CP949"]) do
          {:ok, utf8, _} -> utf8
          _ -> chunk
        end
      end)
    else
      require Logger
      Logger.warning("ingest.csv EUC-KR requested but :codepagex not loaded; assuming UTF-8")
      stream
    end
  end

  defp strip_bom(stream) do
    Stream.transform(stream, true, fn
      chunk, true -> {[String.replace_prefix(chunk, "\uFEFF", "")], false}
      chunk, false -> {[chunk], false}
    end)
  end
end
