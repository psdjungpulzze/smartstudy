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

  ## Query API

  The query helpers (`summary/1`, `by_assistant/1`, `time_series/2`, etc.)
  power the `/admin/usage/ai` dashboard. All of them accept the same
  `filters` map — see `@type filters/0`.
  """

  import Ecto.Query, warn: false

  alias FunSheep.AIUsage.{Call, Pricing, Tokenizer}
  alias FunSheep.Repo

  require Logger

  @type filters :: %{
          optional(:since) => DateTime.t(),
          optional(:until) => DateTime.t(),
          optional(:env) => String.t() | [String.t()] | :any,
          optional(:provider) => String.t() | [String.t()] | :any,
          optional(:assistant_name) => String.t() | :any,
          optional(:source) => String.t() | :any,
          optional(:model) => String.t() | :any,
          optional(:status) => String.t() | [String.t()] | :any
        }

  @type bucket_size :: :hour | :day | :week

  @type summary :: %{
          calls: non_neg_integer(),
          prompt_tokens: non_neg_integer(),
          completion_tokens: non_neg_integer(),
          total_tokens: non_neg_integer(),
          errors: non_neg_integer(),
          p50_ms: float() | nil,
          p95_ms: float() | nil,
          est_cost_cents: non_neg_integer() | nil
        }

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

  defp stringify_metadata(%{} = m) do
    Map.new(m, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_metadata(_), do: %{}

  ## --- Query API --------------------------------------------------------

  @doc """
  Aggregate totals for the filtered window.

  Returns a `t:summary/0` map. `est_cost_cents` is computed per-model then
  summed so multi-model groups stay accurate.
  """
  @spec summary(filters()) :: summary()
  def summary(filters) do
    rows = summary_by_model_rows(filters)
    latency = latency_percentiles(filters)
    aggregate_summary(rows, latency)
  end

  @doc """
  Same as `summary/1` but also returns deltas vs. the prior window of
  equal length (`prior_start = 2*since - until`).

  `:calls_delta_pct`, `:tokens_delta_pct`, `:cost_delta_pct`, and
  `:errors_delta_pct` are `nil` when the prior window is empty (divide by
  zero).
  """
  @spec summary_with_delta(filters()) :: map()
  def summary_with_delta(filters) do
    since = Map.get(filters, :since) || ~U[1970-01-01 00:00:00Z]
    until_dt = Map.get(filters, :until) || DateTime.utc_now()

    window_seconds = DateTime.diff(until_dt, since)
    prior_since = DateTime.add(since, -window_seconds, :second)
    prior_until = since

    current = summary(filters)
    prior = summary(%{filters | since: prior_since, until: prior_until})

    Map.merge(current, %{
      prior: prior,
      calls_delta_pct: pct_delta(current.calls, prior.calls),
      tokens_delta_pct: pct_delta(current.total_tokens, prior.total_tokens),
      cost_delta_pct: pct_delta(current.est_cost_cents, prior.est_cost_cents),
      errors_delta_pct: pct_delta(current.errors, prior.errors)
    })
  end

  @doc """
  Aggregate grouped on `assistant_name`.

  Returns a list of maps:
  `%{key, calls, prompt_tokens, completion_tokens, total_tokens,
     est_cost_cents, avg_ms, p95_ms, errors, last_seen}`
  """
  @spec by_assistant(filters()) :: [map()]
  def by_assistant(filters), do: grouped(filters, :assistant_name)

  @doc "Aggregate grouped on `source`. See `by_assistant/1`."
  @spec by_source(filters()) :: [map()]
  def by_source(filters), do: grouped(filters, :source)

  @doc "Aggregate grouped on `model`. See `by_assistant/1`."
  @spec by_model(filters()) :: [map()]
  def by_model(filters), do: grouped(filters, :model)

  @doc """
  Bucketed token totals for the chart.

  Returns a list of maps `%{bucket_at, prompt_tokens, completion_tokens}`
  in ascending order, zero-filled across the range.
  """
  @spec time_series(filters(), bucket_size()) :: [map()]
  def time_series(filters, bucket_size) when bucket_size in [:hour, :day, :week] do
    since = Map.get(filters, :since) || default_since()
    until_dt = Map.get(filters, :until) || DateTime.utc_now()

    rows = bucketed_rows(filters, bucket_size)
    rows_by_bucket = Map.new(rows, &{truncate_bucket(&1.bucket_at, bucket_size), &1})

    bucket_range(since, until_dt, bucket_size)
    |> Enum.map(fn bucket ->
      case Map.get(rows_by_bucket, bucket) do
        nil -> %{bucket_at: bucket, prompt_tokens: 0, completion_tokens: 0}
        row -> %{row | bucket_at: bucket}
      end
    end)
  end

  defp bucketed_rows(filters, :hour) do
    from(c in Call)
    |> apply_filters(filters)
    |> group_by([c], fragment("date_trunc('hour', ?)", c.inserted_at))
    |> select([c], %{
      bucket_at: fragment("date_trunc('hour', ?)", c.inserted_at),
      prompt_tokens: coalesce(sum(c.prompt_tokens), 0),
      completion_tokens: coalesce(sum(c.completion_tokens), 0)
    })
    |> Repo.all()
  end

  defp bucketed_rows(filters, :day) do
    from(c in Call)
    |> apply_filters(filters)
    |> group_by([c], fragment("date_trunc('day', ?)", c.inserted_at))
    |> select([c], %{
      bucket_at: fragment("date_trunc('day', ?)", c.inserted_at),
      prompt_tokens: coalesce(sum(c.prompt_tokens), 0),
      completion_tokens: coalesce(sum(c.completion_tokens), 0)
    })
    |> Repo.all()
  end

  defp bucketed_rows(filters, :week) do
    from(c in Call)
    |> apply_filters(filters)
    |> group_by([c], fragment("date_trunc('week', ?)", c.inserted_at))
    |> select([c], %{
      bucket_at: fragment("date_trunc('week', ?)", c.inserted_at),
      prompt_tokens: coalesce(sum(c.prompt_tokens), 0),
      completion_tokens: coalesce(sum(c.completion_tokens), 0)
    })
    |> Repo.all()
  end

  @doc "Recent calls (any status), newest first."
  @spec recent_calls(filters(), pos_integer()) :: [Call.t()]
  def recent_calls(filters, limit \\ 25) do
    from(c in Call)
    |> apply_filters(filters)
    |> order_by([c], desc: c.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Recent error/timeout calls, newest first."
  @spec recent_errors(filters(), pos_integer()) :: [Call.t()]
  def recent_errors(filters, limit \\ 25) do
    filters
    |> Map.put(:status, ["error", "timeout"])
    |> recent_calls(limit)
  end

  @doc "Most expensive calls in the filtered window, sorted by total_tokens desc."
  @spec top_calls(filters(), pos_integer()) :: [Call.t()]
  def top_calls(filters, limit \\ 25) do
    from(c in Call)
    |> apply_filters(filters)
    |> order_by([c], desc: c.total_tokens)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Fetches a single call by id, raising if not found."
  @spec get_call!(binary()) :: Call.t()
  def get_call!(id), do: Repo.get!(Call, id)

  ## --- Internal helpers -------------------------------------------------

  defp grouped(filters, group_col) do
    rows =
      from(c in Call)
      |> apply_filters(filters)
      |> group_by([c], [field(c, ^group_col), c.model])
      |> select([c], %{
        key: field(c, ^group_col),
        model: c.model,
        calls: count(c.id),
        prompt_tokens: coalesce(sum(c.prompt_tokens), 0),
        completion_tokens: coalesce(sum(c.completion_tokens), 0),
        total_tokens: coalesce(sum(c.total_tokens), 0),
        errors: fragment("SUM(CASE WHEN ? IN ('error','timeout') THEN 1 ELSE 0 END)", c.status),
        avg_ms: avg(c.duration_ms),
        last_seen: max(c.inserted_at)
      })
      |> Repo.all()

    latency_by_group = latency_percentiles_grouped(filters, group_col)

    rows
    |> Enum.group_by(& &1.key)
    |> Enum.map(fn {key, model_rows} ->
      %{
        key: key,
        calls: sum_field(model_rows, :calls),
        prompt_tokens: sum_field(model_rows, :prompt_tokens),
        completion_tokens: sum_field(model_rows, :completion_tokens),
        total_tokens: sum_field(model_rows, :total_tokens),
        errors: sum_field(model_rows, :errors),
        avg_ms: weighted_avg(model_rows, :avg_ms, :calls),
        p95_ms: Map.get(latency_by_group, key, %{}) |> Map.get(:p95_ms),
        last_seen: model_rows |> Enum.map(& &1.last_seen) |> Enum.max(DateTime, fn -> nil end),
        est_cost_cents: cost_cents_for_rows(model_rows)
      }
    end)
    |> Enum.sort_by(& &1.total_tokens, :desc)
  end

  defp summary_by_model_rows(filters) do
    from(c in Call)
    |> apply_filters(filters)
    |> group_by([c], c.model)
    |> select([c], %{
      model: c.model,
      calls: count(c.id),
      prompt_tokens: coalesce(sum(c.prompt_tokens), 0),
      completion_tokens: coalesce(sum(c.completion_tokens), 0),
      total_tokens: coalesce(sum(c.total_tokens), 0),
      errors: fragment("SUM(CASE WHEN ? IN ('error','timeout') THEN 1 ELSE 0 END)", c.status)
    })
    |> Repo.all()
  end

  defp aggregate_summary(rows, latency) do
    %{
      calls: sum_field(rows, :calls),
      prompt_tokens: sum_field(rows, :prompt_tokens),
      completion_tokens: sum_field(rows, :completion_tokens),
      total_tokens: sum_field(rows, :total_tokens),
      errors: sum_field(rows, :errors),
      p50_ms: latency.p50_ms,
      p95_ms: latency.p95_ms,
      est_cost_cents: cost_cents_for_rows(rows)
    }
  end

  defp latency_percentiles(filters) do
    row =
      from(c in Call)
      |> apply_filters(filters)
      |> where([c], not is_nil(c.duration_ms))
      |> select([c], %{
        p50_ms:
          fragment(
            "PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ?)",
            c.duration_ms
          ),
        p95_ms:
          fragment(
            "PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ?)",
            c.duration_ms
          )
      })
      |> Repo.one()

    row || %{p50_ms: nil, p95_ms: nil}
  end

  defp latency_percentiles_grouped(filters, group_col) do
    from(c in Call)
    |> apply_filters(filters)
    |> where([c], not is_nil(c.duration_ms))
    |> group_by([c], field(c, ^group_col))
    |> select([c], %{
      key: field(c, ^group_col),
      p95_ms:
        fragment(
          "PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ?)",
          c.duration_ms
        )
    })
    |> Repo.all()
    |> Map.new(&{&1.key, &1})
  end

  defp cost_cents_for_rows(rows) do
    microcents =
      Enum.reduce(rows, {0, false}, fn row, {acc, any?} ->
        case Pricing.cost_microcents(row.model, row.prompt_tokens, row.completion_tokens) do
          nil -> {acc, any?}
          m -> {acc + m, true}
        end
      end)

    case microcents do
      {_, false} -> nil
      {sum, true} -> div(sum + 500_000, 1_000_000)
    end
  end

  defp sum_field(rows, field), do: rows |> Enum.map(&Map.get(&1, field, 0)) |> Enum.sum()

  defp weighted_avg(rows, avg_field, weight_field) do
    {total_weight, weighted_sum} =
      Enum.reduce(rows, {0, 0.0}, fn row, {w_acc, s_acc} ->
        weight = Map.get(row, weight_field, 0) || 0
        avg = Map.get(row, avg_field)

        case avg do
          nil -> {w_acc, s_acc}
          %Decimal{} = d -> {w_acc + weight, s_acc + weight * Decimal.to_float(d)}
          n when is_number(n) -> {w_acc + weight, s_acc + weight * n}
        end
      end)

    if total_weight > 0, do: weighted_sum / total_weight, else: nil
  end

  defp pct_delta(_current, 0), do: nil
  defp pct_delta(_current, nil), do: nil
  defp pct_delta(nil, _prior), do: nil

  defp pct_delta(current, prior) when prior != 0 do
    (current - prior) / prior * 100.0
  end

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:since, %DateTime{} = dt}, q ->
        where(q, [c], c.inserted_at >= ^dt)

      {:until, %DateTime{} = dt}, q ->
        where(q, [c], c.inserted_at <= ^dt)

      {_k, :any}, q ->
        q

      {_k, nil}, q ->
        q

      {:env, v}, q ->
        apply_in_or_eq(q, :env, v)

      {:provider, v}, q ->
        apply_in_or_eq(q, :provider, v)

      {:assistant_name, v}, q ->
        apply_in_or_eq(q, :assistant_name, v)

      {:source, v}, q ->
        apply_in_or_eq(q, :source, v)

      {:model, v}, q ->
        apply_in_or_eq(q, :model, v)

      {:status, v}, q ->
        apply_in_or_eq(q, :status, v)

      _, q ->
        q
    end)
  end

  defp apply_in_or_eq(q, field, values) when is_list(values) and values != [] do
    where(q, [c], field(c, ^field) in ^values)
  end

  defp apply_in_or_eq(q, _field, []), do: q

  defp apply_in_or_eq(q, field, value) when is_binary(value) do
    where(q, [c], field(c, ^field) == ^value)
  end

  defp apply_in_or_eq(q, _field, _), do: q

  defp truncate_bucket(%DateTime{} = dt, :hour),
    do: %{dt | minute: 0, second: 0, microsecond: {0, 0}}

  defp truncate_bucket(%DateTime{} = dt, :day),
    do: %{dt | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}

  defp truncate_bucket(%DateTime{} = dt, :week) do
    day_of_week = Date.day_of_week(DateTime.to_date(dt))
    offset_days = day_of_week - 1
    floor = %{dt | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    DateTime.add(floor, -offset_days * 86_400, :second)
  end

  defp truncate_bucket(%NaiveDateTime{} = ndt, size) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> truncate_bucket(size)
  end

  defp truncate_bucket(other, _size), do: other

  defp bucket_range(since, until_dt, :hour),
    do: step_range(truncate_bucket(since, :hour), until_dt, 3600)

  defp bucket_range(since, until_dt, :day),
    do: step_range(truncate_bucket(since, :day), until_dt, 86_400)

  defp bucket_range(since, until_dt, :week),
    do: step_range(truncate_bucket(since, :week), until_dt, 7 * 86_400)

  defp step_range(start, until_dt, step_seconds) do
    Stream.unfold(start, fn cursor ->
      if DateTime.compare(cursor, until_dt) == :lt do
        next = DateTime.add(cursor, step_seconds, :second)
        {cursor, next}
      else
        nil
      end
    end)
    |> Enum.to_list()
  end

  defp default_since, do: DateTime.add(DateTime.utc_now(), -24 * 3600, :second)
end
