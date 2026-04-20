defmodule FunSheep.IngestTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Ingest

  test "lookup/1 finds every registered source" do
    assert {:ok, FunSheep.Ingest.Sources.NcesCcd} = Ingest.lookup("nces_ccd")
    assert {:ok, FunSheep.Ingest.Sources.KrNeis} = Ingest.lookup("kr_neis")
    assert {:ok, FunSheep.Ingest.Sources.Ipeds} = Ingest.lookup("ipeds")
    assert {:ok, FunSheep.Ingest.Sources.GiasUk} = Ingest.lookup("gias_uk")
    assert {:ok, FunSheep.Ingest.Sources.AcaraAu} = Ingest.lookup("acara_au")
    assert {:ok, FunSheep.Ingest.Sources.CaProvincial} = Ingest.lookup("ca_provincial")
    assert {:ok, FunSheep.Ingest.Sources.Whed} = Ingest.lookup("ror")
    assert {:ok, FunSheep.Ingest.Sources.IbWorldSchools} = Ingest.lookup("ib")
    assert :error = Ingest.lookup("no_such_source")
  end

  test "sources/0 returns every registered source tuple" do
    keys = Ingest.sources() |> Enum.map(&elem(&1, 0))

    for expected <- ~w(nces_ccd ipeds kr_neis gias_uk acara_au ca_provincial ror ib) do
      assert expected in keys, "expected source `#{expected}` to be registered"
    end
  end

  test "run/2 with unknown source returns error tuple" do
    assert {:error, {:unknown_source, "nope"}} = Ingest.run("nope", "whatever")
  end

  test "every registered source module implements the behaviour" do
    for {_name, mod} <- Ingest.sources() do
      Code.ensure_loaded!(mod)

      assert function_exported?(mod, :source, 0),
             "#{inspect(mod)} must export source/0"

      assert function_exported?(mod, :datasets, 0),
             "#{inspect(mod)} must export datasets/0"

      assert function_exported?(mod, :run, 2),
             "#{inspect(mod)} must export run/2"
    end
  end
end
