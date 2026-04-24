defmodule FunSheep.AI.Client do
  @moduledoc """
  Dispatches single-turn LLM calls to the correct provider based on model name.

  Routes `"claude-*"` models to `FunSheep.AI.Anthropic` and all others
  (including `"gpt-*"`, `"o1-*"`, etc.) to `FunSheep.AI.OpenAI`.

  Callers should always go through this module (or the behaviour) rather than
  the provider modules directly, so tests can swap the implementation via:

      Application.put_env(:fun_sheep, :ai_client_impl, FunSheep.AI.ClientMock)
  """

  @behaviour FunSheep.AI.ClientBehaviour

  @impl FunSheep.AI.ClientBehaviour
  def call(system_prompt, user_prompt, opts) do
    model = Map.fetch!(opts, :model)
    provider(model).call(system_prompt, user_prompt, opts)
  end

  defp provider("claude-" <> _), do: FunSheep.AI.Anthropic
  defp provider(_), do: FunSheep.AI.OpenAI
end
