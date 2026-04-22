defmodule FunSheep.Interactor.Client do
  @moduledoc """
  Shared HTTP client helpers for Interactor API calls.

  Provides `get/1` and `post/2` that handle:
  - Mock mode (returns stub data without HTTP calls)
  - Token injection from `FunSheep.Interactor.Auth`
  - Rate limit retry with backoff (429 responses)
  - Consistent error handling
  """

  require Logger

  @max_retries 3

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
        do_get(path, token, 0)
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
        do_post(path, body, token, 0)
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
        do_put(path, body, token, 0)
      end
    end
  end

  # --- Request execution with rate limit retry ---

  defp do_get(path, token, attempt) do
    case Req.get(base_url() <> path, headers: auth_headers(token)) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 429} = resp} ->
        maybe_retry(:get, {path, token}, resp, attempt)

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_post(path, body, token, attempt) do
    case Req.post(base_url() <> path, json: body, headers: auth_headers(token)) do
      {:ok, %{status: status, body: resp_body}} when status in [200, 201] ->
        {:ok, resp_body}

      {:ok, %{status: 429} = resp} ->
        maybe_retry(:post, {path, body, token}, resp, attempt)

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {status, resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_put(path, body, token, attempt) do
    case Req.put(base_url() <> path, json: body, headers: auth_headers(token)) do
      {:ok, %{status: status, body: resp_body}} when status in [200, 201] ->
        {:ok, resp_body}

      {:ok, %{status: 429} = resp} ->
        maybe_retry(:put, {path, body, token}, resp, attempt)

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {status, resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Rate limit retry logic ---

  defp maybe_retry(_method, _args, %{status: 429, body: body}, attempt)
       when attempt >= @max_retries do
    Logger.warning("[Client] Rate limited after #{@max_retries} retries, giving up")
    {:error, {429, body}}
  end

  defp maybe_retry(method, args, %{status: 429, body: body, headers: headers}, attempt) do
    retry_after = parse_retry_after(headers, body)
    wait_ms = retry_after * 1_000

    Logger.info(
      "[Client] Rate limited (429), waiting #{retry_after}s before retry #{attempt + 1}/#{@max_retries}"
    )

    Process.sleep(wait_ms)

    case {method, args} do
      {:get, {path, token}} -> do_get(path, token, attempt + 1)
      {:post, {path, req_body, token}} -> do_post(path, req_body, token, attempt + 1)
      {:put, {path, req_body, token}} -> do_put(path, req_body, token, attempt + 1)
    end
  end

  defp parse_retry_after(headers, body) do
    # Check Retry-After header first
    header_val =
      headers
      |> Enum.find_value(fn
        {"retry-after", val} -> val
        {"Retry-After", val} -> val
        _ -> nil
      end)

    cond do
      is_binary(header_val) -> parse_int(header_val, 60)
      is_map(body) && body["retry_after"] -> body["retry_after"]
      true -> 60
    end
  end

  defp parse_int(str, default) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> default
    end
  end

  # --- Helpers ---

  defp auth_headers(token), do: [{"authorization", "Bearer #{token}"}]

  defp base_url,
    do: Application.get_env(:fun_sheep, :interactor_core_url, "https://core.interactor.com")

  defp mock_mode?, do: Application.get_env(:fun_sheep, :interactor_mock, false)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
