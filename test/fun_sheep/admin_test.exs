defmodule FunSheep.AdminTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.{Accounts, Admin}
  alias FunSheep.Admin.AuditLog

  describe "record/1" do
    test "writes a row with the required fields and defaults" do
      assert {:ok, %AuditLog{} = log} =
               Admin.record(%{
                 actor_label: "mix-task:admin.grant",
                 action: "user.promote_to_admin",
                 target_type: "interactor_user",
                 target_id: "usr_abc"
               })

      assert log.actor_label == "mix-task:admin.grant"
      assert log.action == "user.promote_to_admin"
      assert log.target_type == "interactor_user"
      assert log.target_id == "usr_abc"
      assert log.metadata == %{}
      assert log.actor_user_role_id == nil
      assert %DateTime{} = log.inserted_at
    end

    test "requires actor_label and action" do
      assert {:error, changeset} = Admin.record(%{})
      assert %{actor_label: _, action: _} = errors_on(changeset)
    end

    test "associates with a local admin actor when provided" do
      {:ok, admin} =
        Accounts.create_user_role(%{
          interactor_user_id: Ecto.UUID.generate(),
          role: :admin,
          email: "admin@test.com",
          display_name: "Test Admin"
        })

      assert {:ok, log} =
               Admin.record(%{
                 actor_user_role_id: admin.id,
                 actor_label: "admin:admin@test.com",
                 action: "user.suspend",
                 metadata: %{"reason" => "test"}
               })

      assert log.actor_user_role_id == admin.id
      assert log.metadata == %{"reason" => "test"}
    end
  end

  describe "list_audit_logs/1" do
    test "returns inserted rows and respects limit" do
      for i <- 1..3 do
        {:ok, _} = Admin.record(%{actor_label: "test", action: "act_#{i}"})
      end

      all = Admin.list_audit_logs()
      assert length(all) == 3
      assert Enum.sort(Enum.map(all, & &1.action)) == ["act_1", "act_2", "act_3"]

      limited = Admin.list_audit_logs(limit: 2)
      assert length(limited) == 2
    end
  end
end
