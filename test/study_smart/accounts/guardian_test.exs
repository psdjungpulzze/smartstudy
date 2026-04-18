defmodule StudySmart.Accounts.GuardianTest do
  use StudySmart.DataCase, async: true

  alias StudySmart.Accounts
  alias StudySmart.Accounts.StudentGuardian

  defp create_user_role(attrs) do
    defaults = %{
      interactor_user_id: Ecto.UUID.generate(),
      role: :student,
      email: "user_#{System.unique_integer([:positive])}@test.com",
      display_name: "Test User"
    }

    {:ok, user_role} = Accounts.create_user_role(Map.merge(defaults, attrs))
    user_role
  end

  defp create_parent do
    create_user_role(%{role: :parent, display_name: "Test Parent"})
  end

  defp create_student do
    create_user_role(%{role: :student, display_name: "Test Student"})
  end

  describe "invite_guardian/3" do
    test "creates a pending student_guardian record" do
      parent = create_parent()
      student = create_student()

      assert {:ok, %StudentGuardian{} = sg} =
               Accounts.invite_guardian(parent.id, student.email, :parent)

      assert sg.guardian_id == parent.id
      assert sg.student_id == student.id
      assert sg.status == :pending
      assert sg.relationship_type == :parent
      assert sg.invited_at != nil
    end

    test "returns error when student email not found" do
      parent = create_parent()

      assert {:error, :student_not_found} =
               Accounts.invite_guardian(parent.id, "nonexistent@test.com", :parent)
    end

    test "returns error when already linked" do
      parent = create_parent()
      student = create_student()

      {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
      Accounts.accept_guardian_invite(sg.id)

      assert {:error, :already_linked} =
               Accounts.invite_guardian(parent.id, student.email, :parent)
    end

    test "returns error when already invited" do
      parent = create_parent()
      student = create_student()

      {:ok, _sg} = Accounts.invite_guardian(parent.id, student.email, :parent)

      assert {:error, :already_invited} =
               Accounts.invite_guardian(parent.id, student.email, :parent)
    end
  end

  describe "accept_guardian_invite/1" do
    test "updates status to active and sets accepted_at" do
      parent = create_parent()
      student = create_student()
      {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)

      assert {:ok, %StudentGuardian{} = updated} = Accounts.accept_guardian_invite(sg.id)
      assert updated.status == :active
      assert updated.accepted_at != nil
    end

    test "returns error when not found" do
      assert {:error, :not_found} = Accounts.accept_guardian_invite(Ecto.UUID.generate())
    end

    test "returns error when not pending" do
      parent = create_parent()
      student = create_student()
      {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
      {:ok, _} = Accounts.accept_guardian_invite(sg.id)

      assert {:error, :not_pending} = Accounts.accept_guardian_invite(sg.id)
    end
  end

  describe "reject_guardian_invite/1" do
    test "sets status to revoked" do
      parent = create_parent()
      student = create_student()
      {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)

      assert {:ok, %StudentGuardian{} = updated} = Accounts.reject_guardian_invite(sg.id)
      assert updated.status == :revoked
    end

    test "returns error when not pending" do
      parent = create_parent()
      student = create_student()
      {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
      {:ok, _} = Accounts.accept_guardian_invite(sg.id)

      assert {:error, :not_pending} = Accounts.reject_guardian_invite(sg.id)
    end
  end

  describe "list_pending_invites_for_student/1" do
    test "returns pending invites with guardian preloaded" do
      parent = create_parent()
      student = create_student()
      {:ok, _sg} = Accounts.invite_guardian(parent.id, student.email, :parent)

      invites = Accounts.list_pending_invites_for_student(student.id)
      assert length(invites) == 1
      assert hd(invites).guardian.id == parent.id
      assert hd(invites).status == :pending
    end

    test "does not return accepted invites" do
      parent = create_parent()
      student = create_student()
      {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
      {:ok, _} = Accounts.accept_guardian_invite(sg.id)

      invites = Accounts.list_pending_invites_for_student(student.id)
      assert invites == []
    end
  end

  describe "list_students_for_guardian/1" do
    test "returns active student links with student preloaded" do
      parent = create_parent()
      student = create_student()
      {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
      {:ok, _} = Accounts.accept_guardian_invite(sg.id)

      links = Accounts.list_students_for_guardian(parent.id)
      assert length(links) == 1
      assert hd(links).student.id == student.id
    end

    test "does not return pending links" do
      parent = create_parent()
      student = create_student()
      {:ok, _sg} = Accounts.invite_guardian(parent.id, student.email, :parent)

      links = Accounts.list_students_for_guardian(parent.id)
      assert links == []
    end
  end

  describe "revoke_guardian/1" do
    test "revokes an active link" do
      parent = create_parent()
      student = create_student()
      {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
      {:ok, _} = Accounts.accept_guardian_invite(sg.id)

      assert {:ok, %StudentGuardian{status: :revoked}} = Accounts.revoke_guardian(sg.id)
    end

    test "returns error when already revoked" do
      parent = create_parent()
      student = create_student()
      {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
      {:ok, _} = Accounts.revoke_guardian(sg.id)

      assert {:error, :already_revoked} = Accounts.revoke_guardian(sg.id)
    end
  end
end
