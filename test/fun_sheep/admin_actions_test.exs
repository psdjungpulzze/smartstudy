defmodule FunSheep.AdminActionsTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.{Accounts, Admin, Courses}
  alias FunSheep.Accounts.UserRole

  defp create_user(role, email) do
    {:ok, user} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: role,
        email: email,
        display_name: "Test " <> to_string(role)
      })

    user
  end

  defp actor(admin) do
    %{"user_role_id" => admin.id, "email" => admin.email}
  end

  describe "suspend_user/2 + unsuspend_user/2" do
    test "toggles suspended_at and records an audit row" do
      admin = create_user(:admin, "admin@test.com")
      target = create_user(:student, "stu@test.com")

      assert {:ok, suspended} = Admin.suspend_user(target, actor(admin))
      assert UserRole.suspended?(suspended)

      logs = Admin.list_audit_logs()
      assert Enum.any?(logs, &(&1.action == "user.suspend" and &1.target_id == target.id))

      assert {:ok, reinstated} = Admin.unsuspend_user(suspended, actor(admin))
      refute UserRole.suspended?(reinstated)

      logs = Admin.list_audit_logs()
      assert Enum.any?(logs, &(&1.action == "user.unsuspend"))
    end
  end

  describe "promote_to_admin/2" do
    test "creates a separate :admin UserRole row and logs it" do
      operator = create_user(:admin, "op@test.com")
      target = create_user(:student, "someone@test.com")

      assert {:ok, admin_row} = Admin.promote_to_admin(target, actor(operator))
      assert admin_row.role == :admin
      assert admin_row.interactor_user_id == target.interactor_user_id
      refute admin_row.id == target.id

      # Original student row is untouched.
      assert Accounts.get_user_role!(target.id).role == :student

      logs = Admin.list_audit_logs()

      assert Enum.any?(logs, fn l ->
               l.action == "user.promote_to_admin" and l.target_id == target.id
             end)
    end

    test "is idempotent — returns existing admin row on second call" do
      operator = create_user(:admin, "op2@test.com")
      target = create_user(:student, "twice@test.com")

      {:ok, first} = Admin.promote_to_admin(target, actor(operator))
      {:ok, second} = Admin.promote_to_admin(target, actor(operator))

      assert first.id == second.id
    end
  end

  describe "demote_admin/2" do
    test "deletes an :admin row" do
      operator = create_user(:admin, "op3@test.com")
      target_admin = create_user(:admin, "demoteme@test.com")

      assert {:ok, _} = Admin.demote_admin(target_admin, actor(operator))
      assert Accounts.get_user_role(target_admin.id) == nil
    end

    test "refuses to demote a non-admin row" do
      operator = create_user(:admin, "op4@test.com")
      target = create_user(:student, "nope@test.com")

      assert {:error, :not_admin} = Admin.demote_admin(target, actor(operator))
    end
  end

  describe "delete_course/2" do
    test "deletes a course and records an audit row" do
      admin = create_user(:admin, "op5@test.com")

      {:ok, course} =
        Courses.create_course(%{
          name: "Algebra",
          subject: "Math",
          grade: "9",
          created_by_id: admin.id
        })

      assert {:ok, _} = Admin.delete_course(course, actor(admin))
      assert_raise Ecto.NoResultsError, fn -> Courses.get_course!(course.id) end

      logs = Admin.list_audit_logs()
      assert Enum.any?(logs, &(&1.action == "course.delete" and &1.target_id == course.id))
    end
  end
end
