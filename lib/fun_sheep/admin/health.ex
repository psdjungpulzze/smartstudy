defmodule FunSheep.Admin.Health do
  @moduledoc """
  Service ping helpers for `/admin/health`.

  Each `check_*/0` returns `%{status: :ok | :degraded | :down, detail: map}`.
  The LiveView renders these as status tiles; callers never get raised
  exceptions — every check traps errors into a `:down` row.
  """

  import Ecto.Query, warn: false

  alias FunSheep.Repo

  @doc """
  Runs every declared probe and returns a map keyed by probe name.
  """
  @spec snapshot() :: %{atom() => map()}
  def snapshot do
    %{
      postgres: check_postgres(),
      oban: check_oban(),
      ai_calls: check_ai_calls(),
      mailer: check_mailer()
    }
  end

  ## --- Individual probes ----------------------------------------------

  @doc "Pings Postgres with a trivial SELECT 1 and reports pool size."
  @spec check_postgres() :: map()
  def check_postgres do
    case safe_query(fn -> Repo.query!("SELECT 1") end) do
      {:ok, _} ->
        %{status: :ok, detail: %{pool_size: Repo.config()[:pool_size]}}

      {:error, reason} ->
        %{status: :down, detail: %{error: inspect(reason)}}
    end
  end

  @doc """
  Reports Oban queue depths + job counts by state in the last hour.
  Degrades if any queue has > 500 `available` jobs (stuck producer).
  """
  @spec check_oban() :: map()
  def check_oban do
    case safe_query(fn -> oban_counts() end) do
      {:ok, counts} ->
        stuck = Enum.any?(counts.by_state, fn {state, n} -> state == "available" and n > 500 end)

        %{status: if(stuck, do: :degraded, else: :ok), detail: counts}

      {:error, reason} ->
        %{status: :down, detail: %{error: inspect(reason)}}
    end
  end

  defp oban_counts do
    one_hour_ago = DateTime.add(DateTime.utc_now(), -3600, :second)

    rows =
      from(j in Oban.Job,
        where: j.inserted_at >= ^one_hour_ago,
        group_by: j.state,
        select: {j.state, count(j.id)}
      )
      |> Repo.all()

    by_state = Map.new(rows)
    total = Enum.sum(Map.values(by_state))

    %{by_state: by_state, total_last_hour: total}
  end

  @doc """
  Reports the last Interactor call status from `ai_calls` — "unreachable"
  if the most recent call in the last 15 minutes was an error/timeout AND
  no subsequent success exists.
  """
  @spec check_ai_calls() :: map()
  def check_ai_calls do
    case safe_query(fn -> ai_stats() end) do
      {:ok, stats} ->
        status =
          cond do
            stats.total_last_15m == 0 -> :ok
            stats.errors_last_15m / max(stats.total_last_15m, 1) > 0.5 -> :degraded
            true -> :ok
          end

        %{status: status, detail: stats}

      {:error, reason} ->
        %{status: :down, detail: %{error: inspect(reason)}}
    end
  end

  defp ai_stats do
    cutoff = DateTime.add(DateTime.utc_now(), -15 * 60, :second)

    from(c in "ai_calls",
      where: c.inserted_at >= ^cutoff,
      select: %{
        total_last_15m: count(c.id),
        errors_last_15m:
          fragment("SUM(CASE WHEN ? IN ('error','timeout') THEN 1 ELSE 0 END)", c.status)
      }
    )
    |> Repo.one()
    |> Map.update!(:errors_last_15m, &(&1 || 0))
  end

  @doc "Very basic mailer probe — checks the adapter is configured."
  @spec check_mailer() :: map()
  def check_mailer do
    case Application.get_env(:fun_sheep, FunSheep.Mailer) do
      nil -> %{status: :degraded, detail: %{error: "mailer not configured"}}
      cfg -> %{status: :ok, detail: %{adapter: inspect(cfg[:adapter])}}
    end
  end

  ## --- Helpers --------------------------------------------------------

  defp safe_query(fun) when is_function(fun, 0) do
    {:ok, fun.()}
  rescue
    e -> {:error, e}
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
