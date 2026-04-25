defmodule FunSheep.Workers.StreakAtRiskWorkerTest do
  use FunSheep.DataCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  import Ecto.Query

  alias FunSheep.{Gamification, Repo}
  alias FunSheep.ContentFixtures
  alias FunSheep.Notifications.Notification
  alias FunSheep.Workers.StreakAtRiskWorker

  defp make_at_risk_student do
    student = ContentFixtures.create_user_role(%{role: :student})
    {:ok, _} = Gamification.get_or_create_streak(student.id)
    yesterday = Date.add(Date.utc_today(), -1)

    Repo.update_all(
      from(s in FunSheep.Gamification.Streak, where: s.user_role_id == ^student.id),
      set: [current_streak: 5, last_activity_date: yesterday]
    )

    Repo.update_all(
      from(ur in FunSheep.Accounts.UserRole, where: ur.id == ^student.id),
      set: [
        alerts_streak: true,
        push_enabled: true,
        notification_frequency: :standard,
        # Set quiet window to 0-0 so it never blocks in CI regardless of run time.
        notification_quiet_start: 0,
        notification_quiet_end: 0
      ]
    )

    student
  end

  test "perform/1 enqueues in-app + push alerts for at-risk students" do
    student = make_at_risk_student()

    assert :ok = perform_job(StreakAtRiskWorker, %{})

    notifs =
      from(n in Notification, where: n.user_role_id == ^student.id)
      |> Repo.all()

    channels = Enum.map(notifs, & &1.channel)
    assert :in_app in channels
    assert :push in channels
    assert Enum.all?(notifs, &(&1.type == :streak_at_risk))
  end

  test "perform/1 does not alert a student who already studied today" do
    student = ContentFixtures.create_user_role(%{role: :student})
    {:ok, _} = Gamification.get_or_create_streak(student.id)
    today = Date.utc_today()

    Repo.update_all(
      from(s in FunSheep.Gamification.Streak, where: s.user_role_id == ^student.id),
      set: [current_streak: 3, last_activity_date: today]
    )

    Repo.update_all(
      from(ur in FunSheep.Accounts.UserRole, where: ur.id == ^student.id),
      set: [alerts_streak: true, push_enabled: true]
    )

    assert :ok = perform_job(StreakAtRiskWorker, %{})

    count =
      from(n in Notification, where: n.user_role_id == ^student.id)
      |> Repo.aggregate(:count)

    assert count == 0
  end

  test "perform/1 does not alert a student who opted out of streak alerts" do
    student = make_at_risk_student()

    Repo.update_all(
      from(ur in FunSheep.Accounts.UserRole, where: ur.id == ^student.id),
      set: [alerts_streak: false]
    )

    assert :ok = perform_job(StreakAtRiskWorker, %{})

    count =
      from(n in Notification, where: n.user_role_id == ^student.id)
      |> Repo.aggregate(:count)

    assert count == 0
  end

  test "perform/1 does not alert a student with push disabled" do
    student = make_at_risk_student()

    Repo.update_all(
      from(ur in FunSheep.Accounts.UserRole, where: ur.id == ^student.id),
      set: [push_enabled: false]
    )

    assert :ok = perform_job(StreakAtRiskWorker, %{})

    push_count =
      from(n in Notification,
        where: n.user_role_id == ^student.id and n.channel == :push
      )
      |> Repo.aggregate(:count)

    assert push_count == 0
  end
end
