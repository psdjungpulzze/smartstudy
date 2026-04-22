defmodule FunSheep.AIUsage do
  @moduledoc """
  Token usage telemetry for LLM calls that route through Interactor.

  FunSheep does not call OpenAI/Anthropic/Gemini directly — every LLM hop
  goes through `FunSheep.Interactor.Agents.chat/3`. This context records
  one row per call so we can attribute cost and volume per provider,
  assistant, environment, and call-site (worker, LiveView, etc).

  Counts come from one of two sources, tracked in `:token_source`:

    * `"interactor"` — the Interactor message response carried the vendor
      `usage` block (exact counts; happens once the Interactor passthrough
      PR is deployed).
    * `"estimated"` — we approximated prompt/response tokens locally via
      `FunSheep.AIUsage.Tokenizer` (chars/4 heuristic).

  Telemetry failures never propagate — they are logged and swallowed so
  the real work is never blocked.
  """

  alias FunSheep.AIUsage.{Call, Tokenizer}
  alias FunSheep.Repo

  require Logger

  @doc """
  Record one LLM call.

  Required keys in `attrs`: `:provider`, `:source`, `:status`.
  Exact counts (`:prompt_tokens`, `:completion_tokens`) win over raw
  `:prompt` / `:response` strings — pass whichever pair is available.
  """
  @spec log_call(map()) :: {:ok, Call.t()} | {:error, term()}
  def log_call(attrs) when is_map(attrs) do
    attrs
    |> build_row()
    |> persist()
  rescue
    e ->
      Logger.warning("[AIUsage] log_call crashed: #{Exception.message(e)}")
      {:error, e}
  end

  defp build_row(attrs) do
    {prompt_tokens, completion_tokens, token_source} = resolve_counts(attrs)
    total = (prompt_tokens || 0) + (completion_tokens || 0)

    %{
      provider: Map.get(attrs, :provider, "unknown"),
      model: Map.get(attrs, :model),
      assistant_name: Map.get(attrs, :assistant_name),
      source: Map.get(attrs, :source, "unknown"),
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: total,
      token_source: token_source,
      env: current_env(),
      duration_ms: Map.get(attrs, :duration_ms),
      status: Map.get(attrs, :status, "ok"),
      error: stringify_error(Map.get(attrs, :error)),
      metadata: stringify_metadata(Map.get(attrs, :metadata, %{}))
    }
  end

  # Exact counts from Interactor win. Otherwise estimate via the tokenizer.
  # A mixed case (one exact, one missing) falls back to estimation for the
  # missing half but still counts as "interactor"-sourced so dashboards can
  # trust the prompt side.
  defp resolve_counts(%{prompt_tokens: p, completion_tokens: c})
       when is_integer(p) and is_integer(c) do
    {p, c, "interactor"}
  end

  defp resolve_counts(%{prompt_tokens: p} = attrs) when is_integer(p) do
    {p, Tokenizer.count(Map.get(attrs, :response)), "interactor"}
  end

  defp resolve_counts(attrs) do
    {
      Tokenizer.count(Map.get(attrs, :prompt)),
      Tokenizer.count(Map.get(attrs, :response)),
      "estimated"
    }
  end

  defp persist(row) do
    %Call{}
    |> Call.changeset(row)
    |> Repo.insert()
    |> case do
      {:ok, _call} = ok ->
        ok

      {:error, changeset} = err ->
        Logger.warning("[AIUsage] insert failed: #{inspect(changeset.errors)}")
        err
    end
  end

  defp current_env do
    Application.get_env(:fun_sheep, :env, "prod") |> to_string()
  end

  defp stringify_error(nil), do: nil
  defp stringify_error(s) when is_binary(s), do: s
  defp stringify_error(other), do: inspect(other)

  # jsonb round-trips cleanly when keys are strings.
  defp stringify_metadata(%{} = m) do
    Map.new(m, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_metadata(_), do: %{}
end
