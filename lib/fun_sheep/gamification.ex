defmodule FunSheep.Gamification do
  @moduledoc """
  The Gamification context.

  Manages streaks (wool growth), XP (Fleece Points), and achievements.
  Provides the engagement layer for the test-prep journey.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo

  alias FunSheep.Gamification.{Streak, XpEvent, Achievement, FpEconomy, ShoutOut}

  ## ── Streaks ──────────────────────────────────────────────────────────────

  @doc "Gets or creates a streak record for a user."
  def get_or_create_streak(user_role_id) do
    case Repo.get_by(Streak, user_role_id: user_role_id) do
      %Streak{} = streak -> {:ok, streak}
      nil -> create_streak(user_role_id)
    end
  end

  defp create_streak(user_role_id) do
    %Streak{}
    |> Streak.changeset(%{user_role_id: user_role_id})
    |> Repo.insert()
  end

  @doc """
  Records study activity for today and updates the streak.
  Returns {:ok, streak} with updated streak info.
  """
  def record_activity(user_role_id) do
    {:ok, streak} = get_or_create_streak(user_role_id)
    today = Date.utc_today()

    cond do
      streak.last_activity_date == today ->
        {:ok, streak}

      streak.last_activity_date == Date.add(today, -1) ->
        new_streak = streak.current_streak + 1
        wool = min(div(new_streak, 3) + 1, 10)

        streak
        |> Streak.changeset(%{
          current_streak: new_streak,
          longest_streak: max(new_streak, streak.longest_streak),
          last_activity_date: today,
          wool_level: wool
        })
        |> Repo.update()

      is_nil(streak.last_activity_date) ->
        streak
        |> Streak.changeset(%{
          current_streak: 1,
          longest_streak: max(1, streak.longest_streak),
          last_activity_date: today,
          wool_level: 1
        })
        |> Repo.update()

      true ->
        frozen? =
          streak.streak_frozen_until &&
            Date.compare(streak.streak_frozen_until, today) != :lt

        if frozen? do
          streak
          |> Streak.changeset(%{
            current_streak: streak.current_streak + 1,
            longest_streak: max(streak.current_streak + 1, streak.longest_streak),
            last_activity_date: today,
            streak_frozen_until: nil
          })
          |> Repo.update()
        else
          streak
          |> Streak.changeset(%{
            current_streak: 1,
            longest_streak: max(1, streak.longest_streak),
            last_activity_date: today,
            wool_level: 1
          })
          |> Repo.update()
        end
    end
  end

  @doc "Checks if streak is active (studied today or yesterday)."
  def streak_active?(%Streak{last_activity_date: nil}), do: false

  def streak_active?(%Streak{last_activity_date: last_date}) do
    today = Date.utc_today()
    diff = Date.diff(today, last_date)
    diff <= 1
  end

  @doc "Returns the sheep mascot state based on user's current situation."
  def sheep_state(user_role_id, opts \\ []) do
    {:ok, streak} = get_or_create_streak(user_role_id)
    upcoming_tests = Keyword.get(opts, :upcoming_tests, [])
    today = Date.utc_today()

    cond do
      # Streak broken — sheared sheep
      streak.last_activity_date && Date.diff(today, streak.last_activity_date) > 1 &&
          streak.current_streak == 0 ->
        :sheared

      # Hasn't studied today and it's been > 24h
      streak.last_activity_date && Date.diff(today, streak.last_activity_date) >= 1 &&
          !streak_active?(streak) ->
        :sleeping

      # Test is close and readiness is low
      has_urgent_test?(upcoming_tests, today) ->
        :worried

      # Long streak — fluffy
      streak.current_streak >= 7 ->
        :fluffy

      # Active and studying
      streak_active?(streak) ->
        :studying

      # Default
      true ->
        :encouraging
    end
  end

  defp has_urgent_test?(tests, today) do
    Enum.any?(tests, fn test ->
      days_until = Date.diff(test.test_date, today)
      days_until <= 5 && days_until >= 0
    end)
  end

  ## ── XP (Fleece Points) ────────────────────────────────────────────────────

  @doc "Awards XP for an action."
  def award_xp(user_role_id, amount, source, opts \\ []) do
    %XpEvent{}
    |> XpEvent.changeset(%{
      user_role_id: user_role_id,
      amount: amount,
      source: source,
      source_id: Keyword.get(opts, :source_id),
      metadata: Keyword.get(opts, :metadata, %{})
    })
    |> Repo.insert()
  end

  @doc "Returns total XP for a user."
  def total_xp(user_role_id) do
    from(x in XpEvent,
      where: x.user_role_id == ^user_role_id,
      select: coalesce(sum(x.amount), 0)
    )
    |> Repo.one()
  end

  @doc "Returns XP earned today."
  def xp_today(user_role_id) do
    today_start =
      Date.utc_today()
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    from(x in XpEvent,
      where: x.user_role_id == ^user_role_id and x.inserted_at >= ^today_start,
      select: coalesce(sum(x.amount), 0)
    )
    |> Repo.one()
  end

  @doc "Returns recent XP events for a user."
  def recent_xp_events(user_role_id, limit \\ 20) do
    from(x in XpEvent,
      where: x.user_role_id == ^user_role_id,
      order_by: [desc: x.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  ## ── Achievements ──────────────────────────────────────────────────────────

  @doc "Awards an achievement if not already earned."
  def award_achievement(user_role_id, achievement_type, metadata \\ %{}) do
    case Repo.get_by(Achievement, user_role_id: user_role_id, achievement_type: achievement_type) do
      %Achievement{} = existing ->
        {:already_earned, existing}

      nil ->
        result =
          %Achievement{}
          |> Achievement.changeset(%{
            user_role_id: user_role_id,
            achievement_type: achievement_type,
            earned_at: DateTime.utc_now(),
            metadata: metadata
          })
          |> Repo.insert()

        case result do
          {:ok, _achievement} -> fan_out_achievement(user_role_id, achievement_type)
          _ -> :ok
        end

        result
    end
  end

  defp fan_out_achievement(user_role_id, achievement_type) do
    follower_ids =
      from(f in FunSheep.Social.Follow,
        where: f.following_id == ^user_role_id,
        select: f.follower_id
      )
      |> Repo.all()

    msg = {:friend_achievement, user_role_id, achievement_type}

    Enum.each(follower_ids, fn fid ->
      Phoenix.PubSub.broadcast(FunSheep.PubSub, "social:feed:#{fid}", msg)
    end)
  end

  @doc "Lists all achievements for a user."
  def list_achievements(user_role_id) do
    from(a in Achievement,
      where: a.user_role_id == ^user_role_id,
      order_by: [desc: a.earned_at]
    )
    |> Repo.all()
  end

  @doc "Returns the count of achievements for a user."
  def achievement_count(user_role_id) do
    from(a in Achievement,
      where: a.user_role_id == ^user_role_id,
      select: count(a.id)
    )
    |> Repo.one()
  end

  @doc "Checks streak milestones and awards achievements."
  def check_streak_achievements(user_role_id) do
    {:ok, streak} = get_or_create_streak(user_role_id)

    milestones = [
      {3, "streak_3"},
      {7, "streak_7"},
      {14, "streak_14"},
      {30, "streak_30"},
      {100, "streak_100"}
    ]

    for {threshold, type} <- milestones,
        streak.current_streak >= threshold do
      award_achievement(user_role_id, type, %{streak: streak.current_streak})
    end
  end

  ## ── Dashboard Summary ─────────────────────────────────────────────────────

  @doc "Returns a summary of gamification stats for the dashboard."
  def dashboard_summary(user_role_id) do
    case get_or_create_streak(user_role_id) do
      {:ok, streak} ->
        %{
          streak: streak,
          total_xp: total_xp(user_role_id),
          xp_today: xp_today(user_role_id),
          achievement_count: achievement_count(user_role_id),
          sheep_state: sheep_state(user_role_id)
        }

      {:error, _changeset} ->
        # user_role doesn't exist (stale session) — return zeroed defaults
        %{
          streak: %{current_streak: 0, longest_streak: 0, wool_level: 0},
          total_xp: 0,
          xp_today: 0,
          achievement_count: 0,
          sheep_state: :sleepy
        }
    end
  end

  ## ── Streak Detail Summary ────────────────────────────────────────────────

  @doc """
  Returns a rich summary of a user's streak for the streak detail modal.

  Includes the 30-day activity heatmap (derived from `xp_events` — any
  FP-earning activity counts as a study day), today/yesterday status,
  next milestone, longest streak, and wool level.
  """
  def streak_summary(user_role_id) do
    with {:ok, _} <- Ecto.UUID.cast(user_role_id),
         {:ok, streak} <- get_or_create_streak(user_role_id) do
      streak_summary_from(streak, user_role_id)
    else
      _ -> empty_streak_summary()
    end
  end

  defp streak_summary_from(streak, user_role_id) do
    today = Date.utc_today()
    active_dates = activity_dates(user_role_id, 30)
    active_set = MapSet.new(active_dates)

    heatmap =
      for offset <- 29..0//-1 do
        d = Date.add(today, -offset)
        %{date: d, active: MapSet.member?(active_set, d)}
      end

    studied_today? = MapSet.member?(active_set, today)
    studied_yesterday? = MapSet.member?(active_set, Date.add(today, -1))

    status =
      cond do
        studied_today? -> :safe
        studied_yesterday? and streak.current_streak > 0 -> :at_risk
        streak.current_streak > 0 -> :broken_today
        true -> :no_streak
      end

    %{
      current_streak: streak.current_streak,
      longest_streak: streak.longest_streak,
      wool_level: streak.wool_level,
      last_activity_date: streak.last_activity_date,
      streak_frozen_until: streak.streak_frozen_until,
      status: status,
      studied_today: studied_today?,
      next_milestone: FpEconomy.next_streak_milestone(streak.current_streak),
      milestones_hit: Enum.count(FpEconomy.streak_milestones(), &(&1 <= streak.current_streak)),
      milestones_total: length(FpEconomy.streak_milestones()),
      heatmap: heatmap
    }
  end

  defp empty_streak_summary do
    today = Date.utc_today()

    heatmap =
      for offset <- 29..0//-1 do
        %{date: Date.add(today, -offset), active: false}
      end

    %{
      current_streak: 0,
      longest_streak: 0,
      wool_level: 0,
      last_activity_date: nil,
      streak_frozen_until: nil,
      status: :no_streak,
      studied_today: false,
      next_milestone: FpEconomy.next_streak_milestone(0),
      milestones_hit: 0,
      milestones_total: length(FpEconomy.streak_milestones()),
      heatmap: heatmap
    }
  end

  ## ── FP Detail Summary ────────────────────────────────────────────────────

  @doc """
  Returns a rich summary of a user's FP for the FP detail modal.

  Includes total, this-week per-day chart data, breakdown by source,
  recent events, current level, and FP to next level. All amounts derive
  from real `xp_events` data — no fabricated values.
  """
  def fp_summary(user_role_id) do
    case Ecto.UUID.cast(user_role_id) do
      {:ok, _} ->
        total = total_xp(user_role_id)
        today = Date.utc_today()
        week_chart = daily_xp(user_role_id, 7)
        week_total = Enum.reduce(week_chart, 0, &(&1.amount + &2))

        %{
          total_xp: total,
          xp_today: xp_today(user_role_id),
          xp_this_week: week_total,
          week_chart: week_chart,
          source_breakdown: source_breakdown(user_role_id),
          recent_events: recent_xp_events(user_role_id, 5),
          level: FpEconomy.level_for_xp(total),
          earn_more: FpEconomy.earn_more_rules(),
          today: today
        }

      :error ->
        empty_fp_summary()
    end
  end

  defp empty_fp_summary do
    today = Date.utc_today()

    week_chart =
      for offset <- 6..0//-1 do
        %{date: Date.add(today, -offset), amount: 0}
      end

    %{
      total_xp: 0,
      xp_today: 0,
      xp_this_week: 0,
      week_chart: week_chart,
      source_breakdown: [],
      recent_events: [],
      level: FpEconomy.level_for_xp(0),
      earn_more: FpEconomy.earn_more_rules(),
      today: today
    }
  end

  @doc """
  Returns a list of `%{date: Date.t(), amount: integer()}` for the most
  recent `n` days (oldest first), filling missing days with zero.
  """
  def daily_xp(user_role_id, days) when is_integer(days) and days > 0 do
    today = Date.utc_today()
    window_start = Date.add(today, -(days - 1))

    window_start_dt = DateTime.new!(window_start, ~T[00:00:00], "Etc/UTC")

    rows =
      from(x in XpEvent,
        where: x.user_role_id == ^user_role_id and x.inserted_at >= ^window_start_dt,
        group_by: fragment("date_trunc('day', ?)", x.inserted_at),
        select: {fragment("date_trunc('day', ?)::date", x.inserted_at), sum(x.amount)}
      )
      |> Repo.all()
      |> Map.new(fn {date, amount} -> {date, amount || 0} end)

    for offset <- (days - 1)..0//-1 do
      d = Date.add(today, -offset)
      %{date: d, amount: Map.get(rows, d, 0)}
    end
  end

  @doc """
  Returns FP grouped by source for a user, sorted by total descending.
  Each entry: `%{source: "practice", amount: 250, count: 25}`.
  """
  def source_breakdown(user_role_id) do
    from(x in XpEvent,
      where: x.user_role_id == ^user_role_id,
      group_by: x.source,
      select: %{source: x.source, amount: coalesce(sum(x.amount), 0), count: count(x.id)},
      order_by: [desc: coalesce(sum(x.amount), 0)]
    )
    |> Repo.all()
  end

  defp activity_dates(user_role_id, days) do
    today = Date.utc_today()
    window_start = Date.add(today, -(days - 1))
    window_start_dt = DateTime.new!(window_start, ~T[00:00:00], "Etc/UTC")

    from(x in XpEvent,
      where: x.user_role_id == ^user_role_id and x.inserted_at >= ^window_start_dt,
      distinct: true,
      select: fragment("date_trunc('day', ?)::date", x.inserted_at)
    )
    |> Repo.all()
  end

  ## ── Shout Outs ───────────────────────────────────────────────────────────

  @shout_out_categories ~w(most_xp most_tests_taken most_textbooks_uploaded most_tests_created longest_streak)a

  @doc """
  Returns the current week's shout out winners.

  Looks up shout_outs where `period == period` and `period_start` equals the
  Monday of the current week. Returns a list of `ShoutOut` structs with the
  `user_role` preloaded.
  """
  def get_current_shout_outs(period \\ "weekly") do
    week_start = current_week_start()

    from(so in ShoutOut,
      where: so.period == ^period and so.period_start == ^week_start,
      preload: [:user_role],
      order_by: so.category
    )
    |> Repo.all()
  end

  @doc """
  Computes shout out winners for the given period and stores them.

  Called by `ComputeShoutOutsWorker` on Sunday night. Existing rows for the
  same `(category, period, period_start)` are NOT deleted first — if you need
  to recompute, delete old rows manually or via a migration.

  Returns `{:ok, count}` where `count` is the number of new rows inserted.
  """
  def compute_and_store_shout_outs(period_start, period_end) do
    results =
      Enum.flat_map(@shout_out_categories, fn category ->
        case compute_winner(category, period_start, period_end) do
          nil ->
            []

          {user_role_id, value} ->
            [
              %{
                category: to_string(category),
                period: "weekly",
                period_start: period_start,
                period_end: period_end,
                metric_value: value,
                user_role_id: user_role_id
              }
            ]
        end
      end)

    rows =
      Enum.map(results, fn attrs ->
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        Map.merge(attrs, %{id: Ecto.UUID.generate(), inserted_at: now})
      end)

    {count, _} = Repo.insert_all(ShoutOut, rows)
    {:ok, count}
  end

  defp current_week_start do
    today = Date.utc_today()

    case Date.day_of_week(today, :monday) do
      1 -> today
      n -> Date.add(today, -(n - 1))
    end
  end

  defp compute_winner(:most_xp, period_start, period_end) do
    start_dt = DateTime.new!(period_start, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(period_end, ~T[00:00:00], "Etc/UTC")

    from(x in XpEvent,
      where: x.inserted_at >= ^start_dt and x.inserted_at < ^end_dt,
      group_by: x.user_role_id,
      select: {x.user_role_id, sum(x.amount)},
      order_by: [desc: sum(x.amount)],
      limit: 1
    )
    |> Repo.one()
  end

  defp compute_winner(:most_tests_taken, period_start, period_end) do
    start_dt = DateTime.new!(period_start, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(period_end, ~T[00:00:00], "Etc/UTC")

    from(qa in FunSheep.Questions.QuestionAttempt,
      where: qa.inserted_at >= ^start_dt and qa.inserted_at < ^end_dt,
      group_by: qa.user_role_id,
      select: {qa.user_role_id, count(qa.id)},
      order_by: [desc: count(qa.id)],
      limit: 1
    )
    |> Repo.one()
  end

  defp compute_winner(:most_textbooks_uploaded, period_start, period_end) do
    start_dt = DateTime.new!(period_start, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(period_end, ~T[00:00:00], "Etc/UTC")

    from(m in FunSheep.Content.UploadedMaterial,
      where:
        m.inserted_at >= ^start_dt and m.inserted_at < ^end_dt and m.ocr_status == :completed,
      group_by: m.user_role_id,
      select: {m.user_role_id, count(m.id)},
      order_by: [desc: count(m.id)],
      limit: 1
    )
    |> Repo.one()
  end

  defp compute_winner(:most_tests_created, period_start, period_end) do
    start_dt = DateTime.new!(period_start, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(period_end, ~T[00:00:00], "Etc/UTC")

    from(ts in FunSheep.Assessments.TestSchedule,
      where: ts.inserted_at >= ^start_dt and ts.inserted_at < ^end_dt,
      group_by: ts.user_role_id,
      select: {ts.user_role_id, count(ts.id)},
      order_by: [desc: count(ts.id)],
      limit: 1
    )
    |> Repo.one()
  end

  defp compute_winner(:longest_streak, _period_start, _period_end) do
    from(s in Streak,
      order_by: [desc: s.current_streak],
      select: {s.user_role_id, s.current_streak},
      limit: 1
    )
    |> Repo.one()
  end

  defp compute_winner(_, _, _), do: nil

  ## ── Leaderboard (Flock) ──────────────────────────────────────────────────

  @grade_order ~w(K 1 2 3 4 5 6 7 8 9 10 11 12 College)

  @doc """
  Builds the user's "flock" — a leaderboard of peers ranked by weekly XP,
  selected by affinity: same school > same course > same subject > ±2 grade > same gender.
  Returns a list of maps with user info, weekly XP, streak, and affinity tags.
  """
  def build_flock(user_role_id, opts \\ []) do
    alias FunSheep.Accounts.UserRole
    alias FunSheep.Courses.Course

    max_size = Keyword.get(opts, :max_size, 30)
    window_days = Keyword.get(opts, :window_days, 7)

    # 1. Load current user's profile
    me = Repo.get!(UserRole, user_role_id)
    my_courses = Repo.all(from(c in Course, where: c.created_by_id == ^user_role_id, select: c))
    my_course_ids = Enum.map(my_courses, & &1.id)
    my_subjects = my_courses |> Enum.map(& &1.subject) |> Enum.uniq()

    # 2. Load all students with weekly XP and streak
    window_start =
      Date.utc_today()
      |> Date.add(-window_days)
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    students =
      from(ur in UserRole,
        where: ur.role == :student and ur.id != ^user_role_id,
        left_join: xp in XpEvent,
        on: xp.user_role_id == ur.id and xp.inserted_at >= ^window_start,
        left_join: s in Streak,
        on: s.user_role_id == ur.id,
        group_by: [
          ur.id,
          ur.display_name,
          ur.school_id,
          ur.grade,
          ur.gender,
          s.current_streak,
          s.wool_level
        ],
        select: %{
          id: ur.id,
          display_name: ur.display_name,
          school_id: ur.school_id,
          grade: ur.grade,
          gender: ur.gender,
          weekly_xp: coalesce(sum(xp.amount), 0),
          streak: coalesce(s.current_streak, 0),
          wool_level: coalesce(s.wool_level, 0)
        }
      )
      |> Repo.all()

    # 3. Load other students' course IDs and subjects for affinity
    other_ids = Enum.map(students, & &1.id)

    courses_by_user =
      if other_ids != [] do
        from(c in Course,
          where: c.created_by_id in ^other_ids,
          select: {c.created_by_id, c.id, c.subject}
        )
        |> Repo.all()
        |> Enum.group_by(&elem(&1, 0), fn {_, cid, subj} -> {cid, subj} end)
      else
        %{}
      end

    # 4. Score each student by affinity
    scored =
      Enum.map(students, fn student ->
        their_courses = Map.get(courses_by_user, student.id, [])
        their_course_ids = Enum.map(their_courses, &elem(&1, 0))
        their_subjects = their_courses |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

        {affinity, tags} =
          compute_affinity(
            me,
            student,
            my_course_ids,
            their_course_ids,
            my_subjects,
            their_subjects
          )

        Map.merge(student, %{affinity: affinity, tags: tags})
      end)
      |> Enum.filter(fn s -> s.affinity > 0 end)
      |> Enum.sort_by(fn s -> {-s.affinity, -s.weekly_xp} end)
      |> Enum.take(max_size)

    # 5. Build final ranked list (re-sort by weekly XP for display)
    peers =
      scored
      |> Enum.sort_by(fn s -> -s.weekly_xp end)
      |> Enum.with_index(1)
      |> Enum.map(fn {s, rank} -> Map.put(s, :rank, rank) end)

    # 6. Insert current user into the ranking
    my_weekly_xp = weekly_xp(user_role_id, window_start)
    {:ok, my_streak} = get_or_create_streak(user_role_id)

    me_entry = %{
      id: user_role_id,
      display_name: me.display_name,
      weekly_xp: my_weekly_xp,
      streak: my_streak.current_streak,
      wool_level: my_streak.wool_level,
      tags: [:you],
      is_me: true
    }

    # Find where current user fits
    {above, below} = Enum.split_while(peers, fn p -> p.weekly_xp > my_weekly_xp end)
    my_rank = length(above) + 1
    me_entry = Map.put(me_entry, :rank, my_rank)

    # Re-rank below users
    below = Enum.map(below, fn p -> Map.update!(p, :rank, &(&1 + 1)) end)

    flock = above ++ [me_entry] ++ below
    {flock, my_rank, length(flock)}
  end

  defp weekly_xp(user_role_id, window_start) do
    from(x in XpEvent,
      where: x.user_role_id == ^user_role_id and x.inserted_at >= ^window_start,
      select: coalesce(sum(x.amount), 0)
    )
    |> Repo.one()
  end

  defp compute_affinity(me, them, my_course_ids, their_course_ids, my_subjects, their_subjects) do
    tags = []
    score = 0

    # Same school (50 pts)
    {score, tags} =
      if me.school_id && me.school_id == them.school_id do
        {score + 50, [:school | tags]}
      else
        {score, tags}
      end

    # Shared course (30 pts)
    shared_courses = MapSet.intersection(MapSet.new(my_course_ids), MapSet.new(their_course_ids))

    {score, tags} =
      if MapSet.size(shared_courses) > 0 do
        {score + 30, [:course | tags]}
      else
        {score, tags}
      end

    # Same subject (20 pts)
    shared_subjects = MapSet.intersection(MapSet.new(my_subjects), MapSet.new(their_subjects))

    {score, tags} =
      if MapSet.size(shared_subjects) > 0 do
        {score + 20, [:subject | tags]}
      else
        {score, tags}
      end

    # Nearby grade ±2 (10 pts)
    {score, tags} =
      if nearby_grade?(me.grade, them.grade) do
        {score + 10, [:grade | tags]}
      else
        {score, tags}
      end

    # Same gender (5 pts)
    {score, tags} =
      if me.gender && me.gender == them.gender do
        {score + 5, [:gender | tags]}
      else
        {score, tags}
      end

    {score, Enum.reverse(tags)}
  end

  defp nearby_grade?(nil, _), do: false
  defp nearby_grade?(_, nil), do: false

  defp nearby_grade?(my_grade, their_grade) do
    my_idx = Enum.find_index(@grade_order, &(&1 == my_grade))
    their_idx = Enum.find_index(@grade_order, &(&1 == their_grade))

    if my_idx && their_idx do
      abs(my_idx - their_idx) <= 2
    else
      false
    end
  end
end
