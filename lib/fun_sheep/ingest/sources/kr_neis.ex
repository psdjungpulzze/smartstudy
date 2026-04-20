defmodule FunSheep.Ingest.Sources.KrNeis do
  @moduledoc """
  NEIS Open API (https://open.neis.go.kr) — Korea Ministry of Education's
  authoritative directory of every 유치원/초/중/고/특수 school under the
  17 시도교육청 (metropolitan/provincial education offices).

  Total coverage ~12,000 schools. Authentication is optional — without a
  `NEIS_API_KEY` env var, requests hit a lower rate limit (sufficient for
  an overnight batch). The API returns JSON; there is no CSV equivalent.

  Natural key: `SD_SCHUL_CODE` (7-digit school standard code, nationally
  unique). Stored as `schools.kr_code` and `schools.source_id`.

  The 17 시도교육청 codes we iterate:
      B10 서울   C10 부산   D10 대구   E10 인천   F10 광주
      G10 대전   H10 울산   I10 세종   J10 경기   K10 강원
      M10 충북   N10 충남   P10 전북   Q10 전남   R10 경북
      S10 경남   T10 제주
  """

  @behaviour FunSheep.Ingest.Source

  require Logger

  alias FunSheep.Geo.{Country, School, State}
  alias FunSheep.Ingest.Upsert
  alias FunSheep.Repo

  import Ecto.Query

  @source "kr_neis"
  @endpoint "https://open.neis.go.kr/hub/schoolInfo"
  @page_size 1000

  # 교육청 코드 → ISO 3166-2
  @office_to_iso %{
    "B10" => "KR-11",
    "C10" => "KR-26",
    "D10" => "KR-27",
    "E10" => "KR-28",
    "F10" => "KR-29",
    "G10" => "KR-30",
    "H10" => "KR-31",
    "I10" => "KR-50",
    "J10" => "KR-41",
    "K10" => "KR-42",
    "M10" => "KR-43",
    "N10" => "KR-44",
    "P10" => "KR-45",
    "Q10" => "KR-46",
    "R10" => "KR-47",
    "S10" => "KR-48",
    "T10" => "KR-49"
  }

  @impl true
  def source, do: @source

  @impl true
  def datasets, do: ["schools"]

  @impl true
  def run(dataset, opts \\ [])

  def run("schools", opts) do
    country_id = kr_country_id()
    state_index = kr_state_index()
    api_key = opts[:api_key] || System.get_env("NEIS_API_KEY")

    {total_rows, total_upserted} =
      @office_to_iso
      |> Map.keys()
      |> Enum.reduce({0, 0}, fn office_code, {rows_acc, upserted_acc} ->
        Logger.info("kr_neis fetching office", office: office_code)

        case fetch_office_all_pages(office_code, api_key) do
          {:ok, rows} ->
            attrs =
              rows
              |> Enum.map(&row_to_school(&1, country_id, state_index))
              |> Enum.reject(&is_nil/1)

            {count, _} = Upsert.run(School, attrs, batch_size: 500)
            {rows_acc + length(rows), upserted_acc + count}

          {:error, reason} ->
            Logger.warning("kr_neis office failed",
              office: office_code,
              reason: inspect(reason)
            )

            {rows_acc, upserted_acc}
        end
      end)

    {:ok, %{inserted: total_upserted, updated: 0, rows: total_rows}}
  end

  def run(dataset, _opts), do: {:error, {:unknown_dataset, dataset}}

  # ── Paging ─────────────────────────────────────────────────────────────────

  defp fetch_office_all_pages(office_code, api_key) do
    fetch_page(office_code, api_key, 1, [])
  end

  defp fetch_page(office_code, api_key, page, acc) do
    params = %{
      "Type" => "json",
      "pIndex" => page,
      "pSize" => @page_size,
      "ATPT_OFCDC_SC_CODE" => office_code
    }

    params = if api_key, do: Map.put(params, "KEY", api_key), else: params

    case Req.get(@endpoint, params: params, receive_timeout: :timer.seconds(60)) do
      {:ok, %{status: 200, body: body}} ->
        case extract_rows(body) do
          {:ok, []} ->
            {:ok, acc}

          {:ok, rows} ->
            new_acc = acc ++ rows

            if length(rows) < @page_size do
              {:ok, new_acc}
            else
              fetch_page(office_code, api_key, page + 1, new_acc)
            end

          {:error, :no_data} ->
            {:ok, acc}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # NEIS wraps responses as:
  #   {"schoolInfo": [{"head": [...]}, {"row": [...]}]}
  # or on no-data:
  #   {"RESULT": {"CODE": "INFO-200", "MESSAGE": "해당하는 데이터가 없습니다."}}
  defp extract_rows(%{"schoolInfo" => frames}) when is_list(frames) do
    rows =
      Enum.find_value(frames, [], fn
        %{"row" => row} when is_list(row) -> row
        _ -> false
      end) || []

    {:ok, rows}
  end

  defp extract_rows(%{"RESULT" => %{"CODE" => "INFO-200"}}), do: {:error, :no_data}
  defp extract_rows(%{"RESULT" => %{"CODE" => code, "MESSAGE" => msg}}), do: {:error, {code, msg}}
  defp extract_rows(_), do: {:error, :unexpected_shape}

  # ── Row mapping ────────────────────────────────────────────────────────────

  defp row_to_school(row, country_id, state_index) do
    code = trim(row["SD_SCHUL_CODE"])
    name = trim(row["SCHUL_NM"])
    office = trim(row["ATPT_OFCDC_SC_CODE"])
    iso = @office_to_iso[office]

    cond do
      is_nil(code) or is_nil(name) ->
        nil

      is_nil(iso) ->
        Logger.debug("kr_neis unknown office", office: office, code: code)
        nil

      true ->
        %{
          source: @source,
          source_id: code,
          kr_code: code,
          name: trim(row["ENG_SCHUL_NM"]) || name,
          native_name: name,
          country_id: country_id,
          state_id: state_index[iso],
          type: kr_type(row["FOND_SC_NM"]),
          level: kr_level(row["SCHUL_KND_SC_NM"]),
          operational_status: "open",
          address: trim(row["ORG_RDNMA"]),
          postal_code: trim(row["ORG_RDNZC"]),
          phone: trim(row["ORG_TELNO"]),
          website: normalize_url(row["HMPG_ADRES"]),
          opened_at: parse_ymd(row["FOND_YMD"]),
          metadata: %{
            "office_code" => office,
            "office_name" => row["ATPT_OFCDC_SC_NM"],
            "coedu" => row["COEDU_SC_NM"],
            "daynight" => row["DGHT_SC_NM"],
            "specialty" => row["SPCLY_PURPS_HS_ORD_NM"],
            "industry_special" => row["INDST_SPECL_CCCCL_EXST_YN"]
          }
        }
    end
  end

  # FOND_SC_NM: 공립 (public), 사립 (private), 국립 (national)
  defp kr_type("공립"), do: "public"
  defp kr_type("사립"), do: "private"
  defp kr_type("국립"), do: "public"
  defp kr_type(_), do: "public"

  # SCHUL_KND_SC_NM: 유치원, 초등학교, 중학교, 고등학교, 특수학교, 기타학교
  defp kr_level("유치원"), do: "kindergarten"
  defp kr_level("초등학교"), do: "elementary"
  defp kr_level("중학교"), do: "middle"
  defp kr_level("고등학교"), do: "high"
  defp kr_level("특수학교"), do: "special"
  defp kr_level("기타학교"), do: "other"
  defp kr_level(_), do: "other"

  # ── Geo lookups ────────────────────────────────────────────────────────────

  defp kr_country_id do
    case Repo.get_by(Country, code: "KR") do
      %{id: id} -> id
      nil -> raise "KR country row missing — run seeds before ingesting NEIS"
    end
  end

  defp kr_state_index do
    from(s in State,
      where: like(s.iso_code, "KR-%"),
      select: {s.iso_code, s.id}
    )
    |> Repo.all()
    |> Map.new()
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp parse_ymd(nil), do: nil
  defp parse_ymd(""), do: nil

  defp parse_ymd(<<y::binary-size(4), m::binary-size(2), d::binary-size(2)>>) do
    case Date.new(String.to_integer(y), String.to_integer(m), String.to_integer(d)) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_ymd(_), do: nil

  defp normalize_url(nil), do: nil
  defp normalize_url(""), do: nil

  defp normalize_url(url) when is_binary(url) do
    trimmed = String.trim(url)

    cond do
      trimmed == "" -> nil
      String.starts_with?(trimmed, "http") -> trimmed
      true -> "http://" <> trimmed
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
