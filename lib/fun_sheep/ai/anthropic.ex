defmodule FunSheep.AI.Anthropic do
  @moduledoc """
  Direct Anthropic Messages API client.

  Uses the existing `FunSheep.Finch` pool (200 × 4 slots). Auth via
  `ANTHROPIC_API_KEY` environment variable / application config.
  """

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"
  @max_retries 3
  @finch_opts [finch: FunSheep.Finch]

  @spec call(String.t(), String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def call(system_prompt, user_prompt, opts) do
    model = Map.fetch!(opts, :model)
    max_tokens = Map.fetch!(opts, :max_tokens)
    temperature = Map.get(opts, :temperature, 0.0)
    timeout = Map.get(opts, :timeout, 60_000)
    source = Map.get(opts, :source, "unknown")

    body = %{
      model: model,
      max_tokens: max_tokens,
      temperature: temperature,
      system: system_prompt,
      messages: [%{role: "user", content: user_prompt}]
    }

    do_call(body, timeout, source, 0)
  end

  defp do_call(body, timeout, source, attempt) do
    case Req.post(@api_url,
           [json: body,
            headers: headers(),
            receive_timeout: timeout,
            retry: false] ++ extra_req_opts() ++ @finch_opts) do
      {:ok, %{status: 200, body: resp}} ->
        extract_text(resp)

      {:ok, %{status: 429, headers: resp_headers, body: resp_body}} ->
        if attempt < @max_retries do
          wait = retry_wait(resp_headers, resp_body, attempt)
          Logger.warning("[AI.Anthropic] Rate limited (429), waiting #{wait}ms (attempt #{attempt + 1})")
          Process.sleep(wait)
          do_call(body, timeout, source, attempt + 1)
        else
          Logger.error("[AI.Anthropic] Rate limited after #{@max_retries} retries [#{source}]")
          {:error, :rate_limited}
        end

      {:ok, %{status: 529, headers: resp_headers, body: resp_body}} ->
        # Anthropic overload response
        if attempt < @max_retries do
          wait = retry_wait(resp_headers, resp_body, attempt)
          Logger.warning("[AI.Anthropic] Overloaded (529), waiting #{wait}ms (attempt #{attempt + 1})")
          Process.sleep(wait)
          do_call(body, timeout, source, attempt + 1)
        else
          {:error, :overloaded}
        end

      {:ok, %{status: status, body: resp_body}} ->
        Logger.error("[AI.Anthropic] HTTP #{status} [#{source}]: #{inspect(resp_body)}")
        {:error, {status, resp_body}}

      {:error, %{reason: :timeout}} ->
        Logger.error("[AI.Anthropic] Timeout [#{source}]")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("[AI.Anthropic] Request failed [#{source}]: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_text(%{"content" => [%{"type" => "text", "text" => text} | _]}), do: {:ok, text}
  defp extract_text(%{"content" => content}), do: {:error, {:unexpected_content, content}}
  defp extract_text(body), do: {:error, {:unexpected_response, body}}

  defp headers do
    api_key = Application.fetch_env!(:fun_sheep, :anthropic_api_key)

    [
      {"x-api-key", api_key},
      {"anthropic-version", @api_version},
      {"content-type", "application/json"}
    ]
  end

  defp retry_wait(headers, body, attempt) do
    header_val =
      Enum.find_value(headers, fn
        {"retry-after", v} -> v
        {"Retry-After", v} -> v
        _ -> nil
      end)

    cond do
      is_binary(header_val) ->
        case Integer.parse(header_val) do
          {n, _} -> n * 1_000
          :error -> backoff(attempt)
        end

      is_map(body) && body["retry_after"] ->
        body["retry_after"] * 1_000

      true ->
        backoff(attempt)
    end
  end

  defp backoff(attempt) do
    base = Application.get_env(:fun_sheep, :ai_backoff_base_ms, 1_000)
    :math.pow(2, attempt) |> round() |> Kernel.*(base)
  end

  # Allows tests to inject `plug: {Req.Test, __MODULE__}` without hitting the network.
  defp extra_req_opts, do: Application.get_env(:fun_sheep, :anthropic_req_opts, [])
end
