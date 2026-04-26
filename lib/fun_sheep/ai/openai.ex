defmodule FunSheep.AI.OpenAI do
  @moduledoc """
  Direct OpenAI Chat Completions API client.

  Uses the existing `FunSheep.Finch` pool. Auth via `OPENAI_API_KEY`
  environment variable / application config.
  """

  require Logger

  @api_url "https://api.openai.com/v1/chat/completions"
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
      messages: [
        %{role: "system", content: system_prompt},
        %{role: "user", content: user_prompt}
      ]
    }

    do_call(body, timeout, source, 0)
  end

  defp do_call(body, timeout, source, attempt) do
    case Req.post(
           @api_url,
           [json: body, headers: headers(), receive_timeout: timeout, retry: false] ++
             extra_req_opts() ++ @finch_opts
         ) do
      {:ok, %{status: 200, body: resp}} ->
        extract_text(resp)

      {:ok, %{status: 429, headers: resp_headers, body: resp_body}} ->
        if attempt < @max_retries do
          wait = retry_wait(resp_headers, resp_body, attempt)

          Logger.warning(
            "[AI.OpenAI] Rate limited (429), waiting #{wait}ms (attempt #{attempt + 1})"
          )

          Process.sleep(wait)
          do_call(body, timeout, source, attempt + 1)
        else
          Logger.error("[AI.OpenAI] Rate limited after #{@max_retries} retries [#{source}]")
          {:error, :rate_limited}
        end

      {:ok, %{status: status, body: resp_body}} ->
        Logger.error("[AI.OpenAI] HTTP #{status} [#{source}]: #{inspect(resp_body)}")
        {:error, {status, resp_body}}

      {:error, %{reason: :timeout}} ->
        Logger.error("[AI.OpenAI] Timeout [#{source}]")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("[AI.OpenAI] Request failed [#{source}]: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_text(%{
         "choices" => [%{"finish_reason" => "length", "message" => %{"content" => partial}} | _]
       }) do
    Logger.warning(
      "[AI.OpenAI] Response truncated (finish_reason=length); partial content: #{String.slice(partial || "", 0, 200)}"
    )

    {:error, :response_truncated}
  end

  defp extract_text(%{"choices" => [%{"message" => %{"content" => text}} | _]}), do: {:ok, text}
  defp extract_text(%{"choices" => choices}), do: {:error, {:unexpected_choices, choices}}
  defp extract_text(body), do: {:error, {:unexpected_response, body}}

  defp headers do
    api_key = Application.fetch_env!(:fun_sheep, :openai_api_key)
    [{"authorization", "Bearer #{api_key}"}, {"content-type", "application/json"}]
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

      is_map(body) && is_map(body["error"]) && body["error"]["retry_after"] ->
        body["error"]["retry_after"] * 1_000

      true ->
        backoff(attempt)
    end
  end

  defp backoff(attempt) do
    base = Application.get_env(:fun_sheep, :ai_backoff_base_ms, 1_000)
    :math.pow(2, attempt) |> round() |> Kernel.*(base)
  end

  # Allows tests to inject `plug: {Req.Test, __MODULE__}` without hitting the network.
  defp extra_req_opts, do: Application.get_env(:fun_sheep, :openai_req_opts, [])
end
