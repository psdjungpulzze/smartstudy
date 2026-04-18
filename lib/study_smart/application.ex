defmodule StudySmart.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      StudySmartWeb.Telemetry,
      StudySmart.Repo,
      {DNSCluster, query: Application.get_env(:study_smart, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: StudySmart.PubSub},
      # Interactor Auth token cache (caches App JWT for M2M calls)
      StudySmart.Interactor.Auth,
      # Start to serve requests, typically the last entry
      StudySmartWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: StudySmart.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    StudySmartWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
