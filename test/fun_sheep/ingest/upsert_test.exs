defmodule FunSheep.Ingest.UpsertTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Geo.School
  alias FunSheep.Ingest.Upsert
  alias FunSheep.IngestFixtures

  setup do
    {us, %{"US-CA" => ca}} = IngestFixtures.seed_us()
    {:ok, country: us, state: ca}
  end

  test "inserts new rows", %{country: us, state: ca} do
    rows = [
      %{
        source: "nces_ccd",
        source_id: "062965005336",
        nces_id: "062965005336",
        name: "Saratoga High",
        country_id: us.id,
        state_id: ca.id,
        type: "public"
      }
    ]

    {count, _} = Upsert.run(School, rows)
    assert count == 1

    [school] = Repo.all(School)
    assert school.name == "Saratoga High"
    assert school.nces_id == "062965005336"
  end

  test "updates existing rows on conflict by (source, source_id)", %{country: us, state: ca} do
    row_v1 = %{
      source: "nces_ccd",
      source_id: "062965005336",
      nces_id: "062965005336",
      name: "Saratoga High",
      country_id: us.id,
      state_id: ca.id,
      type: "public"
    }

    Upsert.run(School, [row_v1])

    row_v2 = %{row_v1 | name: "Saratoga High School", type: "charter"}
    Upsert.run(School, [row_v2])

    [school] = Repo.all(School)
    assert school.name == "Saratoga High School"
    assert school.type == "charter"
    # PK stays stable so FKs from user_roles/courses/questions aren't broken
    assert Repo.aggregate(School, :count) == 1
  end

  test "batches large inputs", %{country: us, state: ca} do
    rows =
      for i <- 1..50 do
        %{
          source: "test",
          source_id: "id#{i}",
          name: "School #{i}",
          country_id: us.id,
          state_id: ca.id
        }
      end

    {count, _} = Upsert.run(School, rows, batch_size: 10)
    assert count == 50
    assert Repo.aggregate(School, :count) == 50
  end
end
