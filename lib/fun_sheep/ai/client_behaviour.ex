defmodule FunSheep.AI.ClientBehaviour do
  @moduledoc """
  Behaviour for single-turn LLM calls.

  The real implementation (`FunSheep.AI.Client`) dispatches to the Anthropic or
  OpenAI API based on the model name. Tests swap it for a Mox-backed mock via:

      Application.put_env(:fun_sheep, :ai_client_impl, FunSheep.AI.ClientMock)
  """

  @doc """
  Send a single-turn prompt to an LLM and return the text response.

  ## Options

    - `:model`       — model identifier, e.g. `"gpt-4o-mini"` or `"claude-haiku-4-5-20251001"`
    - `:max_tokens`  — upper bound on response tokens (required)
    - `:temperature` — sampling temperature (default: `0.0`)
    - `:timeout`     — request timeout in ms (default: `60_000`)
    - `:source`      — caller label for logs (default: `"unknown"`)
  """
  @callback call(
              system_prompt :: String.t(),
              user_prompt :: String.t(),
              opts :: map()
            ) :: {:ok, String.t()} | {:error, term()}
end
