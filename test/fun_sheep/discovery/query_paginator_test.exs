defmodule FunSheep.Discovery.QueryPaginatorTest do
  use ExUnit.Case, async: true

  alias FunSheep.Discovery.QueryPaginator

  defp result(url) do
    %{url: url, title: "Page #{url}", snippet: "snippet", publisher: "example.com"}
  end

  describe "search/2" do
    test "returns results from a single page when there are few" do
      search_fn = fn _q -> {:ok, [result("https://a.com/1"), result("https://a.com/2")]} end

      results = QueryPaginator.search("SAT math", search_fn: search_fn, max_pages: 3)

      assert length(results) == 2
      assert Enum.any?(results, &(&1.url == "https://a.com/1"))
    end

    test "deduplicates URLs across pages" do
      call_count = :counters.new(1, [])

      search_fn = fn _q ->
        n = :counters.add(call_count, 1, 1)
        # Page 1 and page 2 both return the same URL — only one should appear
        {:ok, [result("https://same.com/page"), result("https://unique-#{n}.com/page")]}
      end

      results = QueryPaginator.search("SAT", search_fn: search_fn, max_pages: 2)

      urls = Enum.map(results, & &1.url)
      assert length(Enum.uniq(urls)) == length(urls), "URLs must be unique after dedup"
    end

    test "stops early when a page yields no novel URLs" do
      call_count = :counters.new(1, [])

      search_fn = fn _q ->
        n = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if n == 0 do
          {:ok, [result("https://a.com/1"), result("https://a.com/2")]}
        else
          # Page 2 returns already-seen URLs — should trigger early exit
          {:ok, [result("https://a.com/1"), result("https://a.com/2")]}
        end
      end

      results = QueryPaginator.search("SAT", search_fn: search_fn, max_pages: 3)

      # Should have stopped after page 2 found nothing novel
      calls = :counters.get(call_count, 1)
      assert calls == 2
      assert length(results) == 2
    end

    test "returns [] when search_fn always errors" do
      search_fn = fn _q -> {:error, :api_down} end

      results = QueryPaginator.search("any query", search_fn: search_fn, max_pages: 2)

      assert results == []
    end

    test "respects max_pages option" do
      call_count = :counters.new(1, [])

      search_fn = fn _q ->
        n = :counters.add(call_count, 1, 1)
        {:ok, [result("https://novel-#{n}.com/page")]}
      end

      QueryPaginator.search("SAT", search_fn: search_fn, max_pages: 2)

      assert :counters.get(call_count, 1) <= 2
    end

    test "page 2 query string differs from page 1 to force novel results" do
      queries = :ets.new(:queries, [:ordered_set, :public])

      search_fn = fn q ->
        :ets.insert(queries, {System.unique_integer([:monotonic]), q})
        # Return 2+ novel results per call so the paginator crosses the min-novel threshold
        n = System.unique_integer([:positive])
        {:ok, [result("https://novel-#{n}.com/a"), result("https://novel-#{n}.com/b")]}
      end

      QueryPaginator.search("original query", search_fn: search_fn, max_pages: 2)

      query_list = :ets.tab2list(queries) |> Enum.map(fn {_, q} -> q end)
      assert length(query_list) == 2

      [q1, q2] = query_list
      assert q1 == "original query"
      # Page 2 must be a different string (exclusion hint appended)
      assert q2 != q1
    end
  end
end
