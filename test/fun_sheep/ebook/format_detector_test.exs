defmodule FunSheep.Ebook.FormatDetectorTest do
  use ExUnit.Case, async: true

  alias FunSheep.Ebook.FormatDetector

  describe "detect/2 — PDF" do
    test "detects PDF from magic bytes" do
      bytes = <<0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34>>
      assert FormatDetector.detect(bytes, "pdf") == :pdf
    end

    test "detects PDF from magic bytes regardless of extension" do
      bytes = <<0x25, 0x50, 0x44, 0x46, 0x2D, 0x31>>
      assert FormatDetector.detect(bytes, "unknown") == :pdf
    end
  end

  describe "detect/2 — EPUB" do
    test "detects EPUB from ZIP magic bytes with epub extension" do
      bytes = <<0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00>>
      assert FormatDetector.detect(bytes, "epub") == :epub
    end

    test "detects EPUB from ZIP magic bytes with no extension" do
      bytes = <<0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00>>
      assert FormatDetector.detect(bytes, "") == :epub
    end

    test "does NOT detect EPUB when extension is mobi (mobi wins)" do
      bytes = <<0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00>>
      assert FormatDetector.detect(bytes, "mobi") == :mobi
    end

    test "does NOT detect EPUB when extension is azw3 (azw3 wins)" do
      bytes = <<0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00>>
      assert FormatDetector.detect(bytes, "azw3") == :azw3
    end
  end

  describe "detect/2 — MOBI/AZW" do
    test "detects mobi from extension" do
      assert FormatDetector.detect(<<0x00, 0x01>>, "mobi") == :mobi
    end

    test "detects azw from extension" do
      assert FormatDetector.detect(<<0x00, 0x01>>, "azw") == :azw3
    end

    test "detects azw3 from extension" do
      assert FormatDetector.detect(<<0x00, 0x01>>, "azw3") == :azw3
    end

    test "detects kfx from extension" do
      assert FormatDetector.detect(<<0x00, 0x01>>, "kfx") == :azw3
    end
  end

  describe "detect/2 — images" do
    test "detects JPEG from FF D8 FF magic bytes" do
      bytes = <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10>>
      assert FormatDetector.detect(bytes, "jpg") == :image
    end

    test "detects PNG from 89 50 4E 47 magic bytes" do
      bytes = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>
      assert FormatDetector.detect(bytes, "png") == :image
    end

    test "detects GIF from GIF magic bytes" do
      bytes = <<0x47, 0x49, 0x46, 0x38, 0x39, 0x61>>
      assert FormatDetector.detect(bytes, "gif") == :image
    end

    test "detects image from magic bytes regardless of extension" do
      jpeg = <<0xFF, 0xD8, 0xFF, 0xE0>>
      assert FormatDetector.detect(jpeg, "unknown") == :image
    end
  end

  describe "detect/2 — unknown" do
    test "returns :unknown for unrecognised bytes" do
      assert FormatDetector.detect(<<0x00, 0x01, 0x02, 0x03>>, "") == :unknown
    end

    test "returns :unknown for empty bytes with no extension" do
      assert FormatDetector.detect(<<>>, "") == :unknown
    end

    test "returns :unknown for random bytes with random extension" do
      assert FormatDetector.detect(<<"hello world">>, "txt") == :unknown
    end
  end
end
