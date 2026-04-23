defmodule FunSheep.Interactor.Auth do
  @moduledoc """
  Interactor OAuth 2.0 client credentials authentication.

  Exchanges client_id/client_secret for an access_token, caches the token
  in GenServer state, and refreshes before expiry.

  In mock mode (default for dev/test), returns a static mock token
  without making any HTTP requests.
  """

  use GenServer

  require Logger

  @refresh_buffer_seconds 120

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns `{:ok, token}` or `{:error, reason}`.

  In mock mode, always returns `{:ok, "mock_interactor_token"}`.
  """
  @spec get_token() :: {:ok, String.t()} | {:error, term()}
  def get_token do
    if mock_mode?() do
      {:ok, "mock_interactor_token"}
    else
      GenServer.call(__MODULE__, :get_token)
    end
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    {:ok, %{token: nil, expires_at: nil}}
  end

  @impl true
  def handle_call(:get_token, _from, state) do
    case state do
      %{token: token, expires_at: exp} when not is_nil(token) ->
        if DateTime.compare(exp, DateTime.utc_now()) == :gt do
          {:reply, {:ok, token}, state}
        else
          refresh_and_reply(state)
        end

      _ ->
        refresh_and_reply(state)
    end
  end

  # --- Private Helpers ---

  defp refresh_and_reply(state) do
    case fetch_token() do
      {:ok, token, expires_at} ->
        {:reply, {:ok, token}, %{state | token: token, expires_at: expires_at}}

      error ->
        Logger.error("Failed to fetch Interactor token: #{inspect(error)}")
        {:reply, error, state}
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
