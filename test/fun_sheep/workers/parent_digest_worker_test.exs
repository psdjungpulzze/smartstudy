defmodule FunSheep.Workers.ParentDigestWorkerTest do
  @moduledoc """
  Covers the digest Oban worker via its `perform/1` callback.
  Uses Swoosh's test adapter so we can assert deliveries without sending real mail.
  """

  use FunSheep.DataCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  import Swoosh.TestAssertions

  alias FunSheep.{Accounts, Repo}
  alias FunSheep.ContentFixtures
  alias FunSheep.Engagement.StudySession
  alias FunSheep.Workers.ParentDigestWorker

  setup do
    # Ensure the Swoosh test adapter captures deliveries into the current pid's inbox.
    Application.put_env(:fun_sheep, FunSheep.Mailer, adapter: Swoosh.Adapters.Test)

    parent = ContentFixtures.create_user_role(%{role: :parent, email: "p@test.com"})
    student = ContentFixtures.create_user_role(%{role: :student, grade: "10"})
    {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
    {:ok, _} = Accounts.accept_guardian_invite(sg.id)

    {:ok, _} =
      %StudySession{}
      |> StudySession.changeset(%{
        session_type: "practice",
        time_window: "morning",
        questions_attempted: 10,
        questions_correct: 8,
        duration_seconds: 1200,
        user_role_id: student.id,
        completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    %{parent: parent, student: student}
  end

  test "delivers a digest when activity exists", %{parent: p, student: s} do
    assert :ok = perform_job(ParentDigestWorker, %{"guardian_id" => p.id, "student_id" => s.id})
    assert_email_sent(subject: "Weekly update: #{s.display_name}")
  end

  test "skips silently when there is no activity", %{parent: p} do
    fresh_student = ContentFixtures.create_user_role(%{role: :student})
    {:ok, sg} = Accounts.invite_guardian(p.id, fresh_student.email, :parent)
    {:ok, _} = Accounts.accept_guardian_invite(sg.id)

    assert :ok =
             perform_job(ParentDigestWorker, %{
               "guardian_id" => p.id,
               "student_id" => fresh_student.id
             })

    # No email sent for this pair
    refute_email_sent()
  end
end
