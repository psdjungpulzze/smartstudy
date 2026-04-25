defmodule FunSheep.Social do
  @moduledoc """
  The Social context.

  Manages peer social graph: follow/unfollow, blocks, school discovery,
  and follow-state enrichment of the Flock leaderboard.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo

  alias FunSheep.Social.{Follow, Block, Invite, CourseShare, CourseShareRecipient}
  alias FunSheep.Accounts.UserRole
  alias FunSheep.Gamification
  alias FunSheep.Gamification.{XpEvent, Streak}

  ## ── Follow ───────────────────────────────────────────────────────────────

  @doc """
  Creates a follow relationship from follower to following.

  Returns `{:ok, follow}` or `{:error, changeset}`.
  Idempotent: if the relationship already exists, returns the existing record.
  """
  def follow(follower_id, following_id, source \\ "manual") do
    if blocked?(follower_id, following_id) do
      {:error, :blocked}
    else
      case Repo.get_by(Follow, follower_id: follower_id, following_id: following_id) do
        %Follow{} = existing ->
          {:ok, existing}

        nil ->
          %Follow{}
          |> Follow.changeset(%{
            follower_id: follower_id,
            following_id: following_id,
            source: source,
            status: "active"
          })
          |> Repo.insert()
          |> tap_award_first_follow_badges(follower_id, following_id)
      end
    end
  end

  @doc "Removes a follow relationship. Returns :ok whether or not it existed."
  def unfollow(follower_id, following_id) do
    Repo.delete_all(
      from(f in Follow,
        where: f.follower_id == ^follower_id and f.following_id == ^following_id
      )
    )

    :ok
  end

  @doc "Mutes a followed user (still following, but suppressed in feed)."
  def mute(follower_id, following_id) do
    case Repo.get_by(Follow, follower_id: follower_id, following_id: following_id) do
      %Follow{} = f ->
        f |> Follow.status_changeset(%{status: "muted"}) |> Repo.update()

      nil ->
        follow(follower_id, following_id, "manual")
        |> case do
          {:ok, f} -> f |> Follow.status_changeset(%{status: "muted"}) |> Repo.update()
          err -> err
        end
    end
  end

  @doc """
  Blocks a user. Removes any existing follows in both directions.
  Returns `{:ok, block}` or `{:error, changeset}`.
  """
  def block(blocker_id, blocked_id) do
    Repo.delete_all(
      from(f in Follow,
        where:
          (f.follower_id == ^blocker_id and f.following_id == ^blocked_id) or
            (f.follower_id == ^blocked_id and f.following_id == ^blocker_id)
      )
    )

    case Repo.get_by(Block, blocker_id: blocker_id, blocked_id: blocked_id) do
      %Block{} = existing -> {:ok, existing}
      nil -> %Block{} |> Block.changeset(%{blocker_id: blocker_id, blocked_id: blocked_id}) |> Repo.insert()
    end
  end

  @doc "Removes a block. Returns :ok."
  def unblock(blocker_id, blocked_id) do
    Repo.delete_all(
      from(b in Block,
        where: b.blocker_id == ^blocker_id and b.blocked_id == ^blocked_id
      )
    )

    :ok
  end

  ## ── Queries ──────────────────────────────────────────────────────────────

  @doc "Returns true if `follower_id` follows `following_id`."
  def following?(follower_id, following_id) do
    Repo.exists?(
      from(f in Follow,
        where: f.follower_id == ^follower_id and f.following_id == ^following_id
      )
    )
  end

  @doc "Returns true if either party has blocked the other."
  def blocked?(user_a_id, user_b_id) do
    Repo.exists?(
      from(b in Block,
        where:
          (b.blocker_id == ^user_a_id and b.blocked_id == ^user_b_id) or
            (b.blocker_id == ^user_b_id and b.blocked_id == ^user_a_id)
      )
    )
  end

  @doc "Returns list of user_role_ids that `user_id` follows (active + muted)."
  def following_ids(user_id) do
    Repo.all(
      from(f in Follow,
        where: f.follower_id == ^user_id and f.status != "blocked",
        select: f.following_id
      )
    )
  end

  @doc "Returns list of user_role_ids that follow `user_id`."
  def follower_ids(user_id) do
    Repo.all(
      from(f in Follow,
        where: f.following_id == ^user_id and f.status != "blocked",
        select: f.follower_id
      )
    )
  end

  @doc """
  Returns all user_role_ids that are blocked by or have blocked `user_id`.
  Used to exclude blocked users from all social queries.
  """
  def blocked_user_ids(user_id) do
    blockers =
      Repo.all(from(b in Block, where: b.blocked_id == ^user_id, select: b.blocker_id))

    blocking =
      Repo.all(from(b in Block, where: b.blocker_id == ^user_id, select: b.blocked_id))

    Enum.uniq(blockers ++ blocking)
  end

  @doc """
  Returns the follow relationship state between viewer and subject.

  - `:mutual` — both follow each other
  - `:following` — viewer follows subject (but not vice versa)
  - `:followed_by` — subject follows viewer (but not vice versa)
  - `:none` — no relationship
  - `:blocked` — either party has blocked the other
  """
  def follow_state(viewer_id, subject_id) do
    if viewer_id == subject_id do
      :self
    else
      blocked = Repo.exists?(
        from(b in Block,
          where:
            (b.blocker_id == ^viewer_id and b.blocked_id == ^subject_id) or
              (b.blocker_id == ^subject_id and b.blocked_id == ^viewer_id)
        )
      )

      if blocked do
        :blocked
      else
        viewer_follows = Repo.exists?(
          from(f in Follow,
            where: f.follower_id == ^viewer_id and f.following_id == ^subject_id
          )
        )

        subject_follows = Repo.exists?(
          from(f in Follow,
            where: f.follower_id == ^subject_id and f.following_id == ^viewer_id
          )
        )

        cond do
          viewer_follows and subject_follows -> :mutual
          viewer_follows -> :following
          subject_follows -> :followed_by
          true -> :not_following
        end
      end
    end
  end

  @doc "Returns true if both users follow each other."
  def mutual?(user_a_id, user_b_id) do
    follow_state(user_a_id, user_b_id) == :mutual
  end

  @doc "Total number of accounts `user_id` follows."
  def following_count(user_id) do
    Repo.one(
      from(f in Follow,
        where: f.follower_id == ^user_id and f.status != "blocked",
        select: count(f.id)
      )
    )
  end

  @doc "Total number of accounts following `user_id`."
  def follower_count(user_id) do
    Repo.one(
      from(f in Follow,
        where: f.following_id == ^user_id and f.status != "blocked",
        select: count(f.id)
      )
    )
  end

  ## ── School peers ─────────────────────────────────────────────────────────

  @doc """
  Returns a list of students at the same school as `user_id`, enriched with
  follow state and shared course count. Excludes blocked users and self.

  Sorted by: mutual → following → shared_courses_count desc → weekly_xp desc.

  Options:
  - `limit` (integer, default 50)
  - `window_days` (integer, default 7) for weekly XP calculation
  """
  def school_peers(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    window_days = Keyword.get(opts, :window_days, 7)

    me = Repo.get!(UserRole, user_id)

    if is_nil(me.school_id) do
      []
    else
      blocked_ids = blocked_user_ids(user_id)
      following = following_ids(user_id)
      follower_set = MapSet.new(follower_ids(user_id))
      following_set = MapSet.new(following)

      window_start =
        Date.utc_today()
        |> Date.add(-window_days)
        |> DateTime.new!(~T[00:00:00], "Etc/UTC")

      exclude_ids = [user_id | blocked_ids]

      peers =
        from(ur in UserRole,
          where:
            ur.school_id == ^me.school_id and
              ur.role == :student and
              ur.id not in ^exclude_ids,
          left_join: s in Streak, on: s.user_role_id == ur.id,
          left_join: xp in XpEvent,
          on: xp.user_role_id == ur.id and xp.inserted_at >= ^window_start,
          group_by: [ur.id, ur.display_name, ur.grade, ur.school_id, s.current_streak, s.wool_level],
          select: %{
            id: ur.id,
            display_name: ur.display_name,
            grade: ur.grade,
            school_id: ur.school_id,
            streak: coalesce(s.current_streak, 0),
            wool_level: coalesce(s.wool_level, 0),
            weekly_xp: coalesce(sum(xp.amount), 0)
          },
          limit: ^(limit * 3)
        )
        |> Repo.all()

      peers
      |> Enum.map(fn p ->
        viewer_follows = MapSet.member?(following_set, p.id)
        subject_follows = MapSet.member?(follower_set, p.id)

        follow_state =
          cond do
            viewer_follows and subject_follows -> :mutual
            viewer_follows -> :following
            subject_follows -> :followed_by
            true -> :none
          end

        Map.put(p, :follow_state, follow_state)
      end)
      |> Enum.sort_by(fn p ->
        follow_order = case p.follow_state do
          :mutual -> 0
          :following -> 1
          :followed_by -> 2
          :none -> 3
        end

        {follow_order, -p.weekly_xp}
      end)
      |> Enum.take(limit)
    end
  end

  @doc "Total number of student peers at the same school as `user_role_id`."
  def school_peer_count(user_role_id) do
    case Repo.get(UserRole, user_role_id) do
      nil ->
        0

      %UserRole{school_id: nil} ->
        0

      %UserRole{school_id: school_id} ->
        Repo.one(
          from(ur in UserRole,
            where:
              ur.school_id == ^school_id and ur.role == :student and ur.id != ^user_role_id,
            select: count(ur.id)
          )
        )
    end
  end

  ## ── Flock with social ────────────────────────────────────────────────────

  @doc """
  Extends the Flock returned by `Gamification.build_flock/2` with follow_state
  per entry. Also applies block filtering.

  The `filter` option controls which entries to return:
  - `:all` (default) — all peers
  - `:following` — only peers viewer follows
  - `:mutual` — only mutual follows (friends)
  """
  def flock_with_social(user_id, opts \\ []) do
    filter = Keyword.get(opts, :filter, :all)

    {flock, my_rank, flock_size} = FunSheep.Gamification.build_flock(user_id, opts)

    blocked_ids = MapSet.new(blocked_user_ids(user_id))
    following_set = MapSet.new(following_ids(user_id))
    follower_set = MapSet.new(follower_ids(user_id))

    enriched =
      flock
      |> Enum.reject(fn p -> MapSet.member?(blocked_ids, p.id) end)
      |> Enum.map(fn p ->
        if Map.get(p, :is_me) do
          Map.put(p, :follow_state, :me)
        else
          viewer_follows = MapSet.member?(following_set, p.id)
          subject_follows = MapSet.member?(follower_set, p.id)

          state =
            cond do
              viewer_follows and subject_follows -> :mutual
              viewer_follows -> :following
              subject_follows -> :followed_by
              true -> :none
            end

          Map.put(p, :follow_state, state)
        end
      end)

    filtered =
      case filter do
        :following ->
          Enum.filter(enriched, fn p ->
            p.follow_state in [:following, :mutual, :me]
          end)

        :mutual ->
          Enum.filter(enriched, fn p ->
            p.follow_state in [:mutual, :me]
          end)

        _ ->
          enriched
      end

    {filtered, my_rank, flock_size}
  end

  ## ── Suggested follows ────────────────────────────────────────────────────

  @doc """
  Returns up to `limit` suggested users for `user_id` to follow, with a reason.

  Reason priority:
  1. Same school (`:school`)
  2. Shared course enrollment (`:course`)
  3. Flock proximity — within 10 rank positions (`:flock`)
  4. Friend-of-friend — someone following a person you follow (`:fof`)

  Excludes: already following, blocked, self.
  """
  def suggested_follows(user_id, limit \\ 6) do
    already_following = MapSet.new(following_ids(user_id))
    blocked = MapSet.new(blocked_user_ids(user_id))
    exclude = MapSet.new([user_id | MapSet.to_list(blocked) ++ MapSet.to_list(already_following)])

    me = Repo.get!(UserRole, user_id)

    school_suggestions =
      if me.school_id do
        Repo.all(
          from(ur in UserRole,
            where:
              ur.school_id == ^me.school_id and
                ur.role == :student and
                ur.id not in ^MapSet.to_list(exclude),
            order_by: [desc: ur.inserted_at],
            limit: 20,
            select: ur
          )
        )
        |> Enum.map(&%{user_role: &1, reason: :school})
      else
        []
      end

    seen = MapSet.new(Enum.map(school_suggestions, & &1.user_role.id))

    fof_ids =
      from(f1 in Follow,
        join: f2 in Follow, on: f2.follower_id == f1.following_id,
        where: f1.follower_id == ^user_id and f2.following_id not in ^MapSet.to_list(exclude),
        where: f2.following_id not in ^MapSet.to_list(seen),
        select: f2.following_id,
        distinct: true,
        limit: 10
      )
      |> Repo.all()

    fof_suggestions =
      if fof_ids != [] do
        Repo.all(from(ur in UserRole, where: ur.id in ^fof_ids, select: ur))
        |> Enum.map(&%{user_role: &1, reason: :fof})
      else
        []
      end

    (school_suggestions ++ fof_suggestions)
    |> Enum.uniq_by(& &1.user_role.id)
    |> Enum.take(limit)
  end

  @doc """
  Searches for students matching `query` within the same school as `user_id`.
  Returns list of %{user_role, follow_state}.
  """
  def search_peers(user_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    me = Repo.get!(UserRole, user_id)
    blocked = blocked_user_ids(user_id)
    following_set = MapSet.new(following_ids(user_id))
    follower_set = MapSet.new(follower_ids(user_id))

    pattern = "%#{String.replace(query, "%", "\\%")}%"

    scope_filter =
      if me.school_id do
        dynamic([ur], ur.school_id == ^me.school_id)
      else
        dynamic([ur], false)
      end

    results =
      from(ur in UserRole,
        where: ^scope_filter,
        where: ur.role == :student,
        where: ur.id != ^user_id,
        where: ur.id not in ^blocked,
        where: ilike(ur.display_name, ^pattern),
        order_by: [asc: ur.display_name],
        limit: ^limit,
        select: ur
      )
      |> Repo.all()

    Enum.map(results, fn ur ->
      viewer_follows = MapSet.member?(following_set, ur.id)
      subject_follows = MapSet.member?(follower_set, ur.id)

      state =
        cond do
          viewer_follows and subject_follows -> :mutual
          viewer_follows -> :following
          subject_follows -> :followed_by
          true -> :none
        end

      %{user_role: ur, follow_state: state}
    end)
  end

  @doc """
  Returns true if the viewer has access to the subject's profile.

  Access is granted when:
  - viewer == subject
  - both are at the same school
  - viewer follows subject
  - they share a course enrollment
  """
  def can_view_profile?(viewer_id, subject_id) when viewer_id == subject_id, do: true

  def can_view_profile?(viewer_id, subject_id) do
    blocked = Repo.exists?(
      from(b in Block,
        where:
          (b.blocker_id == ^viewer_id and b.blocked_id == ^subject_id) or
            (b.blocker_id == ^subject_id and b.blocked_id == ^viewer_id)
      )
    )

    if blocked do
      false
    else
      viewer = Repo.get(UserRole, viewer_id)
      subject = Repo.get(UserRole, subject_id)

      cond do
        is_nil(viewer) or is_nil(subject) -> false
        viewer.school_id && viewer.school_id == subject.school_id -> true
        Repo.exists?(from(f in Follow, where: f.follower_id == ^viewer_id and f.following_id == ^subject_id)) -> true
        true -> false
      end
    end
  end

  ## ── Invites ──────────────────────────────────────────────────────────────

  @doc """
  Creates a peer invite.

  Options:
  - `invitee_user_role_id` — invite an existing user (in-app notification)
  - `invitee_email` — invite a non-user (generates a token, email must be sent separately)
  - `context` — "general" | "course" | "test" (default "general")
  - `context_id` — UUID of the course or test schedule
  - `message` — optional personal note (max 200 chars)

  Returns `{:ok, invite}` or `{:error, changeset}`.
  """
  def create_invite(inviter_id, opts \\ []) do
    invitee_user_role_id = Keyword.get(opts, :invitee_user_role_id)
    invitee_email = Keyword.get(opts, :invitee_email)
    context = Keyword.get(opts, :context, "general")
    context_id = Keyword.get(opts, :context_id)
    message = opts |> Keyword.get(:message) |> truncate(200)

    attrs =
      %{
        inviter_id: inviter_id,
        invitee_user_role_id: invitee_user_role_id,
        invitee_email: invitee_email,
        context: context,
        context_id: context_id,
        message: message,
        status: "pending"
      }

    attrs =
      if is_nil(invitee_user_role_id) do
        token = generate_invite_token()
        expires_at = DateTime.utc_now() |> DateTime.add(14 * 24 * 60 * 60, :second) |> DateTime.truncate(:second)
        Map.merge(attrs, %{invite_token: token, invite_token_expires_at: expires_at})
      else
        attrs
      end

    %Invite{} |> Invite.changeset(attrs) |> Repo.insert()
  end

  @doc """
  Accepts an invite by token (for non-users who just signed up).

  Creates a follow from invitee to inviter. Returns `{:ok, invite}` or
  `{:error, reason}`.
  """
  def accept_invite(token) when is_binary(token) do
    case Repo.get_by(Invite, invite_token: token, status: "pending") do
      nil ->
        {:error, :not_found}

      %Invite{invite_token_expires_at: exp} = invite ->
        if DateTime.compare(exp, DateTime.utc_now()) == :lt do
          Repo.update(Invite.status_changeset(invite, "expired"))
          {:error, :expired}
        else
          {:ok, accepted} = Repo.update(Invite.accept_changeset(invite))
          follow(accepted.invitee_user_role_id, accepted.inviter_id, "invite_accepted")
          check_flock_milestones(accepted.inviter_id)
          {:ok, accepted}
        end
    end
  end

  def accept_invite(_), do: {:error, :invalid_token}

  @doc "Declines an invite by token."
  def decline_invite(token) when is_binary(token) do
    case Repo.get_by(Invite, invite_token: token, status: "pending") do
      nil -> {:error, :not_found}
      invite -> Repo.update(Invite.status_changeset(invite, "declined"))
    end
  end

  @doc "Lists invites sent by `user_id`."
  def list_sent_invites(user_id) do
    from(i in Invite,
      where: i.inviter_id == ^user_id,
      order_by: [desc: i.inserted_at],
      preload: [:invitee_user_role]
    )
    |> Repo.all()
  end

  @doc "Lists invites received by `user_id`."
  def list_received_invites(user_id) do
    from(i in Invite,
      where: i.invitee_user_role_id == ^user_id and i.status == "pending",
      order_by: [desc: i.inserted_at],
      preload: [:inviter]
    )
    |> Repo.all()
  end

  @doc "Returns invite counts by status for a user."
  def invite_count_by_status(user_id) do
    from(i in Invite,
      where: i.inviter_id == ^user_id,
      group_by: i.status,
      select: {i.status, count(i.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  ## ── Flock Tree (Invitation Chain) ────────────────────────────────────────

  @doc """
  Returns the invitation lineage for `user_role_id`.

  Returns a map:
  - `:invited_by` — the UserRole that sent the accepted invite to this user, or `nil`
  - `:invited_users` — list of UserRoles this user has invited (accepted invites)
  - `:total_invited` — total accepted invite count (recursive tree size, capped at 100)
  """
  def flock_tree(user_role_id) do
    invited_by =
      case Repo.one(
             from(i in Invite,
               where: i.invitee_user_role_id == ^user_role_id and i.status == "accepted",
               join: inviter in assoc(i, :inviter),
               select: inviter,
               limit: 1
             )
           ) do
        nil -> nil
        inviter -> inviter
      end

    invited_users =
      from(i in Invite,
        where: i.inviter_id == ^user_role_id and i.status == "accepted",
        join: invitee in assoc(i, :invitee_user_role),
        select: invitee,
        order_by: [asc: i.inserted_at]
      )
      |> Repo.all()

    total_invited = count_subtree(user_role_id, 0, 100)

    %{
      invited_by: invited_by,
      invited_users: invited_users,
      total_invited: total_invited
    }
  end

  defp count_subtree(_user_id, acc, max) when acc >= max, do: acc

  defp count_subtree(user_id, acc, max) do
    direct =
      from(i in Invite,
        where: i.inviter_id == ^user_id and i.status == "accepted",
        select: i.invitee_user_role_id
      )
      |> Repo.all()

    Enum.reduce(direct, acc + length(direct), fn child_id, a ->
      count_subtree(child_id, a, max)
    end)
  end

  ## ── Study Buddy XP ───────────────────────────────────────────────────────

  @study_buddy_window_hours 24
  @study_buddy_xp 5

  @doc """
  Awards a Study Buddy XP bonus when mutual followers study the same course
  within `@study_buddy_window_hours` of each other.

  Call this after recording a practice attempt. Idempotent: the XP is only
  awarded once per (user_pair, course, day) by checking existing XpEvents.
  """
  def maybe_award_study_buddy_xp(user_role_id, course_id) do
    mutual = mutual_follower_ids(user_role_id)

    if Enum.empty?(mutual) do
      :noop
    else
      window_start =
        DateTime.utc_now()
        |> DateTime.add(-@study_buddy_window_hours * 3600, :second)
        |> DateTime.truncate(:second)

      active_mutual =
        from(x in XpEvent,
          where:
            x.user_role_id in ^mutual and
              x.source == "practice" and
              x.source_id == ^course_id and
              x.inserted_at >= ^window_start,
          select: x.user_role_id,
          distinct: true
        )
        |> Repo.all()

      Enum.each(active_mutual, fn partner_id ->
        award_pair_study_buddy_xp(user_role_id, partner_id, course_id)
      end)
    end
  end

  defp mutual_follower_ids(user_id) do
    following = following_ids(user_id) |> MapSet.new()
    followers = follower_ids(user_id) |> MapSet.new()
    MapSet.intersection(following, followers) |> MapSet.to_list()
  end

  defp award_pair_study_buddy_xp(user_a, user_b, course_id) do
    today = Date.utc_today()

    already_awarded? = fn uid, partner ->
      Repo.exists?(
        from(x in XpEvent,
          where:
            x.user_role_id == ^uid and
              x.source == "study_buddy" and
              x.source_id == ^course_id and
              fragment("(metadata->>'partner_id') = ?", ^partner) and
              fragment("DATE(inserted_at) = ?", ^today)
        )
      )
    end

    unless already_awarded?.(user_a, user_b) do
      Gamification.award_xp(user_a, @study_buddy_xp, "study_buddy",
        source_id: course_id,
        metadata: %{partner_id: user_b}
      )
      tap_award_study_buddy_achievement(user_a)
    end

    unless already_awarded?.(user_b, user_a) do
      Gamification.award_xp(user_b, @study_buddy_xp, "study_buddy",
        source_id: course_id,
        metadata: %{partner_id: user_a}
      )
      tap_award_study_buddy_achievement(user_b)
    end
  end

  defp tap_award_study_buddy_achievement(user_role_id) do
    existing = Gamification.list_achievements(user_role_id)

    unless Enum.any?(existing, &(&1.achievement_type == "study_buddy")) do
      Gamification.award_achievement(user_role_id, "study_buddy")
    end
  end

  ## ── Course Shares ────────────────────────────────────────────────────────

  @doc """
  Shares a course with a list of follower user_role_ids.

  Creates (or increments) a CourseShare record and adds recipients.
  Returns `{:ok, share}` or `{:error, changeset}`.
  """
  def share_course(sharer_id, course_id, recipient_ids, opts \\ []) do
    message = opts |> Keyword.get(:message) |> truncate(200)
    recipient_ids = Enum.reject(recipient_ids, &(&1 == sharer_id))

    Repo.transaction(fn ->
      share =
        case Repo.get_by(CourseShare, sharer_id: sharer_id, course_id: course_id) do
          nil ->
            %CourseShare{}
            |> CourseShare.changeset(%{sharer_id: sharer_id, course_id: course_id, message: message})
            |> Repo.insert!()

          existing ->
            existing
            |> CourseShare.changeset(%{share_count: existing.share_count + 1, message: message})
            |> Repo.update!()
        end

      now = DateTime.truncate(DateTime.utc_now(), :second)

      recipients =
        Enum.map(recipient_ids, fn rid ->
          case Repo.get_by(CourseShareRecipient, share_id: share.id, recipient_id: rid) do
            nil ->
              %CourseShareRecipient{}
              |> CourseShareRecipient.changeset(%{share_id: share.id, recipient_id: rid})
              |> Repo.insert!(on_conflict: :nothing)

            existing -> existing
          end
        end)

      _ = now
      %{share | recipients: recipients}
    end)
  end

  @doc "Marks a share recipient record as seen."
  def mark_share_seen(share_id, recipient_id) do
    case Repo.get_by(CourseShareRecipient, share_id: share_id, recipient_id: recipient_id) do
      nil -> {:error, :not_found}
      r -> Repo.update(CourseShareRecipient.seen_changeset(r))
    end
  end

  @doc "Lists courses shared with `user_id` (unseen first)."
  def list_received_shares(user_id) do
    from(r in CourseShareRecipient,
      where: r.recipient_id == ^user_id,
      join: s in assoc(r, :share),
      join: sharer in assoc(s, :sharer),
      order_by: [asc: r.seen_at, desc: s.inserted_at],
      preload: [share: {s, sharer: sharer}]
    )
    |> Repo.all()
  end

  @doc "Lists courses this user has shared."
  def list_sent_shares(user_id) do
    from(s in CourseShare,
      where: s.sharer_id == ^user_id,
      order_by: [desc: s.inserted_at],
      preload: [:course, :recipients]
    )
    |> Repo.all()
  end

  @doc "Returns the user_role_ids of followers the sharer has already shared this course with."
  def already_shared_with(sharer_id, course_id) do
    case Repo.get_by(CourseShare, sharer_id: sharer_id, course_id: course_id) do
      nil ->
        []

      share ->
        from(r in CourseShareRecipient, where: r.share_id == ^share.id, select: r.recipient_id)
        |> Repo.all()
    end
  end

  @doc """
  Returns the list of mutual followers eligible to receive a course share.
  Excludes users already shared with for this course.
  """
  def shareable_followers(sharer_id, course_id) do
    already = already_shared_with(sharer_id, course_id) |> MapSet.new()
    following = following_ids(sharer_id) |> MapSet.new()
    followers = follower_ids(sharer_id) |> MapSet.new()
    mutual = MapSet.intersection(following, followers)

    eligible =
      mutual
      |> MapSet.difference(already)
      |> MapSet.to_list()

    from(ur in UserRole,
      where: ur.id in ^eligible,
      select: ur
    )
    |> Repo.all()
  end

  defp generate_invite_token do
    :crypto.strong_rand_bytes(10) |> Base.url_encode64(padding: false) |> binary_part(0, 14)
  end

  defp truncate(nil, _), do: nil
  defp truncate(str, max), do: String.slice(str, 0, max)

  ## ── Badge side effects ───────────────────────────────────────────────────

  defp tap_award_first_follow_badges({:ok, _follow} = result, follower_id, following_id) do
    new_following_count = Repo.one(
      from(f in Follow, where: f.follower_id == ^follower_id and f.status != "blocked", select: count(f.id))
    )

    new_follower_count = Repo.one(
      from(f in Follow, where: f.following_id == ^following_id and f.status != "blocked", select: count(f.id))
    )

    if new_following_count == 1 do
      FunSheep.Gamification.award_achievement(follower_id, "first_follow", %{})
    end

    if new_follower_count == 1 do
      FunSheep.Gamification.award_achievement(following_id, "first_follower", %{})
    end

    if new_follower_count == 5 do
      FunSheep.Gamification.award_achievement(following_id, "flock_starter", %{})
    end

    result
  end

  defp tap_award_first_follow_badges(error, _follower_id, _following_id), do: error

  defp check_flock_milestones(inviter_id) do
    total = count_subtree(inviter_id, 0, 100)

    cond do
      total >= 20 -> Gamification.award_achievement(inviter_id, "flock_builder", %{total: total})
      total >= 10 -> Gamification.award_achievement(inviter_id, "lead_shepherd", %{total: total})
      total >= 5 -> Gamification.award_achievement(inviter_id, "shepherd", %{total: total})
      true -> :noop
    end
  end
end
