defmodule FunSheep.Admin.UserDetailTest do
  use FunSheep.DataCase, async: false

  alias FunSheep.Accounts
  alias FunSheep.Admin
  alias FunSheep.Admin.UserDetail

  defp create_user(attrs \\ %{}) do
    {:ok, user} =
      Accounts.create_user_role(
        Map.merge(
          %{
            interactor_user_id: Ecto.UUID.generate(),
            role: :student,
            email: "student-#{System.unique_integer([:positive])}@x.com",
            display_name: "Student"
          },
          attrs
        )
      )

    user
  end

  describe "load/1" do
    test "returns a full aggregate for a brand-new user with zero data" do
      user = create_user()
      agg = UserDetail.load(user.id)

      assert agg.user.id == user.id
      assert agg.courses_owned == []
      assert agg.activity_timeline == []
      assert agg.audit_trail == []
      assert agg.ai_usage.calls == 0
      assert agg.ai_usage.total_tokens == 0
      assert agg.subscription.available? == false
      assert agg.interactor_profile.available? == false
      assert agg.credentials.available? == false
    end

    test "activity timeline merges audit logs and created courses" do
      user = create_user()

      {:ok, _} =
        Admin.record(%{
          actor_label: "admin:x@y.com",
          action: "user.suspend",
          target_type: "user_role",
          target_id: user.id,
          metadata: %{}
        })

      {:ok, _course} =
        FunSheep.Courses.create_course(%{
          name: "Biology",
          subject: "Biology",
          grade: "10",
          created_by_id: user.id
        })

      agg = UserDetail.load(user.id)
      summaries = Enum.map(agg.activity_timeline, & &1.summary)
      assert Enum.any?(summaries, &(&1 =~ "Suspended"))
      assert Enum.any?(summaries, &(&1 =~ "Biology"))
    end

    test "courses_owned lists every course created by the user" do
      user = create_user()

      for i <- 1..3 do
        FunSheep.Courses.create_course(%{
          name: "Course #{i}",
          subject: "Math",
          grade: "9",
          created_by_id: user.id
        })
      end

      agg = UserDetail.load(user.id)
      assert length(agg.courses_owned) == 3
    end

    test "audit_trail returns rows where user is the target" do
      user = create_user()

      {:ok, _} =
        Admin.record(%{
          actor_label: "admin:a@x.com",
          action: "user.promote_to_admin",
          target_type: "user_role",
          target_id: user.id,
          metadata: %{}
        })

      agg = UserDetail.load(user.id)
      assert length(agg.audit_trail) == 1
      assert hd(agg.audit_trail).action == "user.promote_to_admin"
    end
  end

  describe "record_view/2" do
    test "writes an admin.user.view audit log with the user's email" do
      user = create_user(%{email: "peek@example.com"})

      actor = %{"user_role_id" => nil, "email" => "admin@test.com"}
      {:ok, _} = UserDetail.record_view(user, actor)

      [log | _] = Admin.list_audit_logs(limit: 5)
      assert log.action == "admin.user.view"
      assert log.target_id == user.id
      assert log.metadata["email"] == "peek@example.com"
    end
  end
end
