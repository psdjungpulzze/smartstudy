defmodule FunSheep.Storage.LocalTest do
  use ExUnit.Case, async: true

  alias FunSheep.Storage.Local

  setup do
    key = "test/#{Ecto.UUID.generate()}/hello.txt"
    on_exit(fn -> Local.delete(key) end)
    {:ok, key: key}
  end

  test "put/get round-trip", %{key: key} do
    assert {:ok, ^key} = Local.put(key, "hello world")
    assert {:ok, "hello world"} = Local.get(key)
  end

  test "put creates intermediate directories" do
    deep_key = "test/#{Ecto.UUID.generate()}/a/b/c/nested.txt"
    on_exit(fn -> Local.delete(deep_key) end)

    assert {:ok, _} = Local.put(deep_key, "nested")
    assert {:ok, "nested"} = Local.get(deep_key)
  end

  test "delete is idempotent on missing files" do
    assert :ok = Local.delete("test/does-not-exist-#{System.unique_integer()}.bin")
  end

  test "delete removes the file", %{key: key} do
    Local.put(key, "will-be-gone")
    assert :ok = Local.delete(key)
    assert {:error, :enoent} = Local.get(key)
  end

  test "leading slash in key is stripped", %{key: key} do
    assert {:ok, _} = Local.put("/" <> key, "slashy")
    assert {:ok, "slashy"} = Local.get(key)
    assert {:ok, "slashy"} = Local.get("/" <> key)
  end

  test "url/1 returns a path under /uploads" do
    assert Local.url("staging/foo/bar.pdf") == "/uploads/staging/foo/bar.pdf"
    assert Local.url("/staging/foo/bar.pdf") == "/uploads/staging/foo/bar.pdf"
  end
end
