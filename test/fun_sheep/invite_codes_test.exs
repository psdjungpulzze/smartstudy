defmodule FunSheep.InviteCodesTest do
  @moduledoc """
  Flow B — tests for the invite code lifecycle (create + redeem).
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.Accounts
  alias FunSheep.Accounts.InviteCode
  alias FunSheep.InviteCodes
  alias FunSheep.Repo

  defp create_role(role, attrs \\ %{}) do
    defaults = %{
      interactor_user_id: Ecto.UUID.generate(),
      role: role,
      email: "u_#{System.unique_integer([:positive])}@t.com",
      display_name: "#{role}"
    }

    {:ok, r} = Accounts.create_user_role(Map.merge(defaults, attrs))
    r
  end

  describe "create/2" do
    test "creates a code with 14-day TTL and stores child metadata" do
      parent = create_role(:parent)

      assert {:ok, %InviteCode{} = inv} =
               InviteCodes.create(parent.id, %{
                 relationship_type: :parent,
                 child_display_name: "Lia",
                 child_grade: "5",
                 metadata: %{}
               })

      assert inv.guardian_id == parent.id
      assert inv.child_display_name == "Lia"
      assert inv.child_grade == "5"
      assert is_nil(inv.redeemed_at)
      assert String.length(inv.code) == 8

      # Expiry ~ 14 days from now.
      diff = DateTime.diff(inv.expires_at, inv.inserted_at, :second)
      assert_in_delta diff, 14 * 86_400, 5
    end

    test "validates child_email format when provided" do
      parent = create_role(:parent)

      assert {:error, cs} =
               InviteCodes.create(parent.id, %{
                 relationship_type: :parent,
                 child_display_name: "Kid",
                 child_email: "not-an-email"
               })

      assert errors_on(cs)[:child_email]
    end

    test "accepts a missing child_email (parent-managed path)" do
      parent = create_role(:parent)

      assert {:ok, inv} =
               InviteCodes.create(parent.id, %{
                 relationship_type: :parent,
                 child_display_name: "Kid"
               })

      assert is_nil(inv.child_email)
    end
  end

  describe "redeem/2" do
    test "links the student_guardian as :active and stamps redeemed_at" do
      parent = create_role(:parent)
      child = create_role(:student, %{email: "c_#{System.unique_integer([:positive])}@t.com"})

      {:ok, inv} =
        InviteCodes.create(parent.id, %{
          relationship_type: :parent,
          child_display_name: "Kid"
        })

      assert {:ok, _sg} = InviteCodes.redeem(inv.code, child)

      reloaded = Repo.get!(InviteCode, inv.id)
      assert not is_nil(reloaded.redeemed_at)
      assert reloaded.redeemed_by_user_role_id == child.id

      # student_guardian link exists as :active
      assert [sg] = Accounts.list_guardians_for_student(child.id)
      assert sg.status == :active
      assert sg.guardian_id == parent.id
    end

    test "rejects an unknown code" do
      child = create_role(:student)
      assert {:error, :invalid_code} = InviteCodes.redeem("ZZZZZZZZ", child)
    end

    test "rejects an already-redeemed code" do
      parent = create_role(:parent)
      child1 = create_role(:student, %{email: "c1@t.com"})
      child2 = create_role(:student, %{email: "c2@t.com"})

      {:ok, inv} =
        InviteCodes.create(parent.id, %{
          relationship_type: :parent,
          child_display_name: "Kid"
        })

      {:ok, _} = InviteCodes.redeem(inv.code, child1)
      assert {:error, :expired_or_redeemed} = InviteCodes.redeem(inv.code, child2)
    end

    test "rejects an expired code" do
      parent = create_role(:parent)
      child = create_role(:student)

      {:ok, inv} =
        InviteCodes.create(parent.id, %{
          relationship_type: :parent,
          child_display_name: "Kid"
        })

      # Backdate expiry.
      past = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:second)
      Ecto.Changeset.change(inv, expires_at: past) |> Repo.update!()

      assert {:error, :expired_or_redeemed} = InviteCodes.redeem(inv.code, child)
    end

    test "only students can redeem" do
      parent = create_role(:parent)
      another_parent = create_role(:parent)

      {:ok, inv} =
        InviteCodes.create(parent.id, %{
          relationship_type: :parent,
          child_display_name: "Kid"
        })

      assert {:error, :only_students_can_redeem} =
               InviteCodes.redeem(inv.code, another_parent)
    end
  end

  describe "list_active_for_guardian/1" do
    test "includes only unredeemed, unexpired codes for the guardian" do
      parent = create_role(:parent)
      other_parent = create_role(:parent)
      child = create_role(:student)

      {:ok, active} =
        InviteCodes.create(parent.id, %{
          relationship_type: :parent,
          child_display_name: "Alive"
        })

      # Redeemed code — should be excluded.
      {:ok, redeemed} =
        InviteCodes.create(parent.id, %{
          relationship_type: :parent,
          child_display_name: "Done"
        })

      {:ok, _} = InviteCodes.redeem(redeemed.code, child)

      # Other parent's code — should be excluded.
      {:ok, _} =
        InviteCodes.create(other_parent.id, %{
          relationship_type: :parent,
          child_display_name: "Other"
        })

      ids = InviteCodes.list_active_for_guardian(parent.id) |> Enum.map(& &1.id)
      assert ids == [active.id]
    end
  end
end
