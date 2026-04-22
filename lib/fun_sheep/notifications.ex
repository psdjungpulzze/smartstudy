defmodule FunSheep.Notifications do
  @moduledoc """
  Digest-building helpers shared by the Oban worker and the Swoosh email
  template (spec §8.1 + §8.2).

  Everything here is read-only, driven entirely by real activity data.
  A digest is only produced if the data exists — otherwise we return
  `:skip` with a reason so the worker logs a clean no-op.
  """

  import Ecto.Query, warn: false

  alias FunSheep.Accounts.{StudentGuardian, UserRole}
  alias FunSheep.Engagement.{StudySession, StudySessions}
  alias FunSheep.Notifications.UnsubscribeToken
  alias FunSheep.{Accountability, Accounts, Assessments, Repo}

  @digest_lookback_days 7

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

  @doc """
  Returns the list of {guardian, student} pairs eligible for the digest.
  Guardian must be `:active` and `digest_frequency != :off`.
  """
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
end
