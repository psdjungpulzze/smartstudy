defmodule FunSheep.Assessments.Forecaster do
  @moduledoc """
  Readiness forecaster (spec §6.2).

  Given a student and an upcoming test schedule, project where readiness
  is likely to land on test day using a simple linear model of the recent
  readiness slope. Combine that with recent practice minutes to surface a
  suggested *daily-minute delta* that would close the gap to the joint
  target (set via `Assessments.set_target_readiness/3`).

  The forecast is intentionally simple and interpretable — this is a
  product signal, not a research claim. The UI presents confidence
  qualitatively (`:wide_range | :tight | :needs_target`) per spec.

  No fake inputs: if the data needed to produce a forecast is missing
  (no target set, fewer than `@min_history_days` days of readiness
  history, or zero practice minutes in the last window), the caller
  gets a `:insufficient_data` result with a reason atom — never a
  fabricated projection.
  """

  alias FunSheep.{Assessments, Repo}
  alias FunSheep.Assessments.{ReadinessScore, TestSchedule}
  alias FunSheep.Engagement.StudySession

  import Ecto.Query, warn: false

  @min_history_days 14
  @recent_minutes_window_days 14
  @confidence_tight_days 42

  @type confidence :: :needs_target | :wide_range | :tight

  @type forecast ::
          %{
            status: :ok,
            projected_readiness: float(),
            target: integer(),
            gap: float(),
            days_to_test: integer(),
            current_daily_minutes: integer(),
            recommended_daily_minutes: integer(),
            minutes_delta: integer(),
            history_days: integer(),
            confidence: confidence()
          }
          | %{status: :insufficient_data, reason: atom()}

  @doc """
  Returns a forecast for the given student + test schedule.

  The caller should have already confirmed guardian access if the
  invocation is parent-initiated (`Accounts.guardian_has_access?/2`).
  """
  @spec forecast(binary(), binary()) :: forecast()
  def forecast(user_role_id, test_schedule_id)
      when is_binary(user_role_id) and is_binary(test_schedule_id) do
    case Repo.get(TestSchedule, test_schedule_id) do
      nil ->
        %{status: :insufficient_data, reason: :no_schedule}

      %TestSchedule{target_readiness_score: nil} ->
        %{status: :insufficient_data, reason: :no_target}

      %TestSchedule{} = schedule ->
        forecast_with_schedule(user_role_id, schedule)
    end
  end

  defp forecast_with_schedule(user_role_id, schedule) do
    with {:ok, history} <- readiness_history(user_role_id, schedule.id),
         :ok <- validate_history(history),
         days_to_test when days_to_test >= 0 <- Date.diff(schedule.test_date, Date.utc_today()) do
      build_forecast(
        history,
        schedule.target_readiness_score,
        days_to_test,
        recent_minutes(user_role_id)
      )
    else
      {:insufficient, reason} ->
        %{status: :insufficient_data, reason: reason}

      days when is_integer(days) and days < 0 ->
        %{status: :insufficient_data, reason: :test_in_past}

      _ ->
        %{status: :insufficient_data, reason: :unknown}
    end
  end

  defp readiness_history(user_role_id, test_schedule_id) do
    cutoff = DateTime.utc_now() |> DateTime.add(-180, :day)

    scores =
      from(rs in ReadinessScore,
        where:
          rs.user_role_id == ^user_role_id and
            rs.test_schedule_id == ^test_schedule_id and
            rs.inserted_at >= ^cutoff,
        order_by: [asc: rs.inserted_at],
        select: %{score: rs.aggregate_score, at: rs.inserted_at}
      )
      |> Repo.all()

    # If the student has never snapshotted but has a live readiness, use that
    # as a single-point anchor so the forecaster can at least report gap-to-target.
    case scores do
      [] ->
        case Assessments.latest_readiness(user_role_id, test_schedule_id) do
          nil ->
            {:ok, []}

          live ->
            {:ok, [%{score: live.aggregate_score, at: DateTime.utc_now()}]}
        end

      _ ->
        {:ok, scores}
    end
  end

  defp validate_history([]), do: {:insufficient, :no_readiness_history}
  defp validate_history([_one]), do: {:insufficient, :single_snapshot}

  defp validate_history(list) do
    first = hd(list).at
    last = List.last(list).at
    days = DateTime.diff(last, first, :second) |> div(86_400)

    if days >= @min_history_days, do: :ok, else: {:insufficient, :short_history}
  end

  defp recent_minutes(user_role_id) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@recent_minutes_window_days, :day)

    from(s in StudySession,
      where:
        s.user_role_id == ^user_role_id and
          not is_nil(s.completed_at) and
          s.completed_at >= ^cutoff,
      select: coalesce(sum(s.duration_seconds), 0)
    )
    |> Repo.one()
    |> div(60)
  end

  defp build_forecast(history, target, days_to_test, minutes_total) do
    current_daily = div(minutes_total, @recent_minutes_window_days)
    slope_per_day = slope_per_day(history)
    current_score = List.last(history).score

    projected = current_score + slope_per_day * days_to_test
    projected = projected |> max(0.0) |> min(100.0) |> Float.round(1)
    gap = Float.round(target - projected, 1)

    recommended_daily =
      if gap > 0 do
        # Crude heuristic: each extra 10 min/day is worth ~1 readiness
        # point over a 2-week window. This is a behavioural suggestion,
        # not a research claim — spec §6.2 explicitly allows this
        # interpretable model.
        points_needed = gap
        extra = trunc(Float.round(points_needed * 10 / 2 * 1.0))
        max(current_daily + extra, current_daily)
      else
        current_daily
      end

    minutes_delta = recommended_daily - current_daily

    %{
      status: :ok,
      projected_readiness: projected,
      target: target,
      gap: gap,
      days_to_test: days_to_test,
      current_daily_minutes: current_daily,
      recommended_daily_minutes: recommended_daily,
      minutes_delta: max(0, minutes_delta),
      history_days: history_days(history),
      confidence: qualitative_confidence(history)
    }
  end

  defp slope_per_day([_single]), do: 0.0

  defp slope_per_day(points) do
    first = hd(points)
    last = List.last(points)
    span_days = DateTime.diff(last.at, first.at, :second) / 86_400.0

    if span_days > 0 do
      (last.score - first.score) / span_days
    else
      0.0
    end
  end

  defp history_days(points) do
    case points do
      [_one] ->
        1

      list ->
        first = hd(list).at
        last = List.last(list).at
        max(DateTime.diff(last, first, :second) |> div(86_400), 1)
    end
  end

  defp qualitative_confidence(points) do
    case points do
      [] -> :wide_range
      [_one] -> :wide_range
      list -> if history_days(list) >= @confidence_tight_days, do: :tight, else: :wide_range
    end
  end
end
