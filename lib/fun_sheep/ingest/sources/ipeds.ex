defmodule FunSheep.Ingest.Sources.Ipeds do
  @moduledoc """
  IPEDS Institutional Characteristics directory — every postsecondary
  institution eligible to receive Title IV US federal financial aid
  (~6,000 colleges and universities).

  Primary natural key: UNITID (6-digit). OPEID is also kept for
  cross-reference with the College Scorecard API.

  Source docs: https://nces.ed.gov/ipeds/use-the-data/download-access-database
  Annual HD (Header/Directory) file URL: https://nces.ed.gov/ipeds/datacenter/data/HDYYYY.zip
  """

  @behaviour FunSheep.Ingest.Source

  require Logger

  alias FunSheep.Geo.{Country, State, University}
  alias FunSheep.Ingest.{Cache, CsvParser, Fetcher, Upsert}
  alias FunSheep.Repo

  import Ecto.Query

  @source "ipeds"
  # HD{YYYY}.zip — academic year. Verified HD2022, HD2023, HD2024 all
  # return 200. HD2024 is the most recent as of 2026-04.
  @default_hd_url "https://nces.ed.gov/ipeds/datacenter/data/HD2024.zip"

  @impl true
  def source, do: @source

  @impl true
  def datasets, do: ["hd"]

  @impl true
  def run(dataset, opts \\ [])

  def run("hd", opts) do
    url =
      opts[:url] || Application.get_env(:fun_sheep, __MODULE__, [])[:hd_url] || @default_hd_url

    key = Cache.build_key(@source, "ipeds_hd.zip")

    with {:ok, zip_path} <- Fetcher.fetch(url, key, opts),
         {:ok, csv_path} <- extract_csv(zip_path),
         country_id <- us_country_id(),
         state_index <- us_state_index() do
      # IPEDS HD is distributed as latin1-ish; NimbleCSV handles binary safely
      # and institution names are ASCII-clean in practice.
      rows =
        csv_path
        |> CsvParser.stream()
        |> Stream.map(&row_to_university(&1, country_id, state_index))
        |> Stream.reject(&is_nil/1)

      {count, _} = Upsert.run(University, rows, batch_size: 500)
      {:ok, %{inserted: count, updated: 0, rows: count, object_key: key}}
    end
  end

  def run(dataset, _opts), do: {:error, {:unknown_dataset, dataset}}

  defp row_to_university(row, country_id, state_index) do
    unitid = trim(row["UNITID"])
    name = trim(row["INSTNM"])
    stabbr = trim(row["STABBR"])

    cond do
      is_nil(unitid) or is_nil(name) ->
        nil

      trim(row["CYACTIVE"]) == "2" and trim(row["CLOSEDAT"]) not in [nil, "-2", "."] ->
        # CYACTIVE=2 + CLOSEDAT present => closed. Skip entirely rather
        # than surface dead institutions to students.
        nil

      true ->
        %{
          source: @source,
          source_id: unitid,
          ipeds_unitid: unitid,
          opeid: trim(row["OPEID"]),
          name: name,
          country_id: country_id,
          state_id: state_index[stabbr],
          control: control_name(row["CONTROL"]),
          level: level_name(row["ICLEVEL"]),
          type: sector_name(row["SECTOR"]),
          operational_status: operational_status(row),
          address: trim(row["ADDR"]),
          city: trim(row["CITY"]),
          postal_code: trim(row["ZIP"]),
          phone: trim(row["GENTELE"]),
          website: normalize_url(row["WEBADDR"]),
          lat: parse_float(row["LATITUDE"]),
          lng: parse_float(row["LONGITUD"]),
          metadata: %{
            "ein" => row["EIN"],
            "sector" => row["SECTOR"],
            "hloffer" => row["HLOFFER"],
            "locale" => row["LOCALE"],
            "obereg" => row["OBEREG"]
          }
        }
    end
  end

  defp control_name("1"), do: "public"
  defp control_name("2"), do: "private_nonprofit"
  defp control_name("3"), do: "private_forprofit"
  defp control_name(_), do: nil

  defp level_name("1"), do: "4-year"
  defp level_name("2"), do: "2-year"
  defp level_name("3"), do: "less-than-2-year"
  defp level_name(_), do: nil

  # SECTOR values 1..9 — combine control + level in a human-readable way
  defp sector_name("1"), do: "4-year public"
  defp sector_name("2"), do: "4-year private nonprofit"
  defp sector_name("3"), do: "4-year private for-profit"
  defp sector_name("4"), do: "2-year public"
  defp sector_name("5"), do: "2-year private nonprofit"
  defp sector_name("6"), do: "2-year private for-profit"
  defp sector_name("7"), do: "less-than-2-year public"
  defp sector_name("8"), do: "less-than-2-year private nonprofit"
  defp sector_name("9"), do: "less-than-2-year private for-profit"
  defp sector_name(_), do: nil

  defp operational_status(row) do
    case {trim(row["CYACTIVE"]), trim(row["OPENPUBL"])} do
      {"1", _} -> "open"
      {_, "1"} -> "open"
      {"2", _} -> "closed"
      _ -> "open"
    end
  end

  defp us_country_id do
    case Repo.get_by(Country, code: "US") do
      %{id: id} -> id
      nil -> raise "US country row missing — run seeds before ingesting IPEDS"
    end
  end

  defp us_state_index do
    from(s in State,
      where: like(s.iso_code, "US-%"),
      select: {fragment("substring(?, 4)", s.iso_code), s.id}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp extract_csv(zip_path) do
    case :zip.unzip(String.to_charlist(zip_path),
           cwd: String.to_charlist(Path.dirname(zip_path))
         ) do
      {:ok, files} ->
        case Enum.find(files, fn f ->
               f |> to_string() |> String.downcase() |> String.ends_with?(".csv")
             end) do
          nil -> {:error, :no_csv_in_zip}
          csv -> {:ok, to_string(csv)}
        end

      {:error, reason} ->
        {:error, {:zip, reason}}
    end
  end

  defp normalize_url(nil), do: nil
  defp normalize_url(""), do: nil

  defp normalize_url(url) when is_binary(url) do
    trimmed = String.trim(url)

    cond do
      trimmed == "" -> nil
      String.starts_with?(trimmed, "http") -> trimmed
      true -> "https://" <> trimmed
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

  defp parse_float(nil), do: nil
  defp parse_float(""), do: nil

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_float(n) when is_number(n), do: n * 1.0
end
