defmodule FunSheep.Search.TavilyClient do
  @moduledoc """
  HTTP client for the Tavily Search API.

  Returns structured search results (title, URL, snippet) suitable for feeding
  into the web-content discovery pipeline. Replaces the Anthropic
  `web_search_20250305` server-side tool, eliminating its $10/1k search fee
  and the large token overhead from page content injected into LLM context.

  Configure the API key via the `TAVILY_API_KEY` environment variable.
  In tests, stub HTTP via:

      Application.put_env(:fun_sheep, :tavily_req_opts,
        plug: {Req.Test, FunSheep.Search.TavilyClient})
  """

  require Logger

  @base_url "https://api.tavily.com/search"
  @timeout 15_000

  @type result :: %{
          title: String.t() | nil,
          url: String.t() | nil,
          snippet: String.t() | nil,
          publisher: String.t() | nil,
          confidence: float()
        }

  @doc """
  Searches the web using Tavily and returns a list of results.

  Options:
    - `:max_results` — maximum number of results (default: 10)
    - `:search_depth` — `"basic"` or `"advanced"` (default: `"basic"`)
  """
  @spec search(String.t(), keyword()) :: {:ok, [result()]} | {:error, term()}
  def search(query, opts \\ []) do
    api_key = Application.get_env(:fun_sheep, :tavily_api_key)

    if is_nil(api_key) or api_key == "" do
      Logger.warning("[Tavily] API key not configured — skipping search for '#{query}'")
      {:error, :no_api_key}
    else
      do_search(query, api_key, opts)
    end
  end

  defp do_search(query, api_key, opts) do
    max_results = Keyword.get(opts, :max_results, 10)
    search_depth = Keyword.get(opts, :search_depth, "basic")

    body = %{
      api_key: api_key,
      query: query,
      search_depth: search_depth,
      max_results: max_results,
      include_answer: false,
      include_images: false,
      include_raw_content: false
    }

    req_opts =
      [
        json: body,
        receive_timeout: @timeout,
        retry: false,
        finch: FunSheep.Finch
      ] ++ Application.get_env(:fun_sheep, :tavily_req_opts, [])

    case Req.post(@base_url, req_opts) do
      {:ok, %{status: 200, body: %{"results" => results}}} ->
        {:ok, parse_results(results)}

      {:ok, %{status: 200, body: body}} ->
        Logger.warning("[Tavily] Unexpected 200 body shape for '#{String.slice(query, 0, 60)}': #{inspect(body)}")
        {:error, :unexpected_response}

      {:ok, %{status: 429}} ->
        Logger.warning("[Tavily] Rate limited for query '#{String.slice(query, 0, 60)}'")
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[Tavily] HTTP #{status} for '#{String.slice(query, 0, 60)}': #{inspect(body)}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        Logger.warning("[Tavily] Request failed for '#{String.slice(query, 0, 60)}': #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_results(results) do
    Enum.map(results, fn r ->
      %{
        title: r["title"],
        url: r["url"],
        snippet: r["content"],
        publisher: extract_publisher(r["url"]),
        confidence: r["score"] || 0.8
      }
    end)
  end

  defp extract_publisher(nil), do: nil

  defp extract_publisher(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" ->
        String.replace_prefix(host, "www.", "")

      _ ->
        nil
    end
  end
end
