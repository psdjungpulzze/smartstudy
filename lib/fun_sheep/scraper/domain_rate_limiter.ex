defmodule FunSheep.Scraper.DomainRateLimiter do
  @moduledoc """
  GenServer + ETS token-bucket rate limiter for web scraping.

  Callers invoke `acquire/1` with a URL. The limiter extracts the domain,
  checks how many requests have been made in the current sliding window, and
  either returns `:ok` immediately (slot available) or sleeps until one opens.

  Per-domain limits:
    khanacademy.org   — 5 req/sec
    collegeboard.org  — 2 req/sec
    varsitytutors.com — 10 req/sec
    (all others)      — 20 req/sec

  All requests complete within a 30-second timeout — if a domain is severely
  backlogged, acquire proceeds anyway rather than blocking indefinitely.
  """

  use GenServer
  require Logger

  @limits %{
    "khanacademy.org" => {5, 1_000},
    "collegeboard.org" => {2, 1_000},
    "varsitytutors.com" => {10, 1_000},
    "default" => {20, 1_000}
  }

  @acquire_timeout_ms 30_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Blocks until a request slot is available for the domain of `url`.
  Returns `:ok`. Always proceeds after `@acquire_timeout_ms` to avoid deadlock.
  """
  @spec acquire(String.t() | any()) :: :ok
  def acquire(url) when is_binary(url) do
    domain = extract_domain(url)
    do_acquire(domain, 0)
  end

  def acquire(_), do: :ok

  # --- GenServer callbacks ---

  @impl GenServer
  def init(:ok) do
    :ets.new(:domain_rate_limiter, [:named_table, :public, :set])
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:check_and_record, domain}, _from, state) do
    {limit, window_ms} = Map.get(@limits, domain, Map.fetch!(@limits, "default"))
    now = System.monotonic_time(:millisecond)
    cutoff = now - window_ms

    recent =
      case :ets.lookup(:domain_rate_limiter, domain) do
        [{^domain, ts_list}] -> Enum.filter(ts_list, &(&1 > cutoff))
        [] -> []
      end

    if length(recent) < limit do
      :ets.insert(:domain_rate_limiter, {domain, [now | recent]})
      {:reply, :ok, state}
    else
      oldest = Enum.min(recent)
      wait_ms = oldest + window_ms - now + 1
      {:reply, {:wait, max(wait_ms, 10)}, state}
    end
  end

  # --- Private helpers ---

  defp do_acquire(_domain, waited_ms) when waited_ms >= @acquire_timeout_ms do
    Logger.warning("[DomainRateLimiter] acquire timeout after #{waited_ms}ms — proceeding")
    :ok
  end

  defp do_acquire(domain, waited_ms) do
    case GenServer.call(__MODULE__, {:check_and_record, domain}, @acquire_timeout_ms) do
      :ok ->
        :ok

      {:wait, ms} ->
        jitter = :rand.uniform(min(ms, 100))
        Process.sleep(ms + jitter)
        do_acquire(domain, waited_ms + ms + jitter)
    end
  end

  defp extract_domain(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        host |> String.downcase() |> String.trim_leading("www.")

      _ ->
        "default"
    end
  end
end
