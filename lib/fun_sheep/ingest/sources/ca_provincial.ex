defmodule FunSheep.Ingest.Sources.CaProvincial do
  @moduledoc """
  Canadian provincial school registries. Education is a provincial
  responsibility in Canada so there is no single federal CSV — each
  province publishes its own open-data portal extract.

  Supported datasets (per province):
    * `"on"` — Ontario public schools (data.ontario.ca)
    * `"bc"` — British Columbia schools (catalogue.data.gov.bc.ca)
    * `"ab"` — Alberta schools (open.alberta.ca)
    * `"qc"` — Quebec schools (donneesquebec.ca)

  Each dataset pulls a different CSV and normalizes its columns into the
  shared `schools` schema. The URL for each province is configurable via
  `Application.put_env(:fun_sheep, __MODULE__, on_url: "...")`.

  Currently only Ontario is implemented with a working URL; add more
  provinces as their column mappings are hand-verified.
  """

  @behaviour FunSheep.Ingest.Source

  require Logger

  alias FunSheep.Geo.{Country, School, State}
  alias FunSheep.Ingest.{Cache, CsvParser, Fetcher, Upsert}
  alias FunSheep.Repo

  import Ecto.Query

  @source "ca_provincial"

  @impl true
  def source, do: @source

  @impl true
  def datasets, do: ["on", "bc", "ab", "qc"]

  @impl true
  def run(dataset, opts \\ [])

  def run("on", opts) do
    url =
      opts[:url] ||
        Application.get_env(:fun_sheep, __MODULE__, [])[:on_url] ||
        raise "Ontario schools CSV URL not configured. " <>
                "Find the current resource at https://data.ontario.ca/dataset/ontario-public-schools " <>
                "and set :on_url in opts or application env."

    ingest_province(url, "ON-schools.csv", "CA-ON", opts)
  end

  def run(dataset, _opts) when dataset in ["bc", "ab", "qc"] do
    {:error,
     {:not_implemented,
      "Canadian province '#{dataset}' ingester not yet implemented — see module docs."}}
  end

  def run(dataset, _opts), do: {:error, {:unknown_dataset, dataset}}

  defp ingest_province(url, filename, state_iso, opts) do
    key = Cache.build_key(@source, filename)

    with {:ok, path} <- Fetcher.fetch(url, key, opts),
         country_id <- ca_country_id(),
         state_id <- ca_state_id(state_iso) do
      rows =
        path
        |> CsvParser.stream()
        |> Stream.map(&row_to_school(&1, country_id, state_id, state_iso))
        |> Stream.reject(&is_nil/1)

      {count, _} = Upsert.run(School, rows, batch_size: 500)
      {:ok, %{inserted: count, updated: 0, rows: count, object_key: key}}
    end
  end

  # Column names differ per province. For Ontario the OnSIS export uses
  # 'School Number', 'School Name', 'School Type', 'Grade Range', etc.
  defp row_to_school(row, country_id, state_id, state_iso) do
    code =
      trim(row["School Number"] || row["school_number"] || row["Board and School Number"])

    name = trim(row["School Name"] || row["school_name"])

    cond do
      is_nil(code) or is_nil(name) ->
        nil

      true ->
        %{
          source: @source,
          source_id: "#{state_iso}-#{code}",
          name: name,
          country_id: country_id,
          state_id: state_id,
          type: ca_type(row["School Type"] || row["School Level"]),
          level: ca_level(row["Grade Range"] || row["School Level"]),
          operational_status: "open",
          address: trim(row["Street"] || row["Address"]),
          city: trim(row["Municipality"] || row["City"]),
          postal_code: trim(row["Postal Code"]),
          phone: trim(row["Phone Number"] || row["Telephone"]),
          website: normalize_url(row["Website"]),
          metadata: %{
            "board_name" => row["Board Name"],
            "board_number" => row["Board Number"],
            "language" => row["Language"],
            "province" => state_iso
          }
        }
    end
  end

  defp ca_type("Public"), do: "public"
  defp ca_type("Catholic"), do: "catholic"
  defp ca_type("Private"), do: "private"
  defp ca_type("First Nations"), do: "indigenous"
  defp ca_type(_), do: "public"

  defp ca_level(nil), do: "other"

  defp ca_level(str) when is_binary(str) do
    s = String.downcase(str)

    cond do
      String.contains?(s, "elem") -> "elementary"
      String.contains?(s, "second") -> "high"
      String.contains?(s, "mid") -> "middle"
      String.contains?(s, "combined") -> "combined"
      String.contains?(s, "k-12") -> "k12"
      true -> "other"
    end
  end

  defp ca_country_id do
    case Repo.get_by(Country, code: "CA") do
      %{id: id} -> id
      nil -> raise "CA country row missing"
    end
  end

  defp ca_state_id(iso) do
    Repo.one(from s in State, where: s.iso_code == ^iso, limit: 1, select: s.id) ||
      raise "CA state #{iso} missing — run seeds with iso_code populated"
  end

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
