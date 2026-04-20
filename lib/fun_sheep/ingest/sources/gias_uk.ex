defmodule FunSheep.Ingest.Sources.GiasUk do
  @moduledoc """
  GIAS (Get Information About Schools) — UK Department for Education's
  register of every establishment in England (~32K). Wales, Scotland, and
  Northern Ireland maintain separate registries and are ingested via
  different sources (not yet implemented).

  Natural key: URN (Unique Reference Number). Stored as `schools.urn` and
  `schools.source_id`.

  Source docs: https://get-information-schools.service.gov.uk/Downloads
  Daily "all establishment data" CSV:
      https://ea-edubase-api-prod.azurewebsites.net/edubase/edubasealldataYYYYMMDD.csv
  """

  @behaviour FunSheep.Ingest.Source

  require Logger

  alias FunSheep.Geo.{Country, School, State}
  alias FunSheep.Ingest.{Cache, CsvParser, Fetcher, Upsert}
  alias FunSheep.Repo

  import Ecto.Query

  @source "gias_uk"

  @impl true
  def source, do: @source

  @impl true
  def datasets, do: ["establishments"]

  @impl true
  def run(dataset, opts \\ [])

  def run("establishments", opts) do
    date = opts[:date] || Date.utc_today()
    yyyymmdd = Calendar.strftime(date, "%Y%m%d")

    url =
      opts[:url] ||
        Application.get_env(:fun_sheep, __MODULE__, [])[:url] ||
        "https://ea-edubase-api-prod.azurewebsites.net/edubase/edubasealldata#{yyyymmdd}.csv"

    key = Cache.build_key(@source, "gias_all_#{yyyymmdd}.csv", date)

    with {:ok, path} <- Fetcher.fetch(url, key, opts),
         country_id <- gb_country_id(),
         england_id <- england_state_id() do
      rows =
        path
        |> CsvParser.stream(encoding: :latin1)
        |> Stream.map(&row_to_school(&1, country_id, england_id))
        |> Stream.reject(&is_nil/1)

      {count, _} = Upsert.run(School, rows, batch_size: 500)
      {:ok, %{inserted: count, updated: 0, rows: count, object_key: key}}
    end
  end

  def run(dataset, _opts), do: {:error, {:unknown_dataset, dataset}}

  defp row_to_school(row, country_id, state_id) do
    urn = trim(row["URN"])
    name = trim(row["EstablishmentName"])
    status = trim(row["EstablishmentStatus (name)"])

    cond do
      is_nil(urn) or is_nil(name) ->
        nil

      status in ["Closed", "Proposed to close"] ->
        nil

      true ->
        %{
          source: @source,
          source_id: urn,
          urn: urn,
          name: name,
          country_id: country_id,
          state_id: state_id,
          type: uk_type(row["EstablishmentTypeGroup (name)"]),
          level: uk_level(row["PhaseOfEducation (name)"]),
          lowest_grade: trim(row["StatutoryLowAge"]),
          highest_grade: trim(row["StatutoryHighAge"]),
          operational_status: uk_status(status),
          address: build_address(row),
          city: trim(row["Town"]),
          postal_code: trim(row["Postcode"]),
          phone: trim(row["TelephoneNum"]),
          website: normalize_url(row["SchoolWebsite"]),
          student_count: parse_int(row["NumberOfPupils"]),
          opened_at: parse_uk_date(row["OpenDate"]),
          closed_at: parse_uk_date(row["CloseDate"]),
          metadata: %{
            "la_code" => row["LA (code)"],
            "la_name" => row["LA (name)"],
            "type_detail" => row["TypeOfEstablishment (name)"],
            "ukprn" => row["UKPRN"],
            "ofsted_rating" => row["OfstedRating (name)"],
            "religious_character" => row["ReligiousCharacter (name)"],
            "gor" => row["GOR (name)"]
          }
        }
    end
  end

  defp uk_type("Academies"), do: "academy"
  defp uk_type("Free Schools"), do: "free_school"
  defp uk_type("Independent schools"), do: "private"
  defp uk_type("Local authority maintained schools"), do: "public"
  defp uk_type("Special schools"), do: "special"
  defp uk_type("Colleges"), do: "college"
  defp uk_type("Universities"), do: "university"
  defp uk_type(_), do: "public"

  defp uk_level("Primary"), do: "elementary"
  defp uk_level("Middle Deemed Primary"), do: "elementary"
  defp uk_level("Middle Deemed Secondary"), do: "middle"
  defp uk_level("Secondary"), do: "high"
  defp uk_level("16 plus"), do: "high"
  defp uk_level("All-through"), do: "combined"
  defp uk_level("Nursery"), do: "kindergarten"
  defp uk_level(_), do: "other"

  defp uk_status("Open"), do: "open"
  defp uk_status("Open, but proposed to close"), do: "open"
  defp uk_status("Closed"), do: "closed"
  defp uk_status("Proposed to close"), do: "planned"
  defp uk_status(_), do: "open"

  defp build_address(row) do
    [row["Street"], row["Locality"], row["Address3"]]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(", ")
    |> case do
      "" -> nil
      s -> s
    end
  end

  defp gb_country_id do
    case Repo.get_by(Country, code: "GB") do
      %{id: id} -> id
      nil -> raise "GB country row missing"
    end
  end

  defp england_state_id do
    Repo.one(from s in State, where: s.name == "England", limit: 1, select: s.id) ||
      Repo.one(from s in State, where: s.iso_code == "GB-ENG", limit: 1, select: s.id)
  end

  defp parse_uk_date(nil), do: nil
  defp parse_uk_date(""), do: nil

  defp parse_uk_date(s) when is_binary(s) do
    # GIAS uses "DD-MM-YYYY"
    case String.split(s, "-") do
      [d, m, y] ->
        with {di, _} <- Integer.parse(d),
             {mi, _} <- Integer.parse(m),
             {yi, _} <- Integer.parse(y),
             {:ok, date} <- Date.new(yi, mi, di) do
          date
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_uk_date(_), do: nil

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp parse_int(n) when is_integer(n), do: n

  defp normalize_url(nil), do: nil
  defp normalize_url(""), do: nil

  defp normalize_url(url) when is_binary(url) do
    case String.trim(url) do
      "" -> nil
      u -> if String.starts_with?(u, "http"), do: u, else: "http://" <> u
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
