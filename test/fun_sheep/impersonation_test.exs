defmodule FunSheep.ImpersonationTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.{Accounts, Admin}

  defp create(role, email) do
    {:ok, u} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: role,
        email: email,
        display_name: "u-" <> email
      })

    u
  end

  describe "start_impersonation/2 — privilege boundaries" do
    test "admin may impersonate a student — returns session keys + audit row" do
      admin = create(:admin, "a@x.com")
      target = create(:student, "t@x.com")

      assert {:ok,
              %{
                "impersonated_user_role_id" => tid,
                "real_admin_user_role_id" => aid,
                "impersonation_expires_at" => exp
              }} = Admin.start_impersonation(admin, target)

      assert tid == target.id
      assert aid == admin.id
      assert {:ok, %DateTime{}, _} = DateTime.from_iso8601(exp)

      logs = Admin.list_audit_logs()
      assert Enum.any?(logs, &(&1.action == "impersonation.start" and &1.target_id == target.id))
    end

    test "admin cannot impersonate themselves" do
      admin = create(:admin, "self@x.com")
      assert {:error, :cannot_impersonate_self} = Admin.start_impersonation(admin, admin)
    end

    test "admin cannot impersonate another admin" do
      admin = create(:admin, "a1@x.com")
      other_admin = create(:admin, "a2@x.com")

      assert {:error, :cannot_impersonate_admin} =
               Admin.start_impersonation(admin, other_admin)
    end

    test "admin cannot impersonate a suspended user" do
      admin = create(:admin, "a3@x.com")
      target = create(:student, "sus@x.com")
      {:ok, suspended} = Admin.suspend_user(target, %{"user_role_id" => admin.id, "email" => admin.email})

      assert {:error, :target_suspended} = Admin.start_impersonation(admin, suspended)
    end

    test "non-admin callers are rejected" do
      teacher = create(:teacher, "t@x.com")
      student = create(:student, "s@x.com")

      assert {:error, :not_admin} = Admin.start_impersonation(teacher, student)
    end
  end

  describe "impersonation_expired?/1" do
    test "returns true for past timestamps" do
      past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.to_iso8601()
      assert Admin.impersonation_expired?(past)
    end

    test "returns false for future timestamps" do
      future = DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.to_iso8601()
      refute Admin.impersonation_expired?(future)
    end

    test "treats garbage input as expired (fail secure)" do
      assert Admin.impersonation_expired?("not-a-date")
      assert Admin.impersonation_expired?(nil)
    end
  end

  describe "stop_impersonation/3" do
    test "records an audit row" do
      admin = create(:admin, "a4@x.com")
      target = create(:student, "tgt@x.com")

      :ok = Admin.stop_impersonation(admin, target, :manual)

      logs = Admin.list_audit_logs()
      assert Enum.any?(logs, &(&1.action == "impersonation.stop" and &1.target_id == target.id))
    end
  end
end
