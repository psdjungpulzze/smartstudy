defmodule FunSheep.Notifications do
  @moduledoc """
  Notifications context.

  Two responsibilities:
    1. Weekly digest building (parent emails, spec §8.1 / §8.2).
    2. Alert lifecycle — enqueue, deliver, list, mark-read — for the
       streak-at-risk, test-upcoming, readiness-drop, and in-app alert
       system (alerts spec, roadmap `docs/ROADMAP/funsheep-alerts-and-notifications.md`).

  Channels: :in_app (always), :push (if push_enabled), :email (digests).
  """

  import Ecto.Query, warn: false

  alias FunSheep.Accounts.{StudentGuardian, UserRole}
  alias FunSheep.Engagement.{StudySession, StudySessions}
  alias FunSheep.Notifications.{Notification, NotificationPreference, PushToken, UnsubscribeToken}
  alias FunSheep.{Accountability, Accounts, Assessments, Repo}

  @digest_lookback_days 7

  ## ── Weekly Digest (parent emails) ─────────────────────────────────────────

  @type digest :: %{
          guardian: UserRole.t(),
          student: UserRole.t(),
          minutes_this_week: integer(),
          minutes_prev_week: integer(),
          readiness_change: integer() | nil,
          top_improvement: any() | nil,
          top_concern: any() | nil,
          prompt: map() | nil,
          upcoming_tests: list(),
          unsubscribe_token: String.t()
        }

  @doc "Returns {guardian, student} pairs eligible for the weekly digest."
  def active_digest_recipients do
    from(sg in StudentGuardian,
      join: g in UserRole,
      on: sg.guardian_id == g.id,
      join: s in UserRole,
      on: sg.student_id == s.id,
      where:
        sg.status == :active and
          g.digest_frequency == :weekly and
          is_nil(g.suspended_at),
      select: {g, s}
    )
    |> Repo.all()
  end

  @doc """
  Builds a digest for one guardian + student pair, or returns
  `{:skip, reason}` when there isn't enough real activity to bother.
  """
  @spec build(binary(), binary()) :: {:ok, digest()} | {:skip, atom()}
  def build(guardian_id, student_id)
      when is_binary(guardian_id) and is_binary(student_id) do
    with true <- Accounts.guardian_has_access?(guardian_id, student_id),
         %UserRole{} = guardian <- Accounts.get_user_role(guardian_id),
         %UserRole{} = student <- Accounts.get_user_role(student_id) do
      build_digest(guardian, student)
    else
      false -> {:skip, :unauthorized}
      _ -> {:skip, :missing_user_role}
    end
  end

  defp build_digest(guardian, student) do
    minutes_this_week = minutes_in_window(student.id, @digest_lookback_days)

    minutes_prev_week =
      minutes_between(student.id, @digest_lookback_days, 2 * @digest_lookback_days)

    if minutes_this_week == 0 and minutes_prev_week == 0 do
      {:skip, :no_activity}
    else
      schedules = Assessments.list_upcoming_schedules(student.id, 14)

      prompt =
        Accountability.conversation_prompts_for_parent(guardian.id, student.id) |> List.first()

      {:ok,
       %{
         guardian: guardian,
         student: student,
         minutes_this_week: minutes_this_week,
         minutes_prev_week: minutes_prev_week,
         readiness_change: readiness_change_for_primary_test(student.id, schedules),
         top_improvement: nil,
         top_concern: nil,
         prompt: prompt,
         upcoming_tests: schedules,
         unsubscribe_token: UnsubscribeToken.mint(guardian.id)
       }}
    end
  end

  defp minutes_in_window(student_id, days) do
    StudySessions.list_for_student_in_window(student_id, days)
    |> Enum.map(&(&1.duration_seconds || 0))
    |> Enum.sum()
    |> div(60)
  end

  defp minutes_between(student_id, from_days, until_days) do
    now = DateTime.utc_now()
    from_ts = DateTime.add(now, -until_days, :day)
    until_ts = DateTime.add(now, -from_days, :day)

    from(s in StudySession,
      where:
        s.user_role_id == ^student_id and
          not is_nil(s.completed_at) and
          s.completed_at >= ^from_ts and
          s.completed_at < ^until_ts,
      select: coalesce(sum(s.duration_seconds), 0)
    )
    |> Repo.one()
    |> div(60)
  end

  defp readiness_change_for_primary_test(_student_id, []), do: nil

  defp readiness_change_for_primary_test(student_id, [first | _]) do
    case Assessments.readiness_trend(student_id, first.id, @digest_lookback_days) do
      %{change: change} when is_number(change) -> round(change)
      _ -> nil
    end
  end

  ## ── Alert Lifecycle ────────────────────────────────────────────────────────

  @doc """
  Enqueues in-app + push notifications for a single user.

  Opts:
    - `type` (required) — atom from `Notification.types()`
    - `title` — short subject line
    - `body` (required) — notification body text
    - `priority` — 0..3 (default 2)
    - `payload` — arbitrary map for the frontend
    - `channels` — list of channels to send on (default: computed from prefs)
    - `scheduled_for` — `DateTime` to send at (default: now)

  Returns `{:ok, [%Notification{}, ...]}` or `{:error, reason}`.
  """
  @spec enqueue(binary(), keyword()) :: {:ok, [Notification.t()]} | {:error, any()}
  def enqueue(user_role_id, opts) when is_binary(user_role_id) do
    user_role = Accounts.get_user_role(user_role_id)

    if is_nil(user_role) do
      {:error, :user_role_not_found}
    else
      channels = resolve_channels(user_role, opts)
      do_enqueue(user_role, channels, opts)
    end
  end

  defp resolve_channels(user_role, opts) do
    requested = Keyword.get(opts, :channels, [:in_app, :push])

    requested
    |> Enum.filter(fn
      :push -> user_role.push_enabled and user_role.notification_frequency != :off
      :in_app -> true
      :email -> true
      :sms -> true
    end)
  end

  defp do_enqueue(user_role, channels, opts) do
    now = DateTime.utc_now()
    scheduled_for = Keyword.get(opts, :scheduled_for, now)

    attrs_base = %{
      user_role_id: user_role.id,
      type: Keyword.fetch!(opts, :type),
      title: Keyword.get(opts, :title),
      body: Keyword.fetch!(opts, :body),
      priority: Keyword.get(opts, :priority, 2),
      payload: Keyword.get(opts, :payload, %{}),
      scheduled_for: scheduled_for,
      status: :pending
    }

    results =
      Enum.map(channels, fn channel ->
        %Notification{}
        |> Notification.changeset(Map.put(attrs_base, :channel, channel))
        |> Repo.insert()
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      notifications = Enum.map(results, fn {:ok, n} -> n end)
      broadcast_in_app(user_role.id, notifications)
      {:ok, notifications}
    else
      {:error, errors}
    end
  end

  @doc "Returns unread in-app notifications for a user (newest first, limit 50)."
  @spec list_in_app_unread(binary()) :: [Notification.t()]
  def list_in_app_unread(user_role_id) do
    from(n in Notification,
      where: n.user_role_id == ^user_role_id and n.channel == :in_app and is_nil(n.read_at),
      order_by: [desc: n.inserted_at],
      limit: 50
    )
    |> Repo.all()
  end

  @doc "Returns the unread in-app count for a user."
  @spec unread_count(binary()) :: non_neg_integer()
  def unread_count(user_role_id) do
    from(n in Notification,
      where: n.user_role_id == ^user_role_id and n.channel == :in_app and is_nil(n.read_at),
      select: count()
    )
    |> Repo.one()
  end

  @doc "Marks a single notification as read."
  @spec mark_read(binary(), binary()) :: {:ok, Notification.t()} | {:error, :not_found}
  def mark_read(user_role_id, notification_id) do
    case Repo.get_by(Notification, id: notification_id, user_role_id: user_role_id) do
      nil ->
        {:error, :not_found}

      %Notification{} = n ->
        n
        |> Notification.changeset(%{read_at: DateTime.utc_now(), status: :read})
        |> Repo.update()
    end
  end

  @doc "Marks all in-app notifications read for a user."
  @spec mark_all_read(binary()) :: {non_neg_integer(), nil}
  def mark_all_read(user_role_id) do
    now = DateTime.utc_now()

    from(n in Notification,
      where: n.user_role_id == ^user_role_id and n.channel == :in_app and is_nil(n.read_at)
    )
    |> Repo.update_all(set: [read_at: now, status: :read])
  end

  ## ── Push token management ─────────────────────────────────────────────────

  @doc "Registers or refreshes a push token for a user."
  @spec upsert_push_token(binary(), String.t(), atom()) ::
          {:ok, PushToken.t()} | {:error, Ecto.Changeset.t()}
  def upsert_push_token(user_role_id, token, platform) do
    case Repo.get_by(PushToken, user_role_id: user_role_id, token: token) do
      nil ->
        %PushToken{}
        |> PushToken.changeset(%{
          user_role_id: user_role_id,
          token: token,
          platform: platform,
          active: true
        })
        |> Repo.insert()

      %PushToken{} = existing ->
        existing
        |> PushToken.changeset(%{active: true, platform: platform})
        |> Repo.update()
    end
  end

  @doc "Deactivates a push token (device unregistered)."
  @spec deactivate_push_token(String.t()) :: :ok
  def deactivate_push_token(token) do
    from(pt in PushToken, where: pt.token == ^token)
    |> Repo.update_all(set: [active: false])

    :ok
  end

  @doc "Returns active push tokens for a user."
  @spec list_push_tokens(binary()) :: [PushToken.t()]
  def list_push_tokens(user_role_id) do
    from(pt in PushToken, where: pt.user_role_id == ^user_role_id and pt.active == true)
    |> Repo.all()
  end

  ## ── Streak alert queries ──────────────────────────────────────────────────

  @doc """
  Returns students whose streak is at risk.

  At risk means: streak > 0 and last_activity_date was yesterday (not today).
  Workers call this to find who needs a nudge before midnight resets their streak.
  """
  @spec streak_at_risk_students() :: [
          %{user_role_id: binary(), streak: integer(), email: String.t()}
        ]
  def streak_at_risk_students do
    today = Date.utc_today()
    yesterday = Date.add(today, -1)

    from(s in FunSheep.Gamification.Streak,
      join: ur in UserRole,
      on: s.user_role_id == ur.id,
      where:
        s.current_streak > 0 and
          s.last_activity_date == ^yesterday and
          ur.role == :student and
          ur.alerts_streak == true and
          ur.push_enabled == true and
          ur.notification_frequency != :off and
          is_nil(ur.suspended_at),
      select: %{
        user_role_id: ur.id,
        streak: s.current_streak,
        email: ur.email,
        display_name: ur.display_name,
        timezone: ur.timezone,
        quiet_start: ur.notification_quiet_start,
        quiet_end: ur.notification_quiet_end
      }
    )
    |> Repo.all()
  end

  ## ── Test-upcoming queries ─────────────────────────────────────────────────

  @doc """
  Returns {student, test_schedule} tuples where a test is in exactly 3 days
  or 1 day from today. Used by `TestUpcomingWorker`.

  Returns maps with role-specific data needed to enqueue the alert.
  """
  @spec upcoming_test_alerts() :: [map()]
  def upcoming_test_alerts do
    today = Date.utc_today()
    t3 = Date.add(today, 3)
    t1 = Date.add(today, 1)

    from(ts in FunSheep.Assessments.TestSchedule,
      join: ur in UserRole,
      on: ts.user_role_id == ur.id,
      where:
        ur.alerts_test_upcoming == true and
          is_nil(ur.suspended_at) and
          ts.test_date in [^t3, ^t1],
      select: %{
        test_schedule_id: ts.id,
        test_name: ts.name,
        test_date: ts.test_date,
        student_id: ur.id,
        student_email: ur.email,
        student_name: ur.display_name,
        student_timezone: ur.timezone
      }
    )
    |> Repo.all()
  end

  ## ── Notification preference helpers ──────────────────────────────────────

  @doc "Returns true if the current local hour falls in the user's quiet window."
  @spec in_quiet_hours?(UserRole.t()) :: boolean()
  def in_quiet_hours?(%UserRole{
        timezone: tz,
        notification_quiet_start: qs,
        notification_quiet_end: qe
      }) do
    local_hour =
      case DateTime.shift_zone(DateTime.utc_now(), tz || "Etc/UTC") do
        {:ok, local} -> local.hour
        _ -> DateTime.utc_now().hour
      end

    if qs > qe do
      # Overnight window (e.g. 21–8): quiet when hour >= start OR hour < end
      local_hour >= qs or local_hour < qe
    else
      # Same-day window: quiet when hour >= start AND hour < end
      local_hour >= qs and local_hour < qe
    end
  end

  ## ── Notification preferences ─────────────────────────────────────────────

  @doc """
  Returns the preference row for a (user, channel) combination, optionally
  scoped to a specific notification type.

  When `notification_type` is `nil` the channel-level default row is returned.
  When `notification_type` is given, a type-specific row is returned if it
  exists, otherwise falls back to the channel default, then `nil`.
  """
  @spec get_preference(binary(), atom(), atom() | nil) :: NotificationPreference.t() | nil
  def get_preference(user_role_id, channel, notification_type \\ nil) do
    channel_str = to_string(channel)
    type_str = notification_type && to_string(notification_type)

    if type_str do
      # Try type-specific row first, fall back to channel default.
      Repo.get_by(NotificationPreference,
        user_role_id: user_role_id,
        channel: channel_str,
        notification_type: type_str
      ) ||
        Repo.get_by(NotificationPreference,
          user_role_id: user_role_id,
          channel: channel_str,
          notification_type: nil
        )
    else
      Repo.get_by(NotificationPreference,
        user_role_id: user_role_id,
        channel: channel_str,
        notification_type: nil
      )
    end
  end

  @doc """
  Creates or updates a notification preference for a user.

  The unique key is `(user_role_id, channel, notification_type)`.
  """
  @spec upsert_preference(map()) ::
          {:ok, NotificationPreference.t()} | {:error, Ecto.Changeset.t()}
  def upsert_preference(attrs) do
    user_role_id = Map.get(attrs, :user_role_id) || Map.get(attrs, "user_role_id")
    channel = Map.get(attrs, :channel) || Map.get(attrs, "channel")
    notification_type = Map.get(attrs, :notification_type) || Map.get(attrs, "notification_type")

    existing =
      Repo.get_by(NotificationPreference,
        user_role_id: user_role_id,
        channel: to_string(channel),
        notification_type: notification_type && to_string(notification_type)
      )

    changeset =
      (existing || %NotificationPreference{})
      |> NotificationPreference.changeset(attrs)

    if existing do
      Repo.update(changeset)
    else
      Repo.insert(changeset)
    end
  end

  ## ── PubSub ────────────────────────────────────────────────────────────────

  @doc "PubSub topic for a user's in-app notifications."
  def topic(user_role_id), do: "notifications:#{user_role_id}"

  defp broadcast_in_app(user_role_id, notifications) do
    in_app = Enum.filter(notifications, &(&1.channel == :in_app))

    if in_app != [] do
      Phoenix.PubSub.broadcast(
        FunSheep.PubSub,
        topic(user_role_id),
        {:new_notifications, in_app}
      )
    end
  end
end
