defmodule StudySmart.StorageTest do
  use ExUnit.Case, async: true

  alias StudySmart.Storage.Local

  @test_content "Hello, this is test content for storage."
  @test_path "test_storage/#{Ecto.UUID.generate()}/test_file.txt"

  setup do
    on_exit(fn ->
      # Clean up the test file and directories
      full_path = Path.join(Local.uploads_dir(), @test_path)
      File.rm(full_path)

      # Remove the test_storage directory tree
      test_dir = Path.join(Local.uploads_dir(), "test_storage")
      File.rm_rf(test_dir)
    end)

    :ok
  end

  describe "Local.put/3" do
    test "writes file to disk and returns {:ok, path}" do
      assert {:ok, @test_path} = Local.put(@test_path, @test_content)

      full_path = Path.join(Local.uploads_dir(), @test_path)
      assert File.exists?(full_path)
      assert File.read!(full_path) == @test_content
    end

    test "creates intermediate directories" do
      nested_path = "test_storage/deep/nested/dir/file.txt"

      on_exit(fn ->
        nested_dir = Path.join(Local.uploads_dir(), "test_storage/deep")
        File.rm_rf(nested_dir)
      end)

      assert {:ok, ^nested_path} = Local.put(nested_path, "content")
      assert File.exists?(Path.join(Local.uploads_dir(), nested_path))
    end
  end

  describe "Local.get/2" do
    test "reads file content from disk" do
      Local.put(@test_path, @test_content)

      assert {:ok, content} = Local.get(@test_path)
      assert content == @test_content
    end

    test "returns error for non-existent file" do
      assert {:error, :enoent} = Local.get("non_existent/file.txt")
    end
  end

  describe "Local.delete/2" do
    test "removes file from disk" do
      Local.put(@test_path, @test_content)
      full_path = Path.join(Local.uploads_dir(), @test_path)
      assert File.exists?(full_path)

      assert :ok = Local.delete(@test_path)
      refute File.exists?(full_path)
    end

    test "returns :ok for non-existent file" do
      assert :ok = Local.delete("non_existent/file.txt")
    end
  end

  describe "Local.url/2" do
    test "returns URL path for serving via Plug.Static" do
      assert Local.url("materials/abc.pdf") == "/uploads/materials/abc.pdf"
    end
  end

  describe "Storage behaviour delegation" do
    test "delegates to configured backend" do
      assert {:ok, @test_path} = StudySmart.Storage.put(@test_path, @test_content)
      assert {:ok, @test_content} = StudySmart.Storage.get(@test_path)
      assert "/uploads/#{@test_path}" == StudySmart.Storage.url(@test_path)
      assert :ok = StudySmart.Storage.delete(@test_path)
    end
  end
end
