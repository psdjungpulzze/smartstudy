defmodule FunSheep.Ingest.Sources.Whed do
  @moduledoc """
  Global higher-education ingester, sourced from the Research Organization
  Registry (ROR) — https://ror.org. ROR publishes a CC0-licensed monthly
  dump on Zenodo containing ~100K research organizations worldwide with
  stable IDs, cross-references (GRID, ISNI, Wikidata, Crossref), and
  geo-coordinates.

  Why ROR rather than WHED? The IAU/UNESCO World Higher Education
  Database (whed.net) is excellent but not freely downloadable in bulk —
  programmatic access requires an institutional license. ROR covers every
  degree-granting institution we care about, under CC0, with a stable
  public API.

  Natural key: ROR ID (e.g. `https://ror.org/02mhbdp94` or just
  `02mhbdp94`). Stored as `universities.ror_id` and `universities.source_id`.

  Dump URL pattern:
      https://zenodo.org/records/{record}/files/v{version}-{yyyy}-{mm}-{dd}-ror-data.zip

  Latest records published at https://zenodo.org/communities/ror-data.
  Pass `url:` in opts with the concrete release URL.

  WHED integration (requires license) can be added as a separate dataset
  once access is procured.
  """

  @behaviour FunSheep.Ingest.Source

  require Logger

  alias FunSheep.Geo.{Country, University}
  alias FunSheep.Ingest.{Cache, Fetcher, Upsert}
  alias FunSheep.Repo

  @source "ror"

  @impl true
  def source, do: @source

  @impl true
  def datasets, do: ["universities", "whed_licensed"]

  @impl true
  def run(dataset, opts \\ [])

  def run("universities", opts) do
    url =
      opts[:url] ||
        Application.get_env(:fun_sheep, __MODULE__, [])[:ror_dump_url] ||
        raise "ROR dump URL not configured. " <>
                "Find the current release at https://zenodo.org/communities/ror-data " <>
                "and set :ror_dump_url in opts or application env."

    key = Cache.build_key(@source, "ror_dump.zip")

    with {:ok, zip_path} <- Fetcher.fetch(url, key, opts),
         {:ok, json_path} <- extract_json(zip_path),
         country_index <- country_index() do
      rows =
        json_path
        |> File.read!()
        |> Jason.decode!()
        |> Enum.filter(&is_educational?/1)
        |> Enum.map(&row_to_university(&1, country_index))
        |> Enum.reject(&is_nil/1)

      {count, _} = Upsert.run(University, rows, batch_size: 500)
      {:ok, %{inserted: count, updated: 0, rows: count, object_key: key}}
    end
  end

  def run("whed_licensed", _opts) do
    {:error,
     {:not_implemented,
      "WHED integration requires an IAU/UNESCO license. Contact portal.whed.net. " <>
        "ROR dataset covers the same institutions under CC0."}}
  end

  def run(dataset, _opts), do: {:error, {:unknown_dataset, dataset}}

  # ── Classification ────────────────────────────────────────────────────────

  # ROR `types` include: Education, Healthcare, Company, Government, Nonprofit,
  # Facility, Archive, Other. We want Education primarily.
  defp is_educational?(%{"types" => types}) when is_list(types) do
    "Education" in types
  end

  defp is_educational?(_), do: false

  # ROR record shape (abbreviated):
  #   {
  #     "id": "https://ror.org/02mhbdp94",
  #     "name": "University of Toronto",
  #     "types": ["Education"],
  #     "country": {"country_code": "CA", "country_name": "Canada"},
  #     "addresses": [{"city": "Toronto", "lat": 43.66, "lng": -79.39, "state_code": "CA-ON", ...}],
  #     "links": ["https://www.utoronto.ca/"],
  #     "external_ids": {"ISNI": {...}, "GRID": {...}, "Wikidata": {...}},
  #     "status": "active"
  #   }
  defp row_to_university(record, country_index) do
    ror_full = record["id"]
    ror_id = extract_ror_id(ror_full)
    name = record["name"]
    country_code = get_in(record, ["country", "country_code"])

    cond do
      is_nil(ror_id) or is_nil(name) ->
        nil

      record["status"] != "active" ->
        nil

      is_nil(country_index[country_code]) ->
        nil

      true ->
        addresses = record["addresses"] || []
        primary_addr = List.first(addresses) || %{}

        %{
          source: @source,
          source_id: ror_id,
          ror_id: ror_id,
          name: name,
          country_id: country_index[country_code],
          state_id: nil,
          type: type_from_record(record),
          operational_status: "open",
          city: primary_addr["city"],
          lat: as_float(primary_addr["lat"]),
          lng: as_float(primary_addr["lng"]),
          website: List.first(record["links"] || []),
          metadata: %{
            "ror_full_id" => ror_full,
            "aliases" => record["aliases"],
            "acronyms" => record["acronyms"],
            "labels" => record["labels"],
            "external_ids" => record["external_ids"],
            "wikipedia_url" => record["wikipedia_url"],
            "country_code" => country_code
          }
        }
    end
  end

  defp extract_ror_id(nil), do: nil

  defp extract_ror_id(full) when is_binary(full) do
    full |> String.split("/") |> List.last()
  end

  defp type_from_record(%{"types" => types}) when is_list(types) do
    cond do
      "Education" in types -> "university"
      true -> "other"
    end
  end

  defp type_from_record(_), do: "university"

  # ── Geo lookups ────────────────────────────────────────────────────────────

  defp country_index do
    Repo.all(Country)
    |> Enum.map(fn c -> {c.code, c.id} end)
    |> Map.new()
  end

  defp extract_json(zip_path) do
    case :zip.unzip(String.to_charlist(zip_path),
           cwd: String.to_charlist(Path.dirname(zip_path))
         ) do
      {:ok, files} ->
        case Enum.find(files, fn f ->
               f |> to_string() |> String.downcase() |> String.ends_with?(".json")
             end) do
          nil -> {:error, :no_json_in_zip}
          json -> {:ok, to_string(json)}
        end

      {:error, reason} ->
        {:error, {:zip, reason}}
    end
  end

  defp as_float(nil), do: nil
  defp as_float(n) when is_number(n), do: n * 1.0

  defp as_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end
end
