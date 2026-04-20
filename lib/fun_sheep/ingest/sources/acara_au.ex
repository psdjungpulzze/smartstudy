defmodule FunSheep.Ingest.Sources.AcaraAu do
  @moduledoc """
  ACARA (Australian Curriculum, Assessment and Reporting Authority) school
  locations — ~9,500 government, Catholic, and independent schools across
  Australia's 8 states/territories.

  Natural key: ACARA ID (also referred to as "Local School ID"). Stored as
  `schools.acara_id` and `schools.source_id`.

  Source: https://data.gov.au/dataset/australian-schools-list
  (ACARA publishes the annual school locations CSV on data.gov.au.)
  """

  @behaviour FunSheep.Ingest.Source

  require Logger

  alias FunSheep.Geo.{Country, School, State}
  alias FunSheep.Ingest.{Cache, CsvParser, Fetcher, Upsert}
  alias FunSheep.Repo

  import Ecto.Query

  @source "acara_au"

  @au_state_iso %{
    "ACT" => "AU-ACT",
    "NSW" => "AU-NSW",
    "NT" => "AU-NT",
    "QLD" => "AU-QLD",
    "SA" => "AU-SA",
    "TAS" => "AU-TAS",
    "VIC" => "AU-VIC",
    "WA" => "AU-WA"
  }

  @impl true
  def source, do: @source

  @impl true
  def datasets, do: ["locations"]

  @impl true
  def run(dataset, opts \\ [])

  def run("locations", opts) do
    url =
      opts[:url] ||
        Application.get_env(:fun_sheep, __MODULE__, [])[:url] ||
        raise "ACARA URL not configured — set :url in opts or application env. " <>
                "See https://data.gov.au/dataset/australian-schools-list for the " <>
                "current annual CSV link."

    key = Cache.build_key(@source, "acara_schools.csv")

    with {:ok, path} <- Fetcher.fetch(url, key, opts),
         country_id <- au_country_id(),
         state_index <- au_state_index() do
      rows =
        path
        |> CsvParser.stream()
        |> Stream.map(&row_to_school(&1, country_id, state_index))
        |> Stream.reject(&is_nil/1)

      {count, _} = Upsert.run(School, rows, batch_size: 500)
      {:ok, %{inserted: count, updated: 0, rows: count, object_key: key}}
    end
  end

  def run(dataset, _opts), do: {:error, {:unknown_dataset, dataset}}

  # ACARA column names vary year-to-year; this covers the common set seen
  # on recent releases. Extend as new fields appear.
  defp row_to_school(row, country_id, state_index) do
    acara_id = trim(row["ACARA School ID"] || row["ACARA_ID"] || row["School ID"])
    name = trim(row["School Name"] || row["SchoolName"])
    state_abbr = trim(row["State"] || row["State/Territory"] || row["STE_NAME"])
    iso = @au_state_iso[state_abbr]

    cond do
      is_nil(acara_id) or is_nil(name) ->
        nil

      is_nil(iso) ->
        nil

      true ->
        %{
          source: @source,
          source_id: acara_id,
          acara_id: acara_id,
          name: name,
          country_id: country_id,
          state_id: state_index[iso],
          type: au_type(row["School Sector"] || row["Sector"]),
          level: au_level(row["School Type"] || row["Type"]),
          operational_status: "open",
          address: trim(row["Street"]),
          city: trim(row["Suburb"] || row["Locality"]),
          postal_code: trim(row["Postcode"]),
          phone: trim(row["Phone"]),
          website: normalize_url(row["Website"]),
          lat: parse_float(row["Latitude"]),
          lng: parse_float(row["Longitude"]),
          metadata: %{
            "sector" => row["School Sector"] || row["Sector"],
            "type" => row["School Type"] || row["Type"],
            "icsea" => row["ICSEA"],
            "remoteness" => row["Geolocation"],
            "indigenous_enrolments" => row["Indigenous enrolments (%)"]
          }
        }
    end
  end

  defp au_type("Government"), do: "public"
  defp au_type("Catholic"), do: "catholic"
  defp au_type("Independent"), do: "private"
  defp au_type(_), do: "public"

  defp au_level("Primary"), do: "elementary"
  defp au_level("Secondary"), do: "high"
  defp au_level("Combined"), do: "combined"
  defp au_level("Special"), do: "special"
  defp au_level(_), do: "other"

  defp au_country_id do
    case Repo.get_by(Country, code: "AU") do
      %{id: id} -> id
      nil -> raise "AU country row missing"
    end
  end

  defp au_state_index do
    from(s in State,
      where: like(s.iso_code, "AU-%"),
      select: {s.iso_code, s.id}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp parse_float(nil), do: nil
  defp parse_float(""), do: nil

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_float(n) when is_number(n), do: n * 1.0

  defp normalize_url(nil), do: nil
  defp normalize_url(""), do: nil

  defp normalize_url(u) when is_binary(u) do
    case String.trim(u) do
      "" -> nil
      t -> if String.starts_with?(t, "http"), do: t, else: "http://" <> t
    end
  end

  defp trim(nil), do: nil
  defp trim(""), do: nil

  defp trim(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      t -> t
    end
  end

  defp trim(_), do: nil
end
