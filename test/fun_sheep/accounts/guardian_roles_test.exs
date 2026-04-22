defmodule FunSheep.Accounts.GuardianRolesTest do
  @moduledoc """
  Tests for `list_active_guardian_roles_for_student/2` and
  `find_primary_guardian/1` — used by Flow A and Flow C.
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.Accounts

  defp create_role(role, attrs \\ %{}) do
    defaults = %{
      interactor_user_id: Ecto.UUID.generate(),
      role: role,
      email: "u_#{System.unique_integer([:positive])}@test.com",
      display_name: "#{role}"
    }

    {:ok, r} = Accounts.create_user_role(Map.merge(defaults, attrs))
    r
  end

  defp link(guardian, student, type) do
    {:ok, sg} =
      Accounts.create_student_guardian(%{
        guardian_id: guardian.id,
        student_id: student.id,
        relationship_type: type,
        status: :active,
        invited_at: DateTime.utc_now() |> DateTime.truncate(:second),
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    sg
  end

  defp pending_link(guardian, student, type) do
    {:ok, sg} =
      Accounts.create_student_guardian(%{
        guardian_id: guardian.id,
        student_id: student.id,
        relationship_type: type,
        status: :pending,
        invited_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    sg
  end

  describe "list_active_guardian_roles_for_student/2" do
    test "returns UserRole.t() list — excludes :pending and :revoked" do
      student = create_role(:student)
      mom = create_role(:parent, %{display_name: "Mom"})
      dad = create_role(:parent, %{display_name: "Dad"})
      pending_parent = create_role(:parent, %{display_name: "Pending"})

      link(mom, student, :parent)
      link(dad, student, :parent)
      pending_link(pending_parent, student, :parent)

      ids =
        Accounts.list_active_guardian_roles_for_student(student.id)
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert ids == Enum.sort([mom.id, dad.id])
    end

    test ":only :parent filter excludes teachers" do
      student = create_role(:student)
      mom = create_role(:parent)
      teacher = create_role(:teacher)

      link(mom, student, :parent)
      link(teacher, student, :teacher)

      ids = Accounts.list_active_guardian_roles_for_student(student.id, only: :parent) |> Enum.map(& &1.id)
      assert ids == [mom.id]
    end

    test ":only :teacher filter excludes parents" do
      student = create_role(:student)
      mom = create_role(:parent)
      teacher = create_role(:teacher)

      link(mom, student, :parent)
      link(teacher, student, :teacher)

      ids = Accounts.list_active_guardian_roles_for_student(student.id, only: :teacher) |> Enum.map(& &1.id)
      assert ids == [teacher.id]
    end

    test "returns [] when no active links" do
      student = create_role(:student)
      assert Accounts.list_active_guardian_roles_for_student(student.id) == []
    end
  end

  describe "find_primary_guardian/1" do
    test "returns a parent when present" do
      student = create_role(:student)
      mom = create_role(:parent, %{display_name: "Mom"})
      teacher = create_role(:teacher, %{display_name: "Mrs Lee"})

      link(mom, student, :parent)
      link(teacher, student, :teacher)

      assert %{id: mom_id, role: :parent} = Accounts.find_primary_guardian(student.id)
      assert mom_id == mom.id
    end

    test "falls back to teacher only when no parent linked" do
      student = create_role(:student)
      teacher = create_role(:teacher)
      link(teacher, student, :teacher)

      assert %{role: :teacher} = Accounts.find_primary_guardian(student.id)
    end

    test "returns nil with no active links" do
      student = create_role(:student)
      assert is_nil(Accounts.find_primary_guardian(student.id))
    end

    test "prefers oldest active parent link" do
      student = create_role(:student)
      mom = create_role(:parent, %{display_name: "Mom"})
      dad = create_role(:parent, %{display_name: "Dad"})

      link(mom, student, :parent)
      # Briefly sleep to make sure inserted_at differs.
      Process.sleep(1100)
      link(dad, student, :parent)

      assert %{id: primary_id} = Accounts.find_primary_guardian(student.id)
      assert primary_id == mom.id
    end
  end
end
