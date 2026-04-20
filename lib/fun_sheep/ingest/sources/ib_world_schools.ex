defmodule FunSheep.Ingest.Sources.IbWorldSchools do
  @moduledoc """
  International Baccalaureate (IB) World Schools directory — ~5,000
  schools offering PYP/MYP/DP/CP across 150+ countries.

  IB does not publish a bulk CSV or public API. The "Find an IB World
  School" tool at https://www.ibo.org/find-an-ib-school/ is the only
  source. Options:

    1. **Manual scraping** (implemented below when a scraped JSON feed is
       provided) — respect their robots.txt and cache aggressively.
    2. **ISC Research** (paid) — provides IB-tagged records in their
       commercial dataset.
    3. **National registries first** — most IB schools are also registered
       with their country's education ministry (NCES, GIAS, NEIS, ACARA),
       so the `metadata.ib_programmes` field on those records already
       captures some IB presence.

  This module only activates when a path to a locally-saved JSON snapshot
  of the IB directory is supplied. Pass `path:` in opts with the JSON file
  (array of `{school_id, name, country, city, programmes}` maps).
  """

  @behaviour FunSheep.Ingest.Source

  require Logger

  alias FunSheep.Geo.{Country, School}
  alias FunSheep.Ingest.Upsert
  alias FunSheep.Repo

  @source "ib"

  @impl true
  def source, do: @source

  @impl true
  def datasets, do: ["directory"]

  @impl true
  def run(dataset, opts \\ [])

  def run("directory", opts) do
    path = opts[:path] || Application.get_env(:fun_sheep, __MODULE__, [])[:directory_path]

    case path do
      nil ->
        {:error,
         {:not_implemented,
          "IB directory requires a scraped snapshot. Pass path: \"ib.json\" in opts."}}

      p when is_binary(p) ->
        country_index = country_index()

        rows =
          p
          |> File.read!()
          |> Jason.decode!()
          |> Enum.map(&row_to_school(&1, country_index))
          |> Enum.reject(&is_nil/1)

        {count, _} = Upsert.run(School, rows, batch_size: 500)
        {:ok, %{inserted: count, updated: 0, rows: count}}
    end
  end

  def run(dataset, _opts), do: {:error, {:unknown_dataset, dataset}}

  defp row_to_school(record, country_index) do
    school_id = record["school_id"] || record["id"]
    name = record["name"]
    country_code = record["country_code"] || record["country"]

    cond do
      is_nil(school_id) or is_nil(name) ->
        nil

      is_nil(country_index[country_code]) ->
        nil

      true ->
        %{
          source: @source,
          source_id: to_string(school_id),
          ib_code: to_string(school_id),
          name: name,
          country_id: country_index[country_code],
          type: "international",
          operational_status: "open",
          city: record["city"],
          website: record["website"],
          metadata: %{
            "programmes" => record["programmes"],
            "curriculum" => "IB"
          }
        }
    end
  end

  defp country_index do
    Repo.all(Country) |> Enum.map(fn c -> {c.code, c.id} end) |> Map.new()
  end
end
