defmodule FunSheep.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        FunSheepWeb.Telemetry,
        FunSheep.Repo,
        {DNSCluster, query: Application.get_env(:fun_sheep, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: FunSheep.PubSub},
        # Interactor Auth token cache (caches App JWT for M2M calls)
        FunSheep.Interactor.Auth,
        # Circuit-breaker + daily-budget guard for LLM calls
        FunSheep.AIUsage.Guard,
        # Registry for AI tutor sessions (one GenServer per active student+question)
        {Registry, keys: :unique, name: FunSheep.Tutor.SessionRegistry},
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
        # dropped their questions back to :uncategorized). 200 × 4 gives
        # 800 effective slots, with `count=4` spreading load across multiple
        # connection pools to avoid head-of-line blocking on a single pool.
        # Override per-environment via FINCH_AI_POOL_SIZE / FINCH_AI_POOL_COUNT.
        {Finch,
         name: FunSheep.Finch,
         pools: %{
           default: [
             size: String.to_integer(System.get_env("FINCH_AI_POOL_SIZE") || "200"),
             count: String.to_integer(System.get_env("FINCH_AI_POOL_COUNT") || "4")
           ]
         }},
        # Background job processing
        {Oban, Application.fetch_env!(:fun_sheep, Oban)}
      ] ++
        goth_children() ++
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
end
