defmodule FunSheep.AIUsage.Pricing do
  @moduledoc """
  Vendor pricing table for per-model LLM token cost estimation.

  Values are stored as `{input_per_M_cents, output_per_M_cents}` where both
  numbers are integer US cents per 1,000,000 tokens. For example, GPT-4o
  input at `$2.50 / 1M tokens` is stored as `250`.

  Pricing is pulled from each vendor's public pricing page; revisit quarterly
  or after any public price change. `@last_verified` is the date the table
  was last reconciled.
  """

  @last_verified ~D[2026-04-22]

  @prices %{
    "gpt-4o" => {250, 1000},
    "gpt-4o-mini" => {15, 60},
    "gpt-4-turbo" => {1000, 3000},
    "claude-opus-4-5" => {1500, 7500},
    "claude-sonnet-4-6" => {300, 1500},
    "claude-haiku-4-5" => {80, 400},
    "gemini-1.5-pro" => {350, 1050},
    "gemini-1.5-flash" => {8, 30}
  }

  @doc "Returns the date this table was last verified against vendor pricing."
  def last_verified, do: @last_verified

  @doc "Returns all models with known pricing."
  @spec known_models() :: [String.t()]
  def known_models, do: Map.keys(@prices) |> Enum.sort()

  @doc """
  Estimated cost for a single call in integer US cents.

  Returns `nil` when the model is unknown or not provided. Small calls may
  round to `0` — callers that need sub-cent precision for aggregations
  should use `cost_microcents/3` and round at the end.
  """
  @spec cost_cents(String.t() | nil, non_neg_integer() | nil, non_neg_integer() | nil) ::
          non_neg_integer() | nil
  def cost_cents(model, prompt_tokens, completion_tokens) do
    case cost_microcents(model, prompt_tokens, completion_tokens) do
      nil -> nil
      microcents -> div(microcents + 500_000, 1_000_000)
    end
  end

  @doc """
  Cost as micro-cents (1/1M of one US cent) — useful for aggregating many
  small-value calls without losing precision to per-row rounding.

  Returns `nil` for unknown models.
  """
  @spec cost_microcents(String.t() | nil, non_neg_integer() | nil, non_neg_integer() | nil) ::
          non_neg_integer() | nil
  def cost_microcents(model, prompt_tokens, completion_tokens) do
    case lookup(model) do
      {in_rate, out_rate} ->
        prompt = prompt_tokens || 0
        completion = completion_tokens || 0
        prompt * in_rate + completion * out_rate

      nil ->
        nil
    end
  end

  @doc """
  Formats integer cents as `"$X.XX"`. `nil` renders as `"—"`.
  """
  @spec format_cost_cents(integer() | nil) :: String.t()
  def format_cost_cents(nil), do: "—"

  def format_cost_cents(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remainder = rem(abs(cents), 100)
    sign = if cents < 0, do: "-", else: ""
    "#{sign}$#{dollars |> abs() |> Integer.to_string()}.#{pad2(remainder)}"
  end

  defp pad2(n) when n < 10, do: "0#{n}"
  defp pad2(n), do: Integer.to_string(n)

  defp lookup(nil), do: nil
  defp lookup(model) when is_binary(model), do: Map.get(@prices, model)
  defp lookup(_), do: nil
end
