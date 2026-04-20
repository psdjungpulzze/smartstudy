defmodule FunSheep.Ingest.CsvParserTest do
  use ExUnit.Case, async: true

  alias FunSheep.Ingest.CsvParser
  alias FunSheep.IngestFixtures

  test "streams rows as maps keyed by header" do
    path =
      IngestFixtures.write_tmp_csv("""
      NCESSCH,SCH_NAME,STABR
      062965005336,Saratoga High School,CA
      062965005337,Los Gatos High School,CA
      """)

    rows = path |> CsvParser.stream() |> Enum.to_list()

    assert length(rows) == 2
    assert Enum.at(rows, 0)["SCH_NAME"] == "Saratoga High School"
    assert Enum.at(rows, 0)["NCESSCH"] == "062965005336"
    assert Enum.at(rows, 1)["STABR"] == "CA"
  end

  test "strips UTF-8 BOM from first field" do
    path = IngestFixtures.write_tmp_csv("\uFEFFURN,Name\n100001,Test School\n")
    [row] = path |> CsvParser.stream() |> Enum.to_list()
    assert row["URN"] == "100001"
  end

  test "handles quoted fields with embedded commas" do
    path =
      IngestFixtures.write_tmp_csv("""
      URN,Name,Address
      100002,"Smith, John School","123 Main St, Suite 4"
      """)

    [row] = path |> CsvParser.stream() |> Enum.to_list()
    assert row["Name"] == "Smith, John School"
    assert row["Address"] == "123 Main St, Suite 4"
  end

  test "nilifies empty fields" do
    path = IngestFixtures.write_tmp_csv("URN,Name,Website\n100003,X,\n")
    [row] = path |> CsvParser.stream() |> Enum.to_list()
    assert row["Website"] == nil
  end
end
