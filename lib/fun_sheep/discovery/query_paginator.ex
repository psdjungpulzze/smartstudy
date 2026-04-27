defmodule FunSheep.Discovery.QueryPaginator do
  @moduledoc """
  Multi-page search wrapper for `WebContentDiscoveryWorker`.

  A single Anthropic `web_search_20250305` call returns up to ~10 URLs.
  For broad subjects (SAT Math, AP Biology) there are far more relevant pages
  than a single search yields. This module reruns the same query up to
  `@max_pages` times, instructing the model to avoid URLs already returned.
  Early-exit when a page produces no novel URLs (diminishing-returns signal).

  Pages 2+ append an exclusion hint to the original query string so the model
  searches for *different* pages rather than re-ranking the same results.
  """

  require Logger

  @max_pages 3
  @min_novel_threshold 2

  @doc """
  Run a search query with up to `@max_pages` pages of results.
  Returns a deduplicated list of result maps `%{url:, title:, snippet:, ...}`.
  Emits `[:fun_sheep, :discovery, :search_complete]` for each page.
  """
  @spec search(String.t(), keyword()) :: [map()]
  def search(query, opts \\ []) do
    search_fn = Keyword.get(opts, :search_fn, &default_search/1)
    max_pages = Keyword.get(opts, :max_pages, @max_pages)

    do_paginate(query, search_fn, max_pages, MapSet.new(), [])
  end

  defp do_paginate(_query, _search_fn, 0, _seen_urls, acc), do: Enum.reverse(acc)

  defp do_paginate(query, search_fn, pages_remaining, seen_urls, acc) do
    paged_query = build_paged_query(query, seen_urls)

    case search_fn.(paged_query) do
      {:ok, results} ->
        novel = Enum.reject(results, fn r -> MapSet.member?(seen_urls, r[:url]) end)
        page_num = @max_pages - pages_remaining + 1

        :telemetry.execute(
          [:fun_sheep, :discovery, :search_complete],
          %{results_count: length(results)},
          %{query: paged_query, page: page_num, novel_count: length(novel)}
        )

        if length(novel) < @min_novel_threshold do
          Enum.reverse(acc) ++ novel
        else
          new_seen = Enum.reduce(novel, seen_urls, fn r, s -> MapSet.put(s, r[:url]) end)
          do_paginate(query, search_fn, pages_remaining - 1, new_seen, Enum.reverse(novel) ++ acc)
        end

      {:error, reason} ->
        Logger.warning("[QueryPaginator] Search failed for '#{query}': #{inspect(reason)}")

        :telemetry.execute(
          [:fun_sheep, :discovery, :search_complete],
          %{results_count: 0},
          %{query: paged_query, error: inspect(reason)}
        )

        Enum.reverse(acc)
    end
  end

  defp build_paged_query(query, seen_urls) do
    if MapSet.size(seen_urls) == 0, do: query, else: build_exclusion_query(query, seen_urls)
  end

  defp build_exclusion_query(query, seen_urls) do
    # Append a hint so the model finds *different* pages, not re-ranking the same set.
    seen_count = MapSet.size(seen_urls)
    "#{query} -site:#{sample_seen_domains(seen_urls)} (find #{seen_count} more different pages)"
  end

  defp sample_seen_domains(seen_urls) do
    seen_urls
    |> MapSet.to_list()
    |> Enum.flat_map(fn url ->
      case URI.parse(url) do
        %URI{host: h} when is_binary(h) -> [String.replace_prefix(h, "www.", "")]
        _ -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.take(3)
    |> Enum.join(" -site:")
  end

  defp default_search(_query), do: {:error, :no_search_fn_injected}
end
