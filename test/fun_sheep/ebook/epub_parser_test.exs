defmodule FunSheep.Ebook.EpubParserTest do
  use ExUnit.Case, async: true

  alias FunSheep.Ebook.EpubParser
  alias FunSheep.EbookFixtures

  # Write fixture bytes to a temp file and return its path + cleanup function
  defp write_tmp(bytes, name \\ "test.epub") do
    dir = System.tmp_dir!() |> Path.join("epub_parser_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    File.write!(path, bytes)
    {path, fn -> File.rm_rf!(dir) end}
  end

  describe "extract/1 — happy path (EPUB 2)" do
    test "returns metadata with title and author" do
      bytes = EbookFixtures.minimal_epub2_bytes(title: "Biology Basics", author: "Jane Smith")
      {path, cleanup} = write_tmp(bytes)

      try do
        {:ok, %{metadata: meta}} = EpubParser.extract(path)
        assert meta["title"] == "Biology Basics"
        assert "Jane Smith" in meta["authors"]
      after
        cleanup.()
      end
    end

    test "returns at least one spine item with non-empty text" do
      bytes =
        EbookFixtures.minimal_epub2_bytes(
          chapter_text: "Photosynthesis converts light to energy."
        )

      {path, cleanup} = write_tmp(bytes)

      try do
        {:ok, %{spine_items: items}} = EpubParser.extract(path)
        assert length(items) >= 1

        all_text = Enum.map_join(items, " ", & &1.text)
        assert String.contains?(all_text, "Photosynthesis")
      after
        cleanup.()
      end
    end

    test "returns TOC entries with titles from NCX" do
      bytes = EbookFixtures.minimal_epub2_bytes()
      {path, cleanup} = write_tmp(bytes)

      try do
        {:ok, %{toc: toc}} = EpubParser.extract(path)
        assert length(toc) >= 1
        [entry | _] = toc
        assert Map.has_key?(entry, :title)
        assert Map.has_key?(entry, :depth)
        assert Map.has_key?(entry, :href)
        assert entry.title =~ "Chapter"
      after
        cleanup.()
      end
    end

    test "spine item index is 0-based" do
      bytes = EbookFixtures.minimal_epub2_bytes()
      {path, cleanup} = write_tmp(bytes)

      try do
        {:ok, %{spine_items: items}} = EpubParser.extract(path)
        first = List.first(items)
        assert first.index == 0
      after
        cleanup.()
      end
    end
  end

  describe "extract/1 — happy path (EPUB 3)" do
    test "extracts title, toc and spine text from EPUB 3" do
      bytes =
        EbookFixtures.minimal_epub3_bytes(
          title: "Physics Fundamentals",
          chapter_text: "Newton discovered gravity."
        )

      {path, cleanup} = write_tmp(bytes)

      try do
        {:ok, result} = EpubParser.extract(path)
        assert result.metadata["title"] == "Physics Fundamentals"

        all_text = Enum.map_join(result.spine_items, " ", & &1.text)
        assert String.contains?(all_text, "Newton")
      after
        cleanup.()
      end
    end
  end

  describe "extract/1 — DRM detection" do
    test "returns {:error, :drm_protected} for DRM-protected EPUB" do
      bytes = EbookFixtures.drm_epub_bytes()
      {path, cleanup} = write_tmp(bytes)

      try do
        assert EpubParser.extract(path) == {:error, :drm_protected}
      after
        cleanup.()
      end
    end
  end

  describe "extract/1 — invalid input" do
    test "returns {:error, :invalid_epub} for corrupt bytes" do
      bytes = EbookFixtures.corrupt_epub_bytes()
      {path, cleanup} = write_tmp(bytes)

      try do
        assert EpubParser.extract(path) == {:error, :invalid_epub}
      after
        cleanup.()
      end
    end

    test "returns error for non-existent file" do
      result = EpubParser.extract("/tmp/this_file_does_not_exist_funsheep_test.epub")
      assert match?({:error, _}, result)
    end
  end

  describe "extract/1 — metadata fields" do
    test "metadata map contains all expected keys" do
      bytes = EbookFixtures.minimal_epub2_bytes()
      {path, cleanup} = write_tmp(bytes)

      try do
        {:ok, %{metadata: meta}} = EpubParser.extract(path)
        assert Map.has_key?(meta, "title")
        assert Map.has_key?(meta, "authors")
        assert Map.has_key?(meta, "language")
        assert Map.has_key?(meta, "publisher")
        assert Map.has_key?(meta, "isbn")
      after
        cleanup.()
      end
    end

    test "language is extracted correctly" do
      bytes = EbookFixtures.minimal_epub2_bytes()
      {path, cleanup} = write_tmp(bytes)

      try do
        {:ok, %{metadata: meta}} = EpubParser.extract(path)
        assert meta["language"] == "en"
      after
        cleanup.()
      end
    end
  end
end
