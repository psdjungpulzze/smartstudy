defmodule FunSheep.Ingest.Sources.NcesCcd do
  @moduledoc """
  NCES Common Core of Data — the US Department of Education's census of
  ~130K public K-12 schools and ~18K local education agencies (districts).

  Two datasets:
    * `"lea"` — district directory (LEAID, name, state, mailing address,
      operational status, type)
    * `"school"` — school directory (NCESSCH = LEAID + SCHID, grade span,
      locale, lat/lng, school type, charter/magnet flags)

  Source docs: https://nces.ed.gov/ccd/files.asp

  URLs change annually when the new academic year is released. Override
  with `Application.put_env(:fun_sheep, FunSheep.Ingest.Sources.NcesCcd,
  lea_url: "...", school_url: "...")` or pass `url:` in opts when running.
  """

  @behaviour FunSheep.Ingest.Source

  require Logger

  alias FunSheep.Geo.{Country, District, School, State}
  alias FunSheep.Ingest.{Cache, CsvParser, Fetcher, Upsert}
  alias FunSheep.Repo

  import Ecto.Query

  @source "nces_ccd"

  # 2022-23 school year public-use files released 2024-08-29. Update when
  # a newer release is published at https://nces.ed.gov/ccd/files.asp.
  @default_lea_url "https://nces.ed.gov/ccd/Data/zip/ccd_lea_029_2223_w_2a_082924.zip"
  @default_school_url "https://nces.ed.gov/ccd/Data/zip/ccd_sch_029_2223_w_2a_082924.zip"

  @impl true
  def source, do: @source

  @impl true
  def datasets, do: ["lea", "school"]

  @impl true
  def run(dataset, opts \\ [])

  def run("lea", opts) do
    url = config_url(:lea_url, @default_lea_url, opts)
    key = Cache.build_key(@source, "ccd_lea.zip")

    with {:ok, zip_path} <- Fetcher.fetch(url, key, opts),
         {:ok, csv_path} <- extract_first_csv(zip_path, @source, "ccd_lea.csv"),
         state_index <- us_state_index(),
         country_id <- us_country_id() do
      rows =
        csv_path
        |> CsvParser.stream()
        |> Stream.map(&row_to_district(&1, country_id, state_index))
        |> Stream.reject(&is_nil/1)

      {count, _} = Upsert.run(District, rows, batch_size: 500)
      {:ok, %{inserted: count, updated: 0, rows: count, object_key: key}}
    end
  end

  def run("school", opts) do
    url = config_url(:school_url, @default_school_url, opts)
    key = Cache.build_key(@source, "ccd_school.zip")

    with {:ok, zip_path} <- Fetcher.fetch(url, key, opts),
         {:ok, csv_path} <- extract_first_csv(zip_path, @source, "ccd_school.csv"),
         state_index <- us_state_index(),
         district_index <- district_index_by_leaid(),
         country_id <- us_country_id() do
      rows =
        csv_path
        |> CsvParser.stream()
        |> Stream.map(&row_to_school(&1, country_id, state_index, district_index))
        |> Stream.reject(&is_nil/1)

      {count, _} = Upsert.run(School, rows, batch_size: 500)
      {:ok, %{inserted: count, updated: 0, rows: count, object_key: key}}
    end
  end

  def run(dataset, _opts), do: {:error, {:unknown_dataset, dataset}}

  # ── Row → attrs ────────────────────────────────────────────────────────────

  defp row_to_district(row, country_id, state_index) do
    leaid = trim_or_nil(row["LEAID"])
    name = trim_or_nil(row["LEA_NAME"])
    stabr = trim_or_nil(row["STABR"] || row["ST"])

    cond do
      is_nil(leaid) or is_nil(name) ->
        nil

      is_nil(state_index[stabr]) ->
        Logger.debug("ccd.lea unknown state", stabr: stabr, leaid: leaid)
        nil

      true ->
        %{
          source: @source,
          source_id: leaid,
          nces_leaid: leaid,
          name: name,
          country_id: country_id,
          state_id: state_index[stabr],
          type: trim_or_nil(row["LEA_TYPE_TEXT"]),
          operational_status: status_from_text(row["SY_STATUS_TEXT"]),
          address: build_address(row, "L"),
          city: trim_or_nil(row["LCITY"]),
          postal_code: trim_or_nil(row["LZIP"]),
          phone: trim_or_nil(row["PHONE"]),
          website: trim_or_nil(row["WEBSITE"]),
          metadata: %{
            "mailing_address" => build_address(row, "M"),
            "mailing_city" => row["MCITY"],
            "mailing_zip" => row["MZIP"]
          }
        }
    end
  end

  defp row_to_school(row, country_id, state_index, district_index) do
    ncessch = trim_or_nil(row["NCESSCH"])
    name = trim_or_nil(row["SCH_NAME"])
    stabr = trim_or_nil(row["STABR"] || row["ST"])
    leaid = trim_or_nil(row["LEAID"])

    cond do
      is_nil(ncessch) or is_nil(name) ->
        nil

      true ->
        %{
          source: @source,
          source_id: ncessch,
          nces_id: ncessch,
          name: name,
          country_id: country_id,
          state_id: state_index[stabr],
          district_id: district_index[leaid],
          type: school_type(row),
          level: school_level(row["LEVEL"]),
          lowest_grade: trim_or_nil(row["GSLO"]),
          highest_grade: trim_or_nil(row["GSHI"]),
          operational_status: status_from_text(row["SY_STATUS_TEXT"]),
          address: build_address(row, "L"),
          city: trim_or_nil(row["LCITY"]),
          postal_code: trim_or_nil(row["LZIP"]),
          phone: trim_or_nil(row["PHONE"]),
          website: trim_or_nil(row["WEBSITE"]),
          lat: parse_float(row["LATCOD"] || row["LAT1516"]),
          lng: parse_float(row["LONCOD"] || row["LON1516"]),
          locale_code: trim_or_nil(row["LOCALE"]),
          student_count: parse_int(row["TOTAL"] || row["MEMBER"]),
          metadata: %{
            "charter" => trim_or_nil(row["CHARTER_TEXT"]),
            "magnet" => trim_or_nil(row["MAGNET_TEXT"]),
            "title_i" => trim_or_nil(row["TITLEI_STATUS_TEXT"]),
            "st_schid" => row["ST_SCHID"],
            "leaid" => leaid
          }
        }
    end
  end

  # ── Classification helpers ─────────────────────────────────────────────────

  # NCES SCH_TYPE: 1 Regular, 2 Special Education, 3 Vocational, 4 Alternative
  defp school_type(row) do
    cond do
      yes?(row["CHARTER_TEXT"]) -> "charter"
      yes?(row["MAGNET_TEXT"]) -> "magnet"
      true ->
        case trim_or_nil(row["SCH_TYPE_TEXT"]) do
          nil -> "public"
          "Regular school" -> "public"
          "Regular School" -> "public"
          "Special Education School" -> "special"
          "Vocational School" -> "vocational"
          "Alternative Education School" -> "alternative"
          other -> String.downcase(other) |> String.replace(" ", "_")
        end
    end
  end

  defp school_level(nil), do: nil
  defp school_level(val) do
    case String.downcase(val) do
      "primary" -> "elementary"
      "middle" -> "middle"
      "high" -> "high"
      "other" -> "other"
      "not applicable" -> nil
      "not reported" -> nil
      other -> other
    end
  end

  defp status_from_text(nil), do: nil
  defp status_from_text(text) do
    case String.downcase(text) do
      "open" -> "open"
      "closed" -> "closed"
      "new" -> "new"
      "added" -> "new"
      "changed agency" -> "open"
      "reopened" -> "open"
      "future" -> "planned"
      "inactive" -> "inactive"
      _ -> "open"
    end
  end

  defp yes?("Yes"), do: true
  defp yes?("YES"), do: true
  defp yes?("1"), do: true
  defp yes?(_), do: false

  # ── Geo lookups ────────────────────────────────────────────────────────────

  defp us_country_id do
    case Repo.get_by(Country, code: "US") do
      %{id: id} -> id
      nil -> raise "US country row missing — run seeds before ingesting NCES CCD"
    end
  end

  # Returns %{"CA" => state_uuid, "NY" => ..., ...} — keyed by 2-letter abbr.
  # States are looked up by `iso_code` like "US-CA"; fall back to FIPS-based name match.
  defp us_state_index do
    from(s in State,
      where: like(s.iso_code, "US-%"),
      select: {fragment("substring(?, 4)", s.iso_code), s.id}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp district_index_by_leaid do
    from(d in District,
      where: d.source == @source and not is_nil(d.nces_leaid),
      select: {d.nces_leaid, d.id}
    )
    |> Repo.all()
    |> Map.new()
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp config_url(key, default, opts) do
    opts[:url] || Application.get_env(:fun_sheep, __MODULE__, [])[key] || default
  end

  defp extract_first_csv(zip_path, source, cached_as) do
    local_key = Cache.build_key(source, cached_as)
    local = Cache.local_path(local_key)

    if File.exists?(local) do
      {:ok, local}
    else
      File.mkdir_p!(Path.dirname(local))

      case :zip.unzip(String.to_charlist(zip_path),
             cwd: String.to_charlist(Path.dirname(zip_path))
           ) do
        {:ok, files} ->
          case Enum.find(files, fn f ->
                 f |> to_string() |> String.downcase() |> String.ends_with?(".csv")
               end) do
            nil ->
              {:error, :no_csv_in_zip}

            csv_charlist ->
              File.cp!(to_string(csv_charlist), local)
              {:ok, local}
          end

        {:error, reason} ->
          {:error, {:zip, reason}}
      end
    end
  end

  defp build_address(row, prefix) do
    [
      row["#{prefix}STREET1"],
      row["#{prefix}STREET2"]
    ]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" ")
    |> trim_or_nil()
  end

  defp trim_or_nil(nil), do: nil
  defp trim_or_nil(""), do: nil

  defp trim_or_nil(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      t -> t
    end
  end

  defp trim_or_nil(_), do: nil

  defp parse_float(nil), do: nil
  defp parse_float(""), do: nil

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_float(n) when is_number(n), do: n * 1.0

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp parse_int(n) when is_integer(n), do: n
end
