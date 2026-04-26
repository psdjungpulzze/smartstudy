defmodule FunSheep.Scraper.DomainRateLimiterTest do
  use ExUnit.Case, async: false

  alias FunSheep.Scraper.DomainRateLimiter

  # Clear ETS entries for the domains used in each test to reset sliding-window state.
  setup do
    :ets.delete_all_objects(:domain_rate_limiter)
    :ok
  end

  describe "acquire/1" do
    test "returns :ok immediately for a default-rate URL" do
      t0 = System.monotonic_time(:millisecond)
      assert DomainRateLimiter.acquire("https://example.com/page") == :ok
      elapsed = System.monotonic_time(:millisecond) - t0
      assert elapsed < 100
    end

    test "returns :ok for nil / non-string argument" do
      assert DomainRateLimiter.acquire(nil) == :ok
      assert DomainRateLimiter.acquire(42) == :ok
    end

    test "www. prefix is stripped for domain matching" do
      # Should complete quickly — first request for this domain
      assert DomainRateLimiter.acquire("https://www.khanacademy.org/math") == :ok
    end

    test "5 sequential khanacademy.org requests fit within one window" do
      url = "https://khanacademy.org/math/algebra"
      t0 = System.monotonic_time(:millisecond)
      for _ <- 1..5, do: DomainRateLimiter.acquire(url)
      elapsed = System.monotonic_time(:millisecond) - t0
      # 5 requests should fit within the 1000ms window (with jitter headroom)
      assert elapsed < 1_100, "First 5 khanacademy requests took #{elapsed}ms, expected < 1100ms"
    end

    test "6th khanacademy.org request is delayed to the next window" do
      url = "https://khanacademy.org/6th-request"
      t0 = System.monotonic_time(:millisecond)
      # Use up the 5-per-second quota
      for _ <- 1..5, do: DomainRateLimiter.acquire(url)
      slot_used_at = System.monotonic_time(:millisecond) - t0

      # 6th request must be delayed
      DomainRateLimiter.acquire(url)
      total = System.monotonic_time(:millisecond) - t0

      assert total >= 1_000,
             "6th khanacademy request should be delayed (>= 1000ms total), got #{total}ms; first 5 in #{slot_used_at}ms"
    end

    test "10 concurrent acquires for khanacademy.org all complete without deadlock" do
      url = "https://khanacademy.org/concurrent"
      t0 = System.monotonic_time(:millisecond)

      tasks = for _ <- 1..10, do: Task.async(fn -> DomainRateLimiter.acquire(url) end)
      results = Task.await_many(tasks, 5_000)

      elapsed = System.monotonic_time(:millisecond) - t0

      assert Enum.all?(results, &(&1 == :ok)), "All acquires should return :ok"
      assert elapsed < 5_000, "10 concurrent acquires should finish within 5s, took #{elapsed}ms"
    end

    test "different domains have independent rate limit buckets" do
      t0 = System.monotonic_time(:millisecond)

      # 5 requests for each domain — both should fit within their own windows
      tasks =
        for i <- 1..5 do
          Task.async(fn -> DomainRateLimiter.acquire("https://khanacademy.org/item/#{i}") end)
        end ++
          for i <- 1..5 do
            Task.async(fn ->
              DomainRateLimiter.acquire("https://varsitytutors.com/item/#{i}")
            end)
          end

      Task.await_many(tasks, 3_000)
      elapsed = System.monotonic_time(:millisecond) - t0

      # Each domain has its own bucket so 5+5 = 10 requests should not cause cross-domain delay
      assert elapsed < 2_000,
             "Cross-domain requests should not block each other, took #{elapsed}ms"
    end

    test "collegeboard.org limit of 2/sec delays the 3rd request" do
      url = "https://collegeboard.org/sat-practice"
      t0 = System.monotonic_time(:millisecond)
      DomainRateLimiter.acquire(url)
      DomainRateLimiter.acquire(url)
      # 3rd must wait
      DomainRateLimiter.acquire(url)
      elapsed = System.monotonic_time(:millisecond) - t0

      assert elapsed >= 1_000,
             "3rd collegeboard request should be delayed (>= 1000ms), got #{elapsed}ms"
    end
  end
end
