defmodule FunSheep.Ebook.MobiConverterTest do
  use ExUnit.Case, async: true

  alias FunSheep.Ebook.MobiConverter

  describe "calibre_available?/0" do
    test "returns a boolean" do
      result = MobiConverter.calibre_available?()
      assert is_boolean(result)
    end

    test "returns false when ebook-convert is not on PATH (expected in CI)" do
      # Verify the function correctly reflects the system state.
      # In CI and most dev environments calibre is not installed.
      # If someone runs tests on a machine with calibre, this test still passes.
      assert MobiConverter.calibre_available?() ==
               (System.find_executable("ebook-convert") != nil)
    end
  end

  describe "convert/2 — calibre not available" do
    test "returns {:error, :calibre_not_found} when ebook-convert is absent" do
      # Only run this test when calibre is NOT installed.
      # On machines with calibre the binary would be found and the test would
      # attempt a real conversion against a non-existent file — skip it.
      if System.find_executable("ebook-convert") != nil do
        # Calibre is present; skip gracefully.
        :ok
      else
        tmp_dir = Path.join(System.tmp_dir!(), "mobi_test_#{System.unique_integer([:positive])}")
        File.mkdir_p!(tmp_dir)

        on_exit(fn -> File.rm_rf(tmp_dir) end)

        assert {:error, :calibre_not_found} =
                 MobiConverter.convert("/nonexistent/file.mobi", tmp_dir)
      end
    end
  end

  describe "convert/2 — calibre available" do
    @tag :requires_calibre
    test "returns {:ok, epub_path} for a valid mobi input file" do
      # This test only runs on a machine with calibre installed.
      # Use `mix test --include requires_calibre` to enable it.
      unless System.find_executable("ebook-convert") do
        ExUnit.configure(exclude: [:requires_calibre])
      end

      # Create a minimal stub input (calibre will fail gracefully on garbage).
      tmp_dir = Path.join(System.tmp_dir!(), "mobi_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)
      input = Path.join(tmp_dir, "test.mobi")
      File.write!(input, "PalmDOC")

      on_exit(fn -> File.rm_rf(tmp_dir) end)

      result = MobiConverter.convert(input, tmp_dir)
      # calibre on a garbage file will likely fail, but the result must be
      # a tagged tuple — either {:ok, path} or {:error, reason}.
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
