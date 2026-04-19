defmodule FunSheep.Engagement.StudySessions do
  @moduledoc """
  Context for study session tracking, receipts, and time-gated FP bonuses.

  Manages the lifecycle of study sessions from start to completion,
  calculates XP with time-window multipliers, generates display receipts,
  and provides summaries for students and parents.
  """

  import Ecto.Query, warn: false

  alias FunSheep.Repo
  alias FunSheep.Engagement.StudySession
  alias FunSheep.Gamification

  @xp_per_correct 5
  @xp_session_completion 10
  @all_windows_bonus 25
  @all_windows_threshold 3

  @time_window_multipliers %{
    "morning" => 2.0,
    "afternoon" => 1.5,
    "evening" => 1.0,
    "night" => 1.0
  }

  ## ── Session Lifecycle ────────────────────────────────────────────────────

  @doc """
  Creates a new study session record.

  Auto-sets the current time window. Accepts optional `course_id` and
  `readiness_before` via the opts keyword list.

  ## Parameters

    * `user_role_id` - The student's user role ID
    * `session_type` - One of: review, practice, assessment, quick_test, daily_challenge, just_this
    * `opts` - Keyword list with optional `:course_id` and `:readiness_before`

  ## Examples

      iex> start_session(user_role_id, "practice", course_id: course_id, readiness_before: 0.72)
      {:ok, %StudySession{}}

  """
  def start_session(user_role_id, session_type, opts \\ []) do
    attrs = %{
      user_role_id: user_role_id,
      session_type: session_type,
      time_window: StudySession.current_time_window(),
      course_id: Keyword.get(opts, :course_id),
      readiness_before: Keyword.get(opts, :readiness_before)
    }

    %StudySession{}
    |> StudySession.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Completes a session with final stats, awards XP, and returns a receipt.

  Sets `completed_at`, calculates XP with time-window bonuses, awards XP
  via the Gamification context, and generates a display receipt.

  ## Parameters

    * `session_id` - The session's binary ID
    * `attrs` - Map with `:questions_attempted`, `:questions_correct`,
      `:duration_seconds`, `:topics_covered`, `:readiness_after`

  ## Returns

      {:ok, session, receipt}

  """
  def complete_session(session_id, attrs) do
    session = Repo.get!(StudySession, session_id)

    {base_xp, multiplier, bonus_xp, total_xp} =
      calculate_xp(session, attrs)

    completion_attrs =
      attrs
      |> Map.put(:completed_at, DateTime.utc_now() |> DateTime.truncate(:second))
      |> Map.put(:xp_earned, total_xp)

    with {:ok, session} <-
           session
           |> StudySession.changeset(completion_attrs)
           |> Repo.update(),
         {:ok, _xp_event} <-
           Gamification.award_xp(session.user_role_id, total_xp, "study_session",
             source_id: session.id,
             metadata: %{
               base_xp: base_xp,
               multiplier: multiplier,
               bonus_xp: bonus_xp,
               time_window: session.time_window
             }
           ) do
      session = Repo.preload(session, :course)
      receipt = generate_receipt(session)
      {:ok, session, receipt}
    end
  end

  ## ── XP Calculation ───────────────────────────────────────────────────────

  @doc """
  Calculates XP for a session including time-window multipliers and daily bonuses.

  Base XP = (correct answers * #{@xp_per_correct}) + #{@xp_session_completion} completion bonus.
  Time-window multipliers: morning 2x, afternoon 1.5x, evening 1x, night 1x.
  All-Windows bonus: #{@all_windows_bonus} FP if #{@all_windows_threshold}+ distinct windows today.

  ## Parameters

    * `session` - A `%StudySession{}` struct (needs `user_role_id` and `time_window`)
    * `attrs` - Map with at least `:questions_correct`

  ## Returns

      {base_xp, multiplier, bonus_xp, total_xp}

  """
  def calculate_xp(%StudySession{} = session, attrs) do
    correct = Map.get(attrs, :questions_correct, 0)
    base_xp = correct * @xp_per_correct + @xp_session_completion
    multiplier = Map.get(@time_window_multipliers, session.time_window, 1.0)
    multiplied_xp = trunc(base_xp * multiplier)

    # Check if completing this session earns the all-windows daily bonus
    windows_before = windows_completed_today(session.user_role_id)

    windows_after =
      [session.time_window | windows_before]
      |> Enum.uniq()

    bonus_xp =
      if length(windows_after) >= @all_windows_threshold and
           length(windows_before) < @all_windows_threshold do
        @all_windows_bonus
      else
        0
      end

    total_xp = multiplied_xp + bonus_xp

    {base_xp, multiplier, bonus_xp, total_xp}
  end

  ## ── Queries ──────────────────────────────────────────────────────────────

  @doc """
  Returns all completed sessions for a user today (UTC).
  """
  def sessions_today(user_role_id) do
    today_start = today_start()

    from(s in StudySession,
      where:
        s.user_role_id == ^user_role_id and
          not is_nil(s.completed_at) and
          s.completed_at >= ^today_start,
      order_by: [desc: s.completed_at]
    )
    |> Repo.all()
  end

  @doc """
  Returns distinct time windows the user has completed sessions in today.

  ## Examples

      iex> windows_completed_today(user_role_id)
      ["morning", "afternoon"]

  """
  def windows_completed_today(user_role_id) do
    today_start = today_start()

    from(s in StudySession,
      where:
        s.user_role_id == ^user_role_id and
          not is_nil(s.completed_at) and
          s.completed_at >= ^today_start,
      distinct: true,
      select: s.time_window
    )
    |> Repo.all()
  end

  @doc """
  Returns the number of completed sessions today for a user.
  """
  def session_count_today(user_role_id) do
    today_start = today_start()

    from(s in StudySession,
      where:
        s.user_role_id == ^user_role_id and
          not is_nil(s.completed_at) and
          s.completed_at >= ^today_start,
      select: count(s.id)
    )
    |> Repo.one()
  end

  ## ── Receipts ─────────────────────────────────────────────────────────────

  @doc """
  Generates a display receipt map for a completed session.

  The session must be preloaded with `:course` for the course name.

  ## Returns

      %{
        session_type: "practice",
        course_name: "Algebra",
        questions: "15/20 correct",
        accuracy: 75.0,
        duration: "8 min",
        xp_earned: 45,
        time_window: "morning",
        bonus_applied: "2x Morning Bonus",
        readiness_change: "+3%",
        topics: ["Quadratic Equations", "Factoring"],
        completed_at: ~U[2026-04-18 10:30:00Z]
      }

  """
  def generate_receipt(%StudySession{} = session) do
    accuracy = calculate_accuracy(session.questions_correct, session.questions_attempted)
    multiplier = Map.get(@time_window_multipliers, session.time_window, 1.0)

    %{
      session_type: session.session_type,
      course_name: course_name(session),
      questions: "#{session.questions_correct}/#{session.questions_attempted} correct",
      accuracy: accuracy,
      duration: format_duration(session.duration_seconds),
      xp_earned: session.xp_earned,
      time_window: session.time_window,
      bonus_applied: format_bonus(session.time_window, multiplier),
      readiness_change:
        format_readiness_change(session.readiness_before, session.readiness_after),
      topics: session.topics_covered || [],
      completed_at: session.completed_at
    }
  end

  ## ── History & Summaries ──────────────────────────────────────────────────

  @doc """
  Returns the last `limit` sessions for a user with preloaded course.

  Defaults to 10 sessions.
  """
  def recent_sessions(user_role_id, limit \\ 10) do
    from(s in StudySession,
      where: s.user_role_id == ^user_role_id and not is_nil(s.completed_at),
      order_by: [desc: s.completed_at],
      limit: ^limit,
      preload: [:course]
    )
    |> Repo.all()
  end

  @doc """
  Returns today's summary for a user.

  ## Returns

      %{
        session_count: 3,
        total_questions: 45,
        total_correct: 38,
        total_xp: 120,
        windows_completed: ["morning", "afternoon"],
        windows_remaining: ["evening"],
        all_windows_bonus_earned: false,
        total_duration_minutes: 22
      }

  """
  def daily_summary(user_role_id) do
    sessions = sessions_today(user_role_id)
    windows_completed = sessions |> Enum.map(& &1.time_window) |> Enum.uniq()
    all_windows = ~w(morning afternoon evening night)

    windows_remaining =
      all_windows
      |> Enum.reject(&(&1 in windows_completed))

    total_seconds = sessions |> Enum.map(& &1.duration_seconds) |> Enum.sum()

    %{
      session_count: length(sessions),
      total_questions: sessions |> Enum.map(& &1.questions_attempted) |> Enum.sum(),
      total_correct: sessions |> Enum.map(& &1.questions_correct) |> Enum.sum(),
      total_xp: sessions |> Enum.map(& &1.xp_earned) |> Enum.sum(),
      windows_completed: windows_completed,
      windows_remaining: windows_remaining,
      all_windows_bonus_earned: length(windows_completed) >= @all_windows_threshold,
      total_duration_minutes: div(total_seconds, 60)
    }
  end

  @doc """
  Returns a summary for the parent dashboard.

  Takes a student's `user_role_id` and an optional `days` parameter
  (defaults to 7) for the week-range calculations.

  ## Returns

      %{
        sessions_today: 3,
        total_study_minutes_today: 22,
        sessions_this_week: 15,
        total_study_minutes_week: 95,
        average_accuracy: 82.5,
        most_active_window: "morning",
        streak_count: 7
      }

  """
  def parent_activity_summary(user_role_id, days \\ 7) do
    today_start = today_start()
    week_start = DateTime.add(today_start, -days, :day)

    today_sessions = sessions_today(user_role_id)

    week_sessions =
      from(s in StudySession,
        where:
          s.user_role_id == ^user_role_id and
            not is_nil(s.completed_at) and
            s.completed_at >= ^week_start,
        order_by: [desc: s.completed_at]
      )
      |> Repo.all()

    today_minutes =
      today_sessions
      |> Enum.map(& &1.duration_seconds)
      |> Enum.sum()
      |> div(60)

    week_minutes =
      week_sessions
      |> Enum.map(& &1.duration_seconds)
      |> Enum.sum()
      |> div(60)

    average_accuracy = calculate_week_accuracy(week_sessions)
    most_active = most_active_window(week_sessions)
    streak = get_streak_count(user_role_id)

    %{
      sessions_today: length(today_sessions),
      total_study_minutes_today: today_minutes,
      sessions_this_week: length(week_sessions),
      total_study_minutes_week: week_minutes,
      average_accuracy: average_accuracy,
      most_active_window: most_active,
      streak_count: streak
    }
  end

  ## ── Private Helpers ──────────────────────────────────────────────────────

  defp today_start do
    DateTime.utc_now()
    |> DateTime.to_date()
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  end

  defp calculate_accuracy(_correct, 0), do: 0.0

  defp calculate_accuracy(correct, attempted) do
    Float.round(correct / attempted * 100, 1)
  end

  defp course_name(%StudySession{course: %{name: name}}), do: name
  defp course_name(_), do: nil

  defp format_duration(nil), do: "0 min"
  defp format_duration(seconds) when seconds < 60, do: "#{seconds} sec"
  defp format_duration(seconds), do: "#{div(seconds, 60)} min"

  defp format_bonus(window, multiplier) when multiplier > 1.0 do
    label = String.capitalize(window)
    "#{format_multiplier(multiplier)}x #{label} Bonus"
  end

  defp format_bonus(_window, _multiplier), do: nil

  defp format_multiplier(multiplier) do
    if multiplier == trunc(multiplier) do
      "#{trunc(multiplier)}"
    else
      "#{multiplier}"
    end
  end

  defp format_readiness_change(nil, _after), do: nil
  defp format_readiness_change(_before, nil), do: nil

  defp format_readiness_change(before, after_val) do
    change = Float.round((after_val - before) * 100, 0) |> trunc()

    cond do
      change > 0 -> "+#{change}%"
      change < 0 -> "#{change}%"
      true -> "0%"
    end
  end

  defp calculate_week_accuracy([]), do: 0.0

  defp calculate_week_accuracy(sessions) do
    total_attempted = sessions |> Enum.map(& &1.questions_attempted) |> Enum.sum()
    total_correct = sessions |> Enum.map(& &1.questions_correct) |> Enum.sum()
    calculate_accuracy(total_correct, total_attempted)
  end

  defp most_active_window([]), do: nil

  defp most_active_window(sessions) do
    sessions
    |> Enum.group_by(& &1.time_window)
    |> Enum.max_by(fn {_window, group} -> length(group) end)
    |> elem(0)
  end

  defp get_streak_count(user_role_id) do
    case Gamification.get_or_create_streak(user_role_id) do
      {:ok, streak} -> streak.current_streak
      _ -> 0
    end
  end
end
