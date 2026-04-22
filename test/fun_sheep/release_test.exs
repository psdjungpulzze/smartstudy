defmodule FunSheep.ReleaseTest do
  use ExUnit.Case, async: true

  alias FunSheep.Release

  setup_all do
    Code.ensure_loaded!(Release)
    :ok
  end

  test "ingest_us_schools/0 is exported so the Cloud Run Job can call it" do
    assert function_exported?(Release, :ingest_us_schools, 0)
  end

  test "migrate/0 is exported so the Docker CMD can call it" do
    assert function_exported?(Release, :migrate, 0)
  end
end
