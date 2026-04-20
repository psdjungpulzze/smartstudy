defmodule FunSheep.Storage.GCSTest do
  use ExUnit.Case, async: false

  alias FunSheep.Storage.GCS

  describe "url/1" do
    test "returns a path under /uploads regardless of leading slash" do
      assert GCS.url("staging/batch/file.pdf") == "/uploads/staging/batch/file.pdf"
      assert GCS.url("/staging/batch/file.pdf") == "/uploads/staging/batch/file.pdf"
    end
  end

  describe "configuration" do
    setup do
      original = Application.get_env(:fun_sheep, FunSheep.Storage.GCS)
      on_exit(fn -> Application.put_env(:fun_sheep, FunSheep.Storage.GCS, original) end)
      :ok
    end

    test "put/2 raises when bucket is not configured" do
      Application.put_env(:fun_sheep, FunSheep.Storage.GCS, bucket: nil, goth_name: :dummy)

      assert_raise RuntimeError, ~r/GCS bucket is not configured/, fn ->
        GCS.put("x/y.bin", "content")
      end
    end
  end
end
