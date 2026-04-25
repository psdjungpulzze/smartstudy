defmodule FunSheep.Ebook.FormatDetector do
  @moduledoc """
  Detects a file's canonical format from its magic bytes and file extension.

  Magic-byte detection takes precedence over extension so that mis-named
  files are identified correctly. Extension is only consulted as a fallback
  when magic bytes are ambiguous (e.g. MOBI files share ZIP-like bytes with
  EPUB in some edge cases, but are reliably identified by extension).

  Returns one of: `:pdf` | `:epub` | `:mobi` | `:azw3` | `:image` | `:unknown`
  """

  @doc """
  Detect format from the first N bytes of a file and its extension.

  `bytes`  — binary, at least the first 8 bytes of the file
  `ext`    — lowercase extension string without leading dot, e.g. `"epub"`, `"pdf"`, `""`

  ## Examples

      iex> FunSheep.Ebook.FormatDetector.detect(<<0x25, 0x50, 0x44, 0x46, 0>>, "pdf")
      :pdf

      iex> FunSheep.Ebook.FormatDetector.detect(<<0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0>>, "epub")
      :epub

  """
  @spec detect(binary(), String.t()) :: :pdf | :epub | :mobi | :azw3 | :image | :unknown

  # PDF: starts with "%PDF-"
  def detect(<<0x25, 0x50, 0x44, 0x46, _rest::binary>>, _ext), do: :pdf

  # EPUB: ZIP magic bytes (PK local file header signature)
  # EPUB files are ZIP archives with a mimetype file. Extension-based
  # disambiguation happens below for MOBI, which sometimes masquerades
  # as ZIP on misconfigured tools.
  def detect(<<0x50, 0x4B, 0x03, 0x04, _rest::binary>>, ext)
      when ext not in ["mobi", "azw", "azw3", "kfx"],
      do: :epub

  # MOBI/AZW by extension (magic bytes overlap with ZIP/EPUB)
  def detect(_bytes, "mobi"), do: :mobi
  def detect(_bytes, ext) when ext in ["azw", "azw3", "kfx"], do: :azw3

  # JPEG: starts with FF D8 FF
  def detect(<<0xFF, 0xD8, 0xFF, _rest::binary>>, _ext), do: :image

  # PNG: starts with 89 50 4E 47
  def detect(<<0x89, 0x50, 0x4E, 0x47, _rest::binary>>, _ext), do: :image

  # GIF: starts with "GIF"
  def detect(<<0x47, 0x49, 0x46, _rest::binary>>, _ext), do: :image

  # WEBP: "RIFF....WEBP"
  def detect(<<0x52, 0x49, 0x46, 0x46, _size::32, 0x57, 0x45, 0x42, 0x50, _rest::binary>>, _ext),
    do: :image

  # TIFF: little-endian or big-endian byte order mark
  def detect(<<0x49, 0x49, 0x2A, 0x00, _rest::binary>>, _ext), do: :image
  def detect(<<0x4D, 0x4D, 0x00, 0x2A, _rest::binary>>, _ext), do: :image

  # Fallback: unknown format
  def detect(_bytes, _ext), do: :unknown

  @doc """
  Convenience wrapper: reads the magic bytes from a local file path and
  normalises the extension, then delegates to `detect/2`.
  """
  @spec detect_file(String.t()) :: :pdf | :epub | :mobi | :azw3 | :image | :unknown
  def detect_file(path) do
    ext =
      path
      |> Path.extname()
      |> String.trim_leading(".")
      |> String.downcase()

    case File.open(path, [:read, :binary]) do
      {:ok, io} ->
        bytes = IO.read(io, 16)
        File.close(io)
        detect(bytes, ext)

      {:error, _} ->
        :unknown
    end
  end
end
