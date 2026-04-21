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
        # Dedicated Finch pool for Google Vision OCR. HTTP/2 multiplexes
        # many concurrent requests over a single connection with built-in
        # ping/keepalive, which dodges the `sndbuf :einval` error we hit
        # when Finch reused HTTP/1 sockets that Cloud Run's egress NAT
        # had already silently closed. Small `size` is intentional: HTTP/2
        # lets one connection carry many streams, so more sockets just
        # invites the same close-race we're trying to avoid.
        {Finch,
         name: FunSheep.VisionFinch,
         pools: %{
           :default => [size: 5, count: 1],
           "https://vision.googleapis.com" => [
             size: 1,
             count: 8,
             conn_max_idle_time: :timer.seconds(10),
             protocols: [:http2]
           ]
         }},
        # Interactor Auth token cache (caches App JWT for M2M calls)
        FunSheep.Interactor.Auth,
        # Registry for AI tutor sessions (one GenServer per active student+question)
        {Registry, keys: :unique, name: FunSheep.Tutor.SessionRegistry},
        # Cache for in-progress assessment state (survives LiveView reconnects)
        FunSheep.Assessments.StateCache,
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
