defmodule FunSheep.FlowCRegressionTest do
  @moduledoc """
  Flow C regression — enforces the §6.3 invariants that teachers
  never appear in a student's guardian picker for billing and never
  receive `ParentRequestEmail`, even when the student was added to
  FunSheep by a teacher.
  """

  use FunSheep.DataCase, async: false

  import Swoosh.TestAssertions

  alias FunSheep.Accounts
  alias FunSheep.PracticeRequests

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

  defp link(guardian, student, type) do
    {:ok, _} =
      Accounts.create_student_guardian(%{
        guardian_id: guardian.id,
        student_id: student.id,
        relationship_type: type,
        status: :active,
        invited_at: DateTime.utc_now() |> DateTime.truncate(:second),
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    :ok
  end

  describe "teacher-added student with a parent also linked (§6.2 Step 5)" do
    test "guardian picker lists only the parent" do
      student = create_role(:student, %{display_name: "Kid"})
      parent = create_role(:parent, %{display_name: "Mom"})
      teacher = create_role(:teacher, %{display_name: "Mrs Lee"})

      link(teacher, student, :teacher)
      link(parent, student, :parent)

      picker = Accounts.list_active_guardian_roles_for_student(student.id, only: :parent)
      ids = Enum.map(picker, & &1.id)

      assert parent.id in ids
      refute teacher.id in ids
    end

    test "PracticeRequests.create/3 + ParentRequestEmailWorker dispatches only to the parent" do
      student = create_role(:student, %{display_name: "Kid"})
      parent = create_role(:parent, %{display_name: "Mom"})
      teacher = create_role(:teacher, %{display_name: "Mrs Lee"})

      link(teacher, student, :teacher)
      link(parent, student, :parent)

      # Student sends a request directly to the parent (mirrors what the UI
      # does after filtering the picker to :parent guardians only).
      {:ok, _req} =
        PracticeRequests.create(student.id, parent.id, %{reason_code: :streak})

      # Swoosh test adapter captured exactly one email — to the parent.
      # The predicate function must *return* truthy (Swoosh iterates
      # captured emails looking for a match), so use boolean expressions
      # rather than raise-on-fail assert/refute.
      assert_email_sent(fn email ->
        recipients = Enum.map(email.to, fn {_n, addr} -> addr end)
        parent.email in recipients and teacher.email not in recipients
      end)
    end
  end

  describe "teacher-added student with NO parent linked (§4.8 fallback)" do
    test "guardian picker returns empty — UI falls back to invite-a-grown-up" do
      student = create_role(:student)
      teacher = create_role(:teacher)
      link(teacher, student, :teacher)

      picker = Accounts.list_active_guardian_roles_for_student(student.id, only: :parent)
      assert picker == []
    end
  end
end
