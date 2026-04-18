defmodule FunSheep.Interactor.Client do
  @moduledoc """
  Shared HTTP client helpers for Interactor API calls.

  Provides `get/1` and `post/2` that handle:
  - Mock mode (returns stub data without HTTP calls)
  - Token injection from `FunSheep.Interactor.Auth`
  - Consistent error handling
  """

  require Logger

  @doc """
  Performs a GET request to the given Interactor API path.

  Returns `{:ok, body}` or `{:error, reason}`.
  In mock mode returns `{:ok, %{"data" => []}}`.
  """
  @spec get(String.t()) :: {:ok, map()} | {:error, term()}
  def get(path) do
    if mock_mode?() do
      {:ok, %{"data" => []}}
    else
      with {:ok, token} <- FunSheep.Interactor.Auth.get_token() do
        case Req.get(base_url() <> path, headers: auth_headers(token)) do
          {:ok, %{status: 200, body: body}} -> {:ok, body}
          {:ok, %{status: status, body: body}} -> {:error, {status, body}}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  @doc """
  Performs a POST request to the given Interactor API path with a JSON body.

  Returns `{:ok, body}` or `{:error, reason}`.
  In mock mode returns `{:ok, %{"data" => ...}}` with a mock ID merged into the input.
  """
  @spec post(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def post(path, body) do
    if mock_mode?() do
      mock_data = Map.merge(%{"id" => "mock_#{:rand.uniform(100_000)}"}, stringify_keys(body))
      {:ok, %{"data" => mock_data}}
    else
      with {:ok, token} <- FunSheep.Interactor.Auth.get_token() do
        case Req.post(base_url() <> path, json: body, headers: auth_headers(token)) do
          {:ok, %{status: status, body: resp_body}} when status in [200, 201] ->
            {:ok, resp_body}

          {:ok, %{status: status, body: resp_body}} ->
            {:error, {status, resp_body}}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  @doc """
  Performs a PUT request to the given Interactor API path with a JSON body.
  """
  @spec put(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def put(path, body) do
    if mock_mode?() do
      mock_data = Map.merge(%{"id" => "mock_#{:rand.uniform(100_000)}"}, stringify_keys(body))
      {:ok, %{"data" => mock_data}}
    else
      with {:ok, token} <- FunSheep.Interactor.Auth.get_token() do
        case Req.put(base_url() <> path, json: body, headers: auth_headers(token)) do
          {:ok, %{status: status, body: resp_body}} when status in [200, 201] ->
            {:ok, resp_body}

          {:ok, %{status: status, body: resp_body}} ->
            {:error, {status, resp_body}}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  # --- Helpers ---

  defp auth_headers(token), do: [{"authorization", "Bearer #{token}"}]

  defp base_url,
    do: Application.get_env(:fun_sheep, :interactor_core_url, "https://core.interactor.com")

  defp mock_mode?, do: Application.get_env(:fun_sheep, :interactor_mock, true)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
