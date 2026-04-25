defmodule FunSheep.Interactor.Auth do
  @moduledoc """
  Interactor OAuth 2.0 client credentials authentication.

  Exchanges client_id/client_secret for an access_token, caches the token
  in GenServer state, and refreshes before expiry.

  Fast path: `get_token/0` reads from ETS first so concurrent callers
  (e.g. multiple Oban workers on the :ai queue) bypass the GenServer
  entirely when a valid token is already cached.  Only token refresh — a
  rare, serialized event — goes through the GenServer.

  In mock mode (default for dev/test), returns a static mock token
  without making any HTTP requests.
  """

  use GenServer

  require Logger

  @table :interactor_auth_cache
  @refresh_buffer_seconds 120
  # Generous timeout: only hit during token refresh (HTTP round-trip). 5 s
  # was too tight when Interactor auth is under load; 30 s gives the HTTP
  # call headroom without hanging callers indefinitely.
  @call_timeout 30_000

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns `{:ok, token}` or `{:error, reason}`.

  Reads from ETS first (no GenServer roundtrip when token is fresh).
  Falls back to GenServer only for refresh.
  In mock mode, always returns `{:ok, "mock_interactor_token"}`.
  """
  @spec get_token() :: {:ok, String.t()} | {:error, term()}
  def get_token do
    if mock_mode?() do
      {:ok, "mock_interactor_token"}
    else
      case ets_get_valid_token() do
        {:ok, token} -> {:ok, token}
        :expired -> GenServer.call(__MODULE__, :get_token, @call_timeout)
      end
    end
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    # If the named table already exists (e.g. when a test starts a second
    # Auth GenServer alongside the one started by the application supervisor),
    # reuse it rather than crashing.
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, read_concurrency: true])
      _tid -> @table
    end

    {:ok, %{token: nil, expires_at: nil}}
  end

  @impl true
  def handle_call(:get_token, _from, state) do
    # Re-check ETS in case another concurrent caller already refreshed.
    case ets_get_valid_token() do
      {:ok, token} ->
        {:reply, {:ok, token}, state}

      :expired ->
        case fetch_token() do
          {:ok, token, expires_at} ->
            :ets.insert(@table, {:token, token, expires_at})
            {:reply, {:ok, token}, state}

          error ->
            Logger.error("Failed to fetch Interactor token: #{inspect(error)}")
            {:reply, error, state}
        end
    end
  end

  # --- Private Helpers ---

  defp ets_get_valid_token do
    case :ets.lookup(@table, :token) do
      [{:token, token, expires_at}] ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
          {:ok, token}
        else
          :expired
        end

      [] ->
        :expired
    end
  end

  defp fetch_token do
    url = "#{interactor_url()}/oauth/token"

    body = [
      grant_type: "client_credentials",
      client_id: client_id(),
      client_secret: client_secret()
    ]

    # Use the dedicated FunSheep.Finch pool — Auth.get_token/0 sits in
    # front of every other Interactor call (the worker queue ↔ LLM hot
    # path), so it must not compete with the same-pool requests it gates.
    case Req.post(url, form: body, finch: FunSheep.Finch) do
      {:ok, %{status: 200, body: %{"access_token" => token, "expires_in" => expires_in}}} ->
        expires_at =
          DateTime.utc_now()
          |> DateTime.add(expires_in - @refresh_buffer_seconds, :second)

        {:ok, token, expires_at}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {status, resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp mock_mode?, do: Application.get_env(:fun_sheep, :interactor_mock, false)

  defp interactor_url,
    do: Application.get_env(:fun_sheep, :interactor_url, "https://auth.interactor.com")

  defp client_id, do: Application.get_env(:fun_sheep, :interactor_client_id, "")
  defp client_secret, do: Application.get_env(:fun_sheep, :interactor_client_secret, "")
end
