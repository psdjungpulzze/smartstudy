defmodule FunSheep.Gamification do
  @moduledoc """
  The Gamification context.

  Manages streaks (wool growth), XP (Fleece Points), and achievements.
  Provides the engagement layer for the test-prep journey.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo

  alias FunSheep.Gamification.{Streak, XpEvent, Achievement}

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
        %Achievement{}
        |> Achievement.changeset(%{
          user_role_id: user_role_id,
          achievement_type: achievement_type,
          earned_at: DateTime.utc_now(),
          metadata: metadata
        })
        |> Repo.insert()
    end
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
