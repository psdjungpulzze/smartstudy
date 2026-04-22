defmodule FunSheep.Workers.GuardianInviteEmailWorkerTest do
  use FunSheep.DataCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  import Swoosh.TestAssertions

  alias FunSheep.Accounts
  alias FunSheep.Accounts.StudentGuardian
  alias FunSheep.Repo
  alias FunSheep.Workers.GuardianInviteEmailWorker

  defp create_student(display_name \\ "Claire") do
    {:ok, s} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: :student,
        email: "stu_#{System.unique_integer([:positive])}@t.com",
        display_name: display_name
      })

    s
  end

  test "perform/1 delivers the claim email" do
    student = create_student()
    {:ok, sg} = Accounts.invite_guardian_by_student(student.id, "unknown@example.com", :parent)

    assert :ok = perform_job(GuardianInviteEmailWorker, %{student_guardian_id: sg.id})

    assert_email_sent(fn email ->
      assert email.to == [{"", "unknown@example.com"}]
      assert email.subject =~ "invited you"
    end)
  end

  test "perform/1 cancels when the student_guardian is missing" do
    assert {:cancel, :student_guardian_not_found} =
             perform_job(GuardianInviteEmailWorker, %{
               student_guardian_id: Ecto.UUID.generate()
             })
  end

  test "perform/1 cancels when the invite is no longer pending" do
    student = create_student()
    {:ok, sg} = Accounts.invite_guardian_by_student(student.id, "unknown@example.com", :parent)

    {:ok, _} =
      sg
      |> StudentGuardian.changeset(%{status: :revoked})
      |> Repo.update()

    assert {:cancel, {:not_pending, :revoked}} =
             perform_job(GuardianInviteEmailWorker, %{student_guardian_id: sg.id})
  end
end
