defmodule FunSheep.IngestFixtures do
  @moduledoc """
  Helpers for seeding geo data needed by ingester tests without hitting
  the network.
  """

  alias FunSheep.Repo
  alias FunSheep.Geo.{Country, State}

  def seed_us do
    {:ok, us} =
      %Country{}
      |> Country.changeset(%{name: "United States", code: "US", iso3: "USA"})
      |> Repo.insert()

    states = [
      {"US-CA", "California"},
      {"US-NY", "New York"},
      {"US-TX", "Texas"}
    ]

    state_map =
      for {iso, name} <- states, into: %{} do
        {:ok, s} =
          %State{}
          |> State.changeset(%{name: name, iso_code: iso, country_id: us.id})
          |> Repo.insert()

        {iso, s}
      end

    {us, state_map}
  end

  def seed_kr do
    {:ok, kr} =
      %Country{}
      |> Country.changeset(%{name: "South Korea", code: "KR", iso3: "KOR"})
      |> Repo.insert()

    {:ok, seoul} =
      %State{}
      |> State.changeset(%{name: "Seoul", iso_code: "KR-11", country_id: kr.id})
      |> Repo.insert()

    {kr, %{"KR-11" => seoul}}
  end

  @doc "Writes `content` to a tmp CSV and returns its path."
  def write_tmp_csv(content) do
    path =
      Path.join(System.tmp_dir!(), "fs_ingest_#{System.unique_integer([:positive])}.csv")

    File.write!(path, content)
    path
  end
end
