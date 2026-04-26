defmodule FunSheep.Workers.TestDateSyncWorker do
  @moduledoc """
  Oban worker that fetches official test dates from organizing bodies
  (College Board, ACT, ETS, LSAC, etc.) using Anthropic web search.

  Runs quarterly via Oban cron. For each supported test type, it asks
  Anthropic to search for the current academic year's test dates and
  upserts the results into `known_test_dates`.

  Uses the real Anthropic `web_search_20250305` tool — no hallucination.
  """

  use Oban.Worker, queue: :background, max_attempts: 3

  alias FunSheep.Courses
  require Logger

  @anthropic_api_url "https://api.anthropic.com/v1/messages"
  @anthropic_api_version "2023-06-01"
  @search_model "claude-haiku-4-5-20251001"
  @search_tool_type "web_search_20250305"
  @search_beta "web-search-2025-03-05"

  # Official sources per test type
  @test_sources %{
    "sat" => %{
      name: "SAT",
      org: "College Board",
      site: "collegeboard.org",
      prompt_hint: "SAT test dates, registration deadlines, and score release dates"
    },
    "act" => %{
      name: "ACT",
      org: "ACT Inc",
      site: "act.org",
      prompt_hint: "ACT test dates, registration deadlines, and score release dates"
    },
    "ap" => %{
      name: "AP Exams",
      org: "College Board",
      site: "collegeboard.org",
      prompt_hint: "AP exam dates for the current academic year"
    },
    "gre" => %{
      name: "GRE",
      org: "ETS",
      site: "ets.org",
      prompt_hint: "GRE General Test dates and registration windows"
    },
    "gmat" => %{
      name: "GMAT",
      org: "GMAC",
      site: "mba.com",
      prompt_hint: "GMAT Focus Edition test availability and registration"
    },
    "lsat" => %{
      name: "LSAT",
      org: "LSAC",
      site: "lsac.org",
      prompt_hint: "LSAT test dates, registration deadlines, and score release dates"
    },
    "mcat" => %{
      name: "MCAT",
      org: "AAMC",
      site: "aamc.org",
      prompt_hint: "MCAT test dates, registration deadlines, and score release dates"
    }
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"test_type" => test_type}}) do
    source = Map.fetch!(@test_sources, test_type)
    Logger.info("[TestDateSyncWorker] Syncing #{test_type} dates from #{source.site}")

    with {:ok, dates} <- fetch_test_dates(test_type, source) do
      {inserted, updated} =
        Enum.reduce(dates, {0, 0}, fn date_attrs, {ins, upd} ->
          case Courses.upsert_known_test_date(Map.put(date_attrs, :last_synced_at, DateTime.utc_now())) do
            {:ok, record} ->
              if record.inserted_at == record.updated_at,
                do: {ins + 1, upd},
                else: {ins, upd + 1}

            {:error, changeset} ->
              Logger.warning("[TestDateSyncWorker] Skipped invalid date: #{inspect(changeset.errors)}")
              {ins, upd}
          end
        end)

      Logger.info("[TestDateSyncWorker] #{test_type}: #{inserted} inserted, #{updated} updated")
      :ok
    else
      {:error, reason} ->
        Logger.error("[TestDateSyncWorker] Failed to fetch #{test_type} dates: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Enqueue sync jobs for all supported test types
  def enqueue_all do
    @test_sources
    |> Map.keys()
    |> Enum.map(fn test_type ->
      %{"test_type" => test_type}
      |> new()
      |> Oban.insert()
    end)
  end

  defp fetch_test_dates(test_type, source) do
    api_key = System.get_env("ANTHROPIC_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      do_fetch(test_type, source, api_key)
    end
  end

  defp do_fetch(test_type, source, api_key) do
    today = Date.utc_today()
    year = today.year
    next_year = year + 1

    prompt = """
    Search #{source.site} for #{source.name} #{source.prompt_hint} for #{year}-#{next_year}.

    For each test date found, extract:
    - test_name: e.g. "SAT October 2025"
    - test_date: in ISO format YYYY-MM-DD
    - registration_deadline: YYYY-MM-DD if available
    - late_registration_deadline: YYYY-MM-DD if available
    - score_release_date: YYYY-MM-DD if available
    - source_url: the exact URL where you found this

    Return a JSON array of objects with these exact keys. Only include real dates you find on the official site — never guess or invent dates.
    Example: [{"test_name":"SAT October 2025","test_date":"2025-10-04","registration_deadline":"2025-09-19","late_registration_deadline":"2025-09-23","score_release_date":"2025-10-24","source_url":"https://collegeboard.org/..."}]
    """

    body = %{
      model: @search_model,
      max_tokens: 4096,
      tools: [%{type: @search_tool_type, name: "web_search", max_uses: 5}],
      messages: [%{role: "user", content: prompt}]
    }

    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", @anthropic_api_version},
      {"anthropic-beta", @search_beta},
      {"content-type", "application/json"}
    ]

    case Req.post(@anthropic_api_url, json: body, headers: headers, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: response_body}} ->
        parse_dates_from_response(response_body, test_type)

      {:ok, %{status: status, body: error_body}} ->
        Logger.error("[TestDateSyncWorker] Anthropic API error #{status}: #{inspect(error_body)}")
        {:error, {:api_error, status}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp parse_dates_from_response(response_body, test_type) do
    text =
      response_body
      |> Map.get("content", [])
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map_join("\n", & &1["text"])

    # Extract JSON array from response text
    case extract_json_array(text) do
      {:ok, raw_dates} ->
        dates =
          Enum.flat_map(raw_dates, fn raw ->
            case parse_date_entry(raw, test_type) do
              {:ok, entry} -> [entry]
              {:error, _} -> []
            end
          end)

        {:ok, dates}

      {:error, _} = err ->
        Logger.warning("[TestDateSyncWorker] Could not parse JSON dates from response: #{String.slice(text, 0, 200)}")
        err
    end
  end

  defp extract_json_array(text) do
    case Regex.run(~r/\[[\s\S]*\]/U, text) do
      [json_str | _] ->
        case Jason.decode(json_str) do
          {:ok, list} when is_list(list) -> {:ok, list}
          _ -> {:error, :invalid_json}
        end

      nil ->
        {:error, :no_json_array}
    end
  end

  defp parse_date_entry(raw, test_type) do
    with {:ok, test_date} <- parse_date(raw["test_date"]) do
      {:ok, %{
        test_type: test_type,
        test_name: raw["test_name"] || "#{String.upcase(test_type)} #{test_date}",
        test_date: test_date,
        registration_deadline: parse_date_ok(raw["registration_deadline"]),
        late_registration_deadline: parse_date_ok(raw["late_registration_deadline"]),
        score_release_date: parse_date_ok(raw["score_release_date"]),
        source_url: raw["source_url"],
        region: "us"
      }}
    end
  end

  defp parse_date(nil), do: {:error, :missing}
  defp parse_date(""), do: {:error, :empty}

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, _} = ok -> ok
      _ -> {:error, :invalid_date}
    end
  end

  defp parse_date_ok(nil), do: nil
  defp parse_date_ok(""), do: nil

  defp parse_date_ok(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
