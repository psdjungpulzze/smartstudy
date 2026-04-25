defmodule FunSheep.Social do
  @moduledoc """
  The Social context.

  Manages the asymmetric follow graph, block relationships, and school
  peer discovery between students.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo
  alias FunSheep.Social.{SocialFollow, UserBlock}
  alias FunSheep.Accounts.UserRole

  # ── Follow / Unfollow ──────────────────────────────────────────────────

  @doc """
  Follow a user. Idempotent — safe to call if already following.

  Returns `{:ok, follow}` or `{:error, changeset}`.
  Cannot follow yourself or a blocked user.
  """
  @spec follow(follower_id :: binary, followee_id :: binary) ::
          {:ok, SocialFollow.t()} | {:error, Ecto.Changeset.t()} | {:error, :blocked}
  def follow(follower_id, followee_id) do
    if blocked?(followee_id, follower_id) || blocked?(follower_id, followee_id) do
      {:error, :blocked}
    else
      %SocialFollow{}
      |> SocialFollow.changeset(%{follower_id: follower_id, followee_id: followee_id})
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:follower_id, :followee_id])
    end
  end

  @doc """
  Unfollow a user. No-op if not currently following.
  """
  @spec unfollow(follower_id :: binary, followee_id :: binary) :: :ok
  def unfollow(follower_id, followee_id) do
    from(f in SocialFollow,
      where: f.follower_id == ^follower_id and f.followee_id == ^followee_id
    )
    |> Repo.delete_all()

    :ok
  end

  # ── Block / Unblock ────────────────────────────────────────────────────

  @doc """
  Block a user. Also removes any existing follow relationships in both directions.
  """
  @spec block(blocker_id :: binary, blocked_id :: binary) ::
          {:ok, UserBlock.t()} | {:error, Ecto.Changeset.t()}
  def block(blocker_id, blocked_id) do
    Repo.transaction(fn ->
      unfollow(blocker_id, blocked_id)
      unfollow(blocked_id, blocker_id)

      result =
        %UserBlock{}
        |> UserBlock.changeset(%{blocker_id: blocker_id, blocked_id: blocked_id})
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:blocker_id, :blocked_id])

      case result do
        {:ok, block} -> block
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  end

  @doc """
  Unblock a user.
  """
  @spec unblock(blocker_id :: binary, blocked_id :: binary) :: :ok
  def unblock(blocker_id, blocked_id) do
    from(b in UserBlock,
      where: b.blocker_id == ^blocker_id and b.blocked_id == ^blocked_id
    )
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Returns true if blocker has blocked blocked_id.
  """
  @spec blocked?(blocker_id :: binary, blocked_id :: binary) :: boolean
  def blocked?(blocker_id, blocked_id) do
    Repo.exists?(
      from b in UserBlock,
        where: b.blocker_id == ^blocker_id and b.blocked_id == ^blocked_id
    )
  end

  # ── Follow State ───────────────────────────────────────────────────────

  @doc """
  Returns the follow state between viewer and subject.

  Possible values:
  - `:self` — viewer is looking at their own profile
  - `:following` — viewer follows subject
  - `:mutual` — both follow each other (friends)
  - `:not_following` — viewer does not follow subject
  - `:blocked` — viewer has blocked subject or is blocked by them
  """
  @spec follow_state(viewer_id :: binary, subject_id :: binary) ::
          :self | :following | :mutual | :not_following | :blocked
  def follow_state(viewer_id, viewer_id), do: :self

  def follow_state(viewer_id, subject_id) do
    cond do
      blocked?(viewer_id, subject_id) || blocked?(subject_id, viewer_id) ->
        :blocked

      following?(viewer_id, subject_id) && following?(subject_id, viewer_id) ->
        :mutual

      following?(viewer_id, subject_id) ->
        :following

      true ->
        :not_following
    end
  end

  @doc """
  Returns true if follower_id follows followee_id.
  """
  @spec following?(follower_id :: binary, followee_id :: binary) :: boolean
  def following?(follower_id, followee_id) do
    Repo.exists?(
      from f in SocialFollow,
        where: f.follower_id == ^follower_id and f.followee_id == ^followee_id
    )
  end

  # ── Follower / Following Lists ─────────────────────────────────────────

  @doc """
  Returns IDs of all users that user_role_id follows.
  """
  @spec following_ids(user_role_id :: binary) :: [binary]
  def following_ids(user_role_id) do
    from(f in SocialFollow,
      where: f.follower_id == ^user_role_id,
      select: f.followee_id
    )
    |> Repo.all()
  end

  @doc """
  Returns IDs of all users that follow user_role_id.
  """
  @spec follower_ids(user_role_id :: binary) :: [binary]
  def follower_ids(user_role_id) do
    from(f in SocialFollow,
      where: f.followee_id == ^user_role_id,
      select: f.follower_id
    )
    |> Repo.all()
  end

  @doc """
  Returns IDs of users blocked by user_role_id.
  """
  @spec blocked_user_ids(user_role_id :: binary) :: [binary]
  def blocked_user_ids(user_role_id) do
    from(b in UserBlock,
      where: b.blocker_id == ^user_role_id,
      select: b.blocked_id
    )
    |> Repo.all()
  end

  @doc """
  Returns the count of users following user_role_id.
  """
  @spec follower_count(user_role_id :: binary) :: non_neg_integer
  def follower_count(user_role_id) do
    from(f in SocialFollow, where: f.followee_id == ^user_role_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns the count of users that user_role_id follows.
  """
  @spec following_count(user_role_id :: binary) :: non_neg_integer
  def following_count(user_role_id) do
    from(f in SocialFollow, where: f.follower_id == ^user_role_id)
    |> Repo.aggregate(:count)
  end

  # ── School Peer Discovery ──────────────────────────────────────────────

  @doc """
  Returns user roles at the same school as user_role_id, excluding
  blocked users and the user themselves.

  Options:
  - `:limit` — max results (default 50)
  - `:role` — filter by role atom, e.g. `:student`
  """
  @spec school_peers(user_role_id :: binary, opts :: keyword) :: [UserRole.t()]
  def school_peers(user_role_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    role_filter = Keyword.get(opts, :role)
    blocked_ids = blocked_user_ids(user_role_id)

    user_role = Repo.get(UserRole, user_role_id)

    if is_nil(user_role) || is_nil(user_role.school_id) do
      []
    else
      base =
        from(ur in UserRole,
          where:
            ur.school_id == ^user_role.school_id and
              ur.id != ^user_role_id and
              ur.id not in ^blocked_ids,
          limit: ^limit,
          order_by: [asc: ur.inserted_at]
        )

      base =
        if role_filter,
          do: where(base, [ur], ur.role == ^to_string(role_filter)),
          else: base

      Repo.all(base)
    end
  end

  @doc """
  Returns the count of peers at the same school as user_role_id.
  """
  @spec school_peer_count(user_role_id :: binary) :: non_neg_integer
  def school_peer_count(user_role_id) do
    case Repo.get(UserRole, user_role_id) do
      %UserRole{school_id: school_id} when not is_nil(school_id) ->
        from(ur in UserRole,
          where: ur.school_id == ^school_id and ur.id != ^user_role_id
        )
        |> Repo.aggregate(:count)

      _ ->
        0
    end
  end
end
