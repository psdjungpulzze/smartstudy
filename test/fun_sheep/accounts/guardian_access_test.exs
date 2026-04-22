defmodule FunSheep.Accounts.GuardianAccessTest do
  @moduledoc """
  Covers `FunSheep.Accounts.guardian_has_access?/2` — the centralised
  authorization check required at the edge of every parent-context
  function (spec §9.1).
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.Accounts
  alias FunSheep.ContentFixtures

  setup do
    parent = ContentFixtures.create_user_role(%{role: :parent})
    student = ContentFixtures.create_user_role(%{role: :student})
    %{parent: parent, student: student}
  end

  test "returns false when no link exists", %{parent: parent, student: student} do
    refute Accounts.guardian_has_access?(parent.id, student.id)
  end

  test "returns false while link is pending", %{parent: parent, student: student} do
    {:ok, _} = Accounts.invite_guardian(parent.id, student.email, :parent)
    refute Accounts.guardian_has_access?(parent.id, student.id)
  end

  test "returns true after the student accepts", %{parent: parent, student: student} do
    {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
    {:ok, _} = Accounts.accept_guardian_invite(sg.id)

    assert Accounts.guardian_has_access?(parent.id, student.id)
  end

  test "returns false after revoke", %{parent: parent, student: student} do
    {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
    {:ok, sg} = Accounts.accept_guardian_invite(sg.id)
    {:ok, _} = Accounts.revoke_guardian(sg.id)

    refute Accounts.guardian_has_access?(parent.id, student.id)
  end

  test "returns false for non-binary args" do
    refute Accounts.guardian_has_access?(nil, nil)
    refute Accounts.guardian_has_access?(nil, Ecto.UUID.generate())
    refute Accounts.guardian_has_access?(Ecto.UUID.generate(), nil)
  end
end
