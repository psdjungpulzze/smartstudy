defmodule FunSheep.AIUsage.Tokenizer do
  @moduledoc """
  Estimates token counts for LLM prompts and responses using the
  industry `chars / 4` heuristic.

  Dependency-free, fast, and accurate to roughly ±20% on English prose
  across GPT, Claude, and Gemini tokenizers. Intentionally approximate:
  these estimates are a stopgap while the Interactor Agents API does
  not yet pass the upstream `usage` block through. Once it does,
  `FunSheep.AIUsage.log_call/1` prefers those exact counts and skips
  this module entirely.

  If higher-accuracy estimation becomes necessary before the Interactor
  passthrough ships, swap the implementation for a BPE tokenizer
  (e.g. `tiktoken`). `log_call/1` records the source of the count in
  the `:token_source` column, so the schema doesn't change.
  """

  @chars_per_token 4

  @spec count(binary() | nil) :: non_neg_integer()
  def count(nil), do: 0
  def count(""), do: 0

  def count(text) when is_binary(text) do
    div(String.length(text) + (@chars_per_token - 1), @chars_per_token)
  end
end
