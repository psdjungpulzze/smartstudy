defmodule FunSheep.Engagement.Wellbeing do
  @moduledoc """
  Classifies a student's inferred engagement-health signal from real,
  observable activity. Powers the parent dashboard's adaptive framing
  (spec §5.4).

  The classifier returns one of:

    * `:thriving` — streak ≥ 7, accuracy trending up, sessions spread
      across ≥ 3 time-of-day bands
    * `:steady` — consistent sessions and stable accuracy (default)
    * `:under_pressure` — late-night sessions spiking, accuracy dropping
      while minutes are increasing (fatigue signature)
    * `:disengaged` — no sessions in last 5 days, streak broken, upcoming
      test within 14 days
    * `:insufficient_data` — not enough real signal to classify yet

  Downstream the parent UI uses the signal to dampen competitive framing
  (percentiles) and surface supportive-conversation prompts instead. The
  signal is never rendered as a raw number; it is only used to choose
  which copy variant to show (design principle #6).
  """

  import Ecto.Query, warn: false

  alias FunSheep.{Assessments, Gamification, Repo}
  alias FunSheep.Engagement.StudySession

  @recent_window_days 7
  @prior_window_days 14
  @disengaged_days 5
  @thriving_streak 7
  @thriving_window_count 3
  @imminent_test_days 14
  @minutes_increase_factor 1.2
  @accuracy_drop_points 5.0
  @night_spike_multiplier 2

  @type signal ::
          :thriving | :steady | :under_pressure | :disengaged | :insufficient_data

  @type result :: %{
          signal: signal(),
          reasons: [atom()],
          metrics: map()
        }

  @doc """
  Classifies the student's current engagement-health signal.

  Accepts the student's `user_role_id`. Returns a map with the `:signal`
  atom, a list of short `:reasons` atoms (useful for tests / telemetry),
  and the raw `:metrics` the classifier computed (for debugging).
  """
  @spec classify(binary()) :: result()
  def classify(user_role_id) when is_binary(user_role_id) do
    now = DateTime.utc_now()
    recent = sessions_since(user_role_id, DateTime.add(now, -@recent_window_days, :day))
    prior = sessions_between(user_role_id, @recent_window_days, @prior_window_days)

    metrics = %{
      sessions_recent: length(recent),
      sessions_prior: length(prior),
      minutes_recent: total_minutes(recent),
      minutes_prior: total_minutes(prior),
      accuracy_recent: accuracy(recent),
      accuracy_prior: accuracy(prior),
      night_sessions_recent: count_window(recent, "night"),
      night_sessions_prior: count_window(prior, "night"),
      distinct_windows_recent: distinct_windows(recent),
      last_session_at: last_session_at(user_role_id),
      streak: streak_for(user_role_id),
      imminent_test?: imminent_test?(user_role_id, @imminent_test_days)
    }

    do_classify(metrics)
  end

  defp do_classify(%{sessions_recent: 0, sessions_prior: 0} = m),
    do: %{signal: :insufficient_data, reasons: [:no_sessions], metrics: m}

  defp do_classify(metrics) do
    cond do
      disengaged?(metrics) ->
        %{signal: :disengaged, reasons: disengaged_reasons(metrics), metrics: metrics}

      under_pressure?(metrics) ->
        %{signal: :under_pressure, reasons: under_pressure_reasons(metrics), metrics: metrics}

      thriving?(metrics) ->
        %{signal: :thriving, reasons: thriving_reasons(metrics), metrics: metrics}

      true ->
        %{signal: :steady, reasons: [:default], metrics: metrics}
    end
  end

  defp disengaged?(%{last_session_at: last, streak: streak, imminent_test?: imminent?}) do
    imminent? and (last == nil or days_since(last) >= @disengaged_days) and streak == 0
  end

  defp disengaged_reasons(%{last_session_at: nil, imminent_test?: true}),
    do: [:no_recent_sessions, :test_imminent]

  defp disengaged_reasons(%{last_session_at: last, imminent_test?: true})
       when not is_nil(last),
       do: [:long_silence, :test_imminent]

  defp disengaged_reasons(_), do: [:disengaged]

  defp under_pressure?(metrics) do
    late_night_spike?(metrics) and accuracy_drop_while_minutes_up?(metrics)
  end

  defp late_night_spike?(%{night_sessions_recent: r, night_sessions_prior: p}) do
    r > 0 and r >= p * @night_spike_multiplier
  end

  defp accuracy_drop_while_minutes_up?(%{
         accuracy_recent: acc_r,
         accuracy_prior: acc_p,
         minutes_recent: min_r,
         minutes_prior: min_p
       })
       when is_number(acc_r) and is_number(acc_p) and min_p > 0 do
    min_r >= min_p * @minutes_increase_factor and acc_p - acc_r >= @accuracy_drop_points
  end

  defp accuracy_drop_while_minutes_up?(_), do: false

  defp under_pressure_reasons(metrics) do
    reasons = []
    reasons = if late_night_spike?(metrics), do: [:late_night_spike | reasons], else: reasons

    reasons =
      if accuracy_drop_while_minutes_up?(metrics),
        do: [:accuracy_drop_while_minutes_up | reasons],
        else: reasons

    reasons
  end

  defp thriving?(%{
         streak: streak,
         accuracy_recent: acc_r,
         accuracy_prior: acc_p,
         distinct_windows_recent: windows
       }) do
    streak >= @thriving_streak and
      is_number(acc_r) and is_number(acc_p) and
      acc_r >= acc_p and
      windows >= @thriving_window_count
  end

  defp thriving?(_), do: false

  defp thriving_reasons(_), do: [:streak_strong, :accuracy_up, :spread_across_windows]

  defp sessions_since(user_role_id, since) do
    from(s in StudySession,
      where:
        s.user_role_id == ^user_role_id and
          not is_nil(s.completed_at) and
          s.completed_at >= ^since,
      select: %{
        duration_seconds: s.duration_seconds,
        time_window: s.time_window,
        questions_attempted: s.questions_attempted,
        questions_correct: s.questions_correct
      }
    )
    |> Repo.all()
  end

  defp sessions_between(user_role_id, from_days_ago, until_days_ago) do
    now = DateTime.utc_now()
    from_ts = DateTime.add(now, -until_days_ago, :day)
    until_ts = DateTime.add(now, -from_days_ago, :day)

    from(s in StudySession,
      where:
        s.user_role_id == ^user_role_id and
          not is_nil(s.completed_at) and
          s.completed_at >= ^from_ts and
          s.completed_at < ^until_ts,
      select: %{
        duration_seconds: s.duration_seconds,
        time_window: s.time_window,
        questions_attempted: s.questions_attempted,
        questions_correct: s.questions_correct
      }
    )
    |> Repo.all()
  end

  defp last_session_at(user_role_id) do
    from(s in StudySession,
      where: s.user_role_id == ^user_role_id and not is_nil(s.completed_at),
      order_by: [desc: s.completed_at],
      limit: 1,
      select: s.completed_at
    )
    |> Repo.one()
  end

  defp total_minutes(sessions) do
    sessions
    |> Enum.map(&(&1.duration_seconds || 0))
    |> Enum.sum()
    |> div(60)
  end

  defp accuracy([]), do: nil

  defp accuracy(sessions) do
    attempted = sessions |> Enum.map(&(&1.questions_attempted || 0)) |> Enum.sum()
    correct = sessions |> Enum.map(&(&1.questions_correct || 0)) |> Enum.sum()

    if attempted > 0, do: Float.round(correct / attempted * 100, 1), else: nil
  end

  defp count_window(sessions, window) do
    Enum.count(sessions, &(&1.time_window == window))
  end

  defp distinct_windows(sessions) do
    sessions |> Enum.map(& &1.time_window) |> Enum.uniq() |> length()
  end

  defp streak_for(user_role_id) do
    case Gamification.get_or_create_streak(user_role_id) do
      {:ok, %{current_streak: n}} -> n
      _ -> 0
    end
  end

  defp imminent_test?(user_role_id, days) do
    Assessments.list_upcoming_schedules(user_role_id, days) != []
  end

  defp days_since(%DateTime{} = ts) do
    DateTime.diff(DateTime.utc_now(), ts, :second) |> div(86_400)
  end
end
