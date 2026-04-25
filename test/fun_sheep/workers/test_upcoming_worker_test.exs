defmodule FunSheep.Workers.TestUpcomingWorkerTest do
  use FunSheep.DataCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  import Ecto.Query

  alias FunSheep.{Accounts, Assessments, Repo}
  alias FunSheep.ContentFixtures
  alias FunSheep.Notifications.Notification
  alias FunSheep.Workers.TestUpcomingWorker

  defp create_test_schedule(student, days_from_today) do
    course = ContentFixtures.create_course()
    test_date = Date.add(Date.utc_today(), days_from_today)

    {:ok, ts} =
      Assessments.create_test_schedule(%{
        user_role_id: student.id,
        course_id: course.id,
        name: "Test #{days_from_today}d",
        test_date: test_date,
        scope: %{"chapters" => [1, 2]}
      })

    ts
  end

  test "perform/1 enqueues T-3 alerts for student with test in 3 days" do
    student = ContentFixtures.create_user_role(%{role: :student})
    _schedule = create_test_schedule(student, 3)

    assert :ok = perform_job(TestUpcomingWorker, %{})

    notifs =
      from(n in Notification,
        where: n.user_role_id == ^student.id and n.type == :test_upcoming_3d
      )
      |> Repo.all()

    assert length(notifs) > 0
  end

  test "perform/1 enqueues T-1 alerts for student with test tomorrow" do
    student = ContentFixtures.create_user_role(%{role: :student})
    _schedule = create_test_schedule(student, 1)

    assert :ok = perform_job(TestUpcomingWorker, %{})

    notifs =
      from(n in Notification,
        where: n.user_role_id == ^student.id and n.type == :test_upcoming_1d
      )
      |> Repo.all()

    assert length(notifs) > 0
  end

  test "perform/1 sends guardian alerts when guardian is active" do
    student = ContentFixtures.create_user_role(%{role: :student})
    parent = ContentFixtures.create_user_role(%{role: :parent})
    {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
    {:ok, _} = Accounts.accept_guardian_invite(sg.id)

    _schedule = create_test_schedule(student, 3)

    assert :ok = perform_job(TestUpcomingWorker, %{})

    parent_notifs =
      from(n in Notification,
        where: n.user_role_id == ^parent.id and n.type == :test_upcoming_3d
      )
      |> Repo.all()

    assert length(parent_notifs) > 0
  end

  test "perform/1 is a no-op when no tests are upcoming" do
    student = ContentFixtures.create_user_role(%{role: :student})

    assert :ok = perform_job(TestUpcomingWorker, %{})

    count =
      from(n in Notification,
        where:
          n.user_role_id == ^student.id and
            n.type in [:test_upcoming_3d, :test_upcoming_1d]
      )
      |> Repo.aggregate(:count)

    assert count == 0
  end

  test "perform/1 does not alert a student with alerts_test_upcoming=false" do
    student = ContentFixtures.create_user_role(%{role: :student})

    Repo.update_all(
      from(ur in FunSheep.Accounts.UserRole, where: ur.id == ^student.id),
      set: [alerts_test_upcoming: false]
    )

    _schedule = create_test_schedule(student, 3)

    assert :ok = perform_job(TestUpcomingWorker, %{})

    count =
      from(n in Notification,
        where: n.user_role_id == ^student.id and n.type == :test_upcoming_3d
      )
      |> Repo.aggregate(:count)

    assert count == 0
  end

  test "perform/1 does not send guardian alert when guardian has alerts_test_upcoming=false" do
    student = ContentFixtures.create_user_role(%{role: :student})
    parent = ContentFixtures.create_user_role(%{role: :parent})
    {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
    {:ok, _} = Accounts.accept_guardian_invite(sg.id)

    Repo.update_all(
      from(ur in FunSheep.Accounts.UserRole, where: ur.id == ^parent.id),
      set: [alerts_test_upcoming: false]
    )

    _schedule = create_test_schedule(student, 3)

    assert :ok = perform_job(TestUpcomingWorker, %{})

    parent_count =
      from(n in Notification,
        where: n.user_role_id == ^parent.id and n.type == :test_upcoming_3d
      )
      |> Repo.aggregate(:count)

    assert parent_count == 0
  end
end
