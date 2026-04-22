defmodule FunSheep.AIUsage.Tokenizer do
  @moduledoc """
  Estimates token counts for LLM prompts and responses.

  Uses the industry `chars / 4` heuristic — fast, dependency-free, and
  accurate to roughly ±20% on English prose across GPT, Claude, and Gemini
  tokenizers. This is intentionally approximate: these counts are a
  stopgap while the Interactor Agents API does not yet expose the
  upstream `usage` block (see the corresponding Interactor PR). Once that
  passthrough lands, `FunSheep.AIUsage.log_call/1` prefers the exact
  counts from the Interactor response and skips this module.

  If higher accuracy becomes necessary before the passthrough ships, swap
  this module for a BPE tokenizer (e.g. `tiktoken`) — `log_call/1`
  already records the source of the count in the `:token_source` column,
  so the schema doesn't need to change.
  """

  @chars_per_token 4

  @doc """
  Estimate tokens for the given text. Empty or nil returns 0.
  """
  @spec count(binary() | nil) :: non_neg_integer()
  def count(nil), do: 0
  def count(""), do: 0

  def count(text) when is_binary(text) do
    # Round up so a single character still counts as one token.
    div(String.length(text) + (@chars_per_token - 1), @chars_per_token)
  end
end
