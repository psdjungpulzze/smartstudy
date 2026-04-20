defmodule FunSheep.Ingest.Sources.Whed do
  @moduledoc """
  Global higher-education ingester, sourced from the Research Organization
  Registry (ROR) — https://ror.org. ROR publishes a CC0-licensed monthly
  dump on Zenodo containing ~120K research organizations worldwide with
  stable IDs, cross-references (GRID, ISNI, Wikidata, Crossref), and
  geo-coordinates.

  Why ROR rather than WHED? The IAU/UNESCO World Higher Education
  Database (whed.net) is excellent but not freely downloadable in bulk —
  programmatic access requires an institutional license. ROR covers every
  degree-granting institution we care about, under CC0, with a stable
  public API.

  Natural key: ROR ID (e.g. `https://ror.org/02mhbdp94` or just
  `02mhbdp94`). Stored as `universities.ror_id` and `universities.source_id`.

  Uses the v2 schema (v1 was deprecated 2025-12-08). Default URL points at
  the January 2026 release; override with `--url` for newer releases at
  https://zenodo.org/communities/ror-data/records.

  WHED integration (requires license) can be added as a separate dataset
  once access is procured.
  """

  @behaviour FunSheep.Ingest.Source

  require Logger

  alias FunSheep.Geo.{Country, University}
  alias FunSheep.Ingest.{Cache, Fetcher, Upsert}
  alias FunSheep.Repo

  @source "ror"

  # v2.2 release published 2026-01-29, 121,920 organizations.
  @default_ror_url "https://zenodo.org/records/18419061/files/v2.2-2026-01-29-ror-data.zip?download=1"

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
        @default_ror_url

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

  # ROR v2 `types` is a lowercase list including "education", "healthcare",
  # "company", "government", "nonprofit", "facility", "archive", "other",
  # "funder". We want anything tagged as "education".
  defp is_educational?(%{"types" => types}) when is_list(types) do
    "education" in types or "Education" in types
  end

  defp is_educational?(_), do: false

  # v2 record shape (key fields):
  #   "id": "https://ror.org/02mhbdp94"
  #   "names": [{"lang": "en", "types": ["ror_display", "label"], "value": "..."}, ...]
  #   "locations": [{"geonames_details": {"country_code": "CA", "lat": ..., "lng": ..., "name": "Toronto", ...}}, ...]
  #   "links": [{"type": "website", "value": "..."}, {"type": "wikipedia", "value": "..."}]
  #   "external_ids": [{"type": "grid", "preferred": "...", "all": [...]}, ...]
  #   "status": "active"
  #   "types": ["education"]
  defp row_to_university(record, country_index) do
    ror_full = record["id"]
    ror_id = extract_ror_id(ror_full)
    name = display_name(record["names"])
    primary_loc = List.first(record["locations"] || []) || %{}
    geo = primary_loc["geonames_details"] || %{}
    country_code = geo["country_code"]

    cond do
      is_nil(ror_id) or is_nil(name) ->
        nil

      record["status"] != "active" ->
        nil

      is_nil(country_index[country_code]) ->
        nil

      true ->
        %{
          source: @source,
          source_id: ror_id,
          ror_id: ror_id,
          name: name,
          native_name: native_name(record["names"]),
          country_id: country_index[country_code],
          state_id: nil,
          type: "university",
          operational_status: "open",
          city: geo["name"],
          lat: as_float(geo["lat"]),
          lng: as_float(geo["lng"]),
          website: primary_link(record["links"]),
          metadata: %{
            "ror_full_id" => ror_full,
            "established" => record["established"],
            "domains" => record["domains"],
            "types" => record["types"],
            "external_ids" => flatten_external_ids(record["external_ids"]),
            "wikipedia_url" => wikipedia_link(record["links"]),
            "country_code" => country_code,
            "country_subdivision" => geo["country_subdivision_name"]
          }
        }
    end
  end

  # Pick the display name ("ror_display" type) or fall back to first "label".
  defp display_name(names) when is_list(names) do
    Enum.find_value(names, fn
      %{"types" => types, "value" => v} when is_list(types) ->
        if "ror_display" in types, do: v
    end) ||
      Enum.find_value(names, fn
        %{"types" => types, "value" => v} when is_list(types) ->
          if "label" in types, do: v
      end) ||
      case names do
        [%{"value" => v} | _] -> v
        _ -> nil
      end
  end

  defp display_name(_), do: nil

  defp native_name(names) when is_list(names) do
    Enum.find_value(names, fn
      %{"types" => types, "value" => v, "lang" => lang}
      when is_list(types) and is_binary(lang) and lang != "en" ->
        if "label" in types, do: v
    end)
  end

  defp native_name(_), do: nil

  defp primary_link(links) when is_list(links) do
    Enum.find_value(links, fn
      %{"type" => "website", "value" => v} -> v
      _ -> nil
    end)
  end

  defp primary_link(_), do: nil

  defp wikipedia_link(links) when is_list(links) do
    Enum.find_value(links, fn
      %{"type" => "wikipedia", "value" => v} -> v
      _ -> nil
    end)
  end

  defp wikipedia_link(_), do: nil

  defp flatten_external_ids(list) when is_list(list) do
    Map.new(list, fn
      %{"type" => type, "preferred" => preferred} when is_binary(preferred) -> {type, preferred}
      %{"type" => type, "all" => [first | _]} -> {type, first}
      _ -> {"_", nil}
    end)
  end

  defp flatten_external_ids(_), do: %{}

  defp extract_ror_id(nil), do: nil

  defp extract_ror_id(full) when is_binary(full) do
    full |> String.split("/") |> List.last()
  end

  # ── Geo lookups ────────────────────────────────────────────────────────────

  defp country_index do
    Repo.all(Country) |> Enum.map(fn c -> {c.code, c.id} end) |> Map.new()
  end

  defp extract_json(zip_path) do
    case :zip.unzip(String.to_charlist(zip_path),
           cwd: String.to_charlist(Path.dirname(zip_path))
         ) do
      {:ok, files} ->
        # Prefer the v2-schema JSON (filename contains "_schema_v2" or is the
        # single JSON that isn't the deprecated v1 in mixed-archive releases).
        # ROR v2.x archives contain both v1 + v2 JSONs for transition; pick v2.
        candidates =
          Enum.filter(files, fn f ->
            fname = f |> to_string() |> String.downcase()
            String.ends_with?(fname, ".json")
          end)

        v2 =
          Enum.find(candidates, fn f ->
            f |> to_string() |> String.downcase() |> String.contains?("schema_v2")
          end)

        case v2 || List.first(candidates) do
          nil -> {:error, :no_json_in_zip}
          path -> {:ok, to_string(path)}
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
