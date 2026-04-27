defmodule FunSheep.Discovery.Adapters.KhanAcademy do
  @moduledoc """
  Direct source adapter for Khan Academy.

  Uses KA's public content API to enumerate exercise URLs for known subject
  slugs without relying on web search. No auth required for public exercises.

  Returns `[%{url:, title:, source_type: "question_bank", discovery_strategy: "api_adapter",
              publisher: "khanacademy.org", tier: 2}]`.

  Known exercise channel slugs per test type:
    - SAT math      → "sat-math"
    - SAT reading   → "sat-reading-writing"
    - ACT           → "act" (KA has ACT prep content)
    - AP Calc AB    → "ap-calculus-ab"
    - AP Biology    → "ap-biology"
    - AP Chemistry  → "ap-chemistry"
    - AP US History → "ap-us-history"

  Fallback: if the API slug is unknown, returns [].
  """

  require Logger

  @base_url "https://www.khanacademy.org"
  @api_path "/api/v1/exercises"
  @timeout 15_000
  @max_exercises 200

  # Maps (catalog_test_type, catalog_subject) → KA channel slug
  @slug_map %{
    {"sat", "mathematics"} => "sat-math",
    {"sat", "reading_writing"} => "sat-reading-writing",
    {"sat", nil} => "sat-math",
    {"act", nil} => "act",
    {"act", "mathematics"} => "act",
    {"ap_calculus_ab", nil} => "ap-calculus-ab",
    {"ap_calculus_bc", nil} => "ap-calculus-bc",
    {"ap_biology", nil} => "ap-biology",
    {"ap_chemistry", nil} => "ap-chemistry",
    {"ap_physics_1", nil} => "ap-physics-1",
    {"ap_us_history", nil} => "ap-us-history",
    {"ap_world_history", nil} => "ap-world-history",
    {"ap_statistics", nil} => "ap-statistics",
    {"lsat", nil} => "lsat",
    {"gre", "quantitative"} => "gre",
    {"gre", "verbal"} => "gre"
  }

  @doc """
  Returns a list of exercise URLs for the given test_type + catalog_subject.
  Returns `[]` when the test/subject combo has no known KA slug.
  """
  @spec discover(String.t() | nil, String.t() | nil, keyword()) :: [map()]
  def discover(test_type, catalog_subject, opts \\ []) do
    slug = Map.get(@slug_map, {test_type, catalog_subject}) ||
           Map.get(@slug_map, {test_type, nil})

    if slug do
      fetch_exercises(slug, opts)
    else
      Logger.debug("[KhanAcademy] No slug for test_type=#{test_type}, subject=#{catalog_subject}")
      []
    end
  end

  defp fetch_exercises(slug, opts) do
    http = Keyword.get(opts, :http_fn, &default_get/1)
    url = "#{@base_url}#{@api_path}?channel_slug=#{slug}&limit=#{@max_exercises}"

    case http.(url) do
      {:ok, %{status: 200, body: body}} ->
        parse_exercises(body, slug)

      {:ok, %{status: status}} ->
        Logger.warning("[KhanAcademy] API returned HTTP #{status} for slug=#{slug}")
        []

      {:error, reason} ->
        Logger.warning("[KhanAcademy] API call failed for slug=#{slug}: #{inspect(reason)}")
        []
    end
  end

  defp parse_exercises(body, slug) when is_map(body) do
    exercises = get_in(body, ["exercises"]) || []

    Enum.map(exercises, fn ex ->
      ka_path = ex["ka_url"] || "/e/#{ex["name"] || ex["id"] || "unknown"}"

      %{
        url: "#{@base_url}#{ka_path}",
        title: ex["display_name"] || ex["title"] || "Khan Academy exercise",
        snippet: ex["description"] || "Practice exercise from Khan Academy #{slug}",
        publisher: "khanacademy.org",
        source_type: "question_bank",
        discovery_strategy: "api_adapter",
        confidence: 0.95
      }
    end)
    |> Enum.reject(fn r -> is_nil(r[:url]) or r[:url] == "" end)
  end

  defp parse_exercises(_, _), do: []

  defp default_get(url) do
    Req.get(url,
      receive_timeout: @timeout,
      max_redirects: 3,
      retry: false,
      finch: FunSheep.Finch,
      headers: [{"accept", "application/json"}]
    )
  end
end
