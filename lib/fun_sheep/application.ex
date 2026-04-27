defmodule FunSheep.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Set up OpenTelemetry auto-instrumentation before the supervisor starts so
    # all Phoenix requests, Ecto queries, and Oban jobs are traced from boot.
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:fun_sheep, :repo])
    OpentelemetryEcto.setup([:fun_sheep, :repo_read])
    OpentelemetryOban.setup()

    children =
      [
        FunSheepWeb.Telemetry,
        FunSheep.Repo,
        # Read-only repo pointed at the read replica (falls back to primary when
        # DATABASE_READ_URL is unset). Used for heavy read queries to offload the primary.
        FunSheep.RepoRead,
        {DNSCluster, query: Application.get_env(:fun_sheep, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: FunSheep.PubSub},
        # Interactor Auth token cache (caches App JWT for M2M calls)
        FunSheep.Interactor.Auth,
        # Circuit-breaker + daily-budget guard for LLM calls
        FunSheep.AIUsage.Guard,
        # Cluster-aware registry for AI tutor sessions. Horde.Registry distributes
        # lookups across all nodes so a session started on node A is findable from
        # node B, and the cluster rebalances on node join/leave.
        {Horde.Registry, name: FunSheep.Tutor.SessionRegistry, keys: :unique, members: :auto},
        # Per-domain token-bucket rate limiter for web scraping (Phase 4).
        # Must start before WebSourceScraperWorker jobs run.
        FunSheep.Scraper.DomainRateLimiter,
        # Cache for in-progress assessment state (survives LiveView reconnects)
        FunSheep.Assessments.StateCache,
        # ETS-backed cache for cohort percentile bands (spec §6.3)
        FunSheep.Assessments.CohortCache,
        # Dedicated Finch HTTP pool for all LLM API calls (Anthropic + OpenAI
        # direct calls via FunSheep.AI.Anthropic / FunSheep.AI.OpenAI, plus
        # remaining Interactor calls for the tutor). Req's default Finch pool is
        # size=50 / count=1, which gets exhausted under worker load
        # (5 concurrent classification jobs × 50 LLM calls each = 250
        # simultaneous requests → "Finch was unable to provide a connection
        # within the timeout due to excess queuing for connections" — the
        # 2026-04-22 incident where 80% of classification jobs silently
        # dropped their questions back to :uncategorized).
        #
        # IMPORTANT: count MUST stay at 1. count>1 causes Mint to call
        # ssl.getopts(socket, [:sndbuf, :recbuf, :buffer]) on simultaneous SSL
        # connections; Cloud Run's container rejects this with EINVAL, breaking
        # every AI call. The transport_opts sndbuf/recbuf/buffer pre-set values
        # that satisfy Mint's inet_opts check without triggering the kernel error.
        # See: lib/fun_sheep/ocr/google_vision.ex (same fix applied for Vision API).
        {Finch,
         name: FunSheep.Finch,
         pools: %{
           default: [
             size: String.to_integer(System.get_env("FINCH_AI_POOL_SIZE") || "100"),
             count: 1,
             conn_opts: [
               transport_opts: [sndbuf: 65_536, recbuf: 65_536, buffer: 65_536]
             ]
           ]
         }},
        # Background job processing
        {Oban, Application.fetch_env!(:fun_sheep, Oban)}
      ] ++
        goth_children() ++
        redis_children() ++
        [
          # Start to serve requests, typically the last entry
          FunSheepWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FunSheep.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FunSheepWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Start Goth only when the GCS storage backend is active. Goth fetches
  # OAuth tokens from the GCE/Cloud Run metadata server (Workload Identity)
  # so no service-account JSON key is required in the container.
  defp goth_children do
    if Application.get_env(:fun_sheep, :storage_backend) == FunSheep.Storage.GCS do
      goth_name =
        Application.get_env(:fun_sheep, FunSheep.Storage.GCS)[:goth_name] || FunSheep.Goth

      [{Goth, name: goth_name, source: {:metadata, []}}]
    else
      []
    end
  end

  # Start a single Redix connection when REDIS_URL is configured. The connection
  # is registered under the name :funsheep_redis so FunSheep.Cache can find it.
  # When REDIS_URL is absent (e.g. dev, test) no Redis process starts and the
  # Cache module degrades gracefully to :miss on all reads.
  defp redis_children do
    case Application.get_env(:fun_sheep, :redis_url) do
      nil -> []
      url -> [{Redix, {url, name: :funsheep_redis}}]
    end
  end

end
