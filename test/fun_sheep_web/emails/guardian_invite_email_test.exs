defmodule FunSheepWeb.Emails.GuardianInviteEmailTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Accounts
  alias FunSheep.Accounts.StudentGuardian
  alias FunSheep.Repo
  alias FunSheepWeb.Emails.GuardianInviteEmail

  defp create_student(display_name) do
    {:ok, s} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: :student,
        email: "stu_#{System.unique_integer([:positive])}@t.com",
        display_name: display_name
      })

    s
  end

  defp email_invite(student_id) do
    {:ok, sg} =
      Accounts.invite_guardian_by_student(student_id, "unknown@example.com", :parent)

    Repo.preload(sg, :student)
  end

  test "builds a Swoosh email with the claim link" do
    student = create_student("Claire")
    sg = email_invite(student.id)

    assert {:ok, email} = GuardianInviteEmail.build(sg)

    assert email.to == [{"", "unknown@example.com"}]
    assert email.subject =~ "Claire invited you"
    assert email.text_body =~ "/guardian-invite/#{sg.invite_token}"
    assert email.html_body =~ "/guardian-invite/#{sg.invite_token}"
    assert email.html_body =~ "Accept invitation"
  end

  test "falls back to generic student name when display_name is blank" do
    {:ok, student} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: :student,
        email: "nameless_#{System.unique_integer([:positive])}@t.com",
        display_name: nil
      })

    sg = email_invite(student.id)
    assert {:ok, email} = GuardianInviteEmail.build(sg)
    assert email.subject =~ "A FunSheep student"
  end

  test "returns {:error, :no_invited_email} for an account-resolved row" do
    student = create_student("Claire")

    {:ok, _parent} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: :parent,
        email: "mom@example.com",
        display_name: "Mom"
      })

    {:ok, sg} = Accounts.invite_guardian_by_student(student.id, "mom@example.com", :parent)

    assert {:error, :no_invited_email} = GuardianInviteEmail.build(Repo.preload(sg, :student))
  end

  test "returns {:error, :no_invite_token} when token is missing" do
    student = create_student("Claire")
    sg = email_invite(student.id)

    {:ok, cleared} =
      sg
      |> StudentGuardian.changeset(%{invite_token: nil})
      |> Repo.update()

    assert {:error, :no_invite_token} = GuardianInviteEmail.build(Repo.preload(cleared, :student))
  end
end
