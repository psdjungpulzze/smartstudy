defmodule FunSheep.Accounts.StudentInviteGuardianTest do
  @moduledoc """
  Tests for the student-initiated grown-up invite flow —
  `Accounts.invite_guardian_by_student/3` and
  `Accounts.claim_guardian_invite_by_token/2`.
  """

  use FunSheep.DataCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  import Swoosh.TestAssertions

  alias FunSheep.Accounts
  alias FunSheep.Accounts.StudentGuardian

  defp create_role(role, attrs \\ %{}) do
    defaults = %{
      interactor_user_id: Ecto.UUID.generate(),
      role: role,
      email: "#{role}_#{System.unique_integer([:positive])}@t.com",
      display_name: "Test #{role}"
    }

    {:ok, r} = Accounts.create_user_role(Map.merge(defaults, attrs))
    r
  end

  describe "invite_guardian_by_student/3 (account-resolved)" do
    test "creates a pending link when parent UserRole exists" do
      student = create_role(:student)
      parent = create_role(:parent, %{email: "mom@example.com"})

      assert {:ok, %StudentGuardian{} = sg} =
               Accounts.invite_guardian_by_student(student.id, "mom@example.com", :parent)

      assert sg.student_id == student.id
      assert sg.guardian_id == parent.id
      assert sg.status == :pending
      assert sg.invited_email == nil
      assert sg.invite_token == nil
    end

    test "normalizes email (trims + lowercases)" do
      student = create_role(:student)
      parent = create_role(:parent, %{email: "dad@example.com"})

      assert {:ok, sg} =
               Accounts.invite_guardian_by_student(student.id, "  DAD@Example.com  ", :parent)

      assert sg.guardian_id == parent.id
    end

    test "rejects blank emails" do
      student = create_role(:student)

      assert {:error, :invalid_email} =
               Accounts.invite_guardian_by_student(student.id, "   ", :parent)
    end

    test "rejects emails without @" do
      student = create_role(:student)

      assert {:error, :invalid_email} =
               Accounts.invite_guardian_by_student(student.id, "notanemail", :parent)
    end

    test "returns already_linked when an active link already exists" do
      student = create_role(:student)
      _parent = create_role(:parent, %{email: "mom@example.com"})

      {:ok, sg} = Accounts.invite_guardian_by_student(student.id, "mom@example.com", :parent)
      {:ok, _} = Accounts.accept_guardian_invite(sg.id)

      assert {:error, :already_linked} =
               Accounts.invite_guardian_by_student(student.id, "mom@example.com", :parent)
    end

    test "returns already_invited when a pending link already exists" do
      student = create_role(:student)
      _parent = create_role(:parent, %{email: "mom@example.com"})

      {:ok, _sg} = Accounts.invite_guardian_by_student(student.id, "mom@example.com", :parent)

      assert {:error, :already_invited} =
               Accounts.invite_guardian_by_student(student.id, "mom@example.com", :parent)
    end
  end

  describe "invite_guardian_by_student/3 (email-only)" do
    test "creates a tokenised pending row when no UserRole matches the email" do
      student = create_role(:student)

      assert {:ok, %StudentGuardian{} = sg} =
               Accounts.invite_guardian_by_student(student.id, "unknown@example.com", :parent)

      assert sg.guardian_id == nil
      assert sg.invited_email == "unknown@example.com"
      assert is_binary(sg.invite_token)
      assert byte_size(sg.invite_token) > 20
      assert sg.invite_token_expires_at != nil

      assert DateTime.compare(
               sg.invite_token_expires_at,
               DateTime.add(DateTime.utc_now(), 13 * 24 * 60 * 60, :second)
             ) == :gt
    end

    test "dispatches the invite email (Oban runs inline in test)" do
      student = create_role(:student, %{display_name: "Claire"})

      {:ok, _sg} =
        Accounts.invite_guardian_by_student(student.id, "stranger@example.com", :parent)

      assert_email_sent(fn email ->
        assert email.to == [{"", "stranger@example.com"}]
        assert email.subject =~ "invited you"
      end)
    end

    test "relationship_type mismatch: parent role exists with same email as requested teacher" do
      # A :parent UserRole with this email exists, but the student is
      # inviting a :teacher. The :parent row should NOT match, so we
      # fall through to the email-only path.
      student = create_role(:student)
      _parent = create_role(:parent, %{email: "someone@example.com"})

      assert {:ok, sg} =
               Accounts.invite_guardian_by_student(student.id, "someone@example.com", :teacher)

      assert sg.guardian_id == nil
      assert sg.invited_email == "someone@example.com"
    end

    test "returns already_invited when an email-only pending link already exists" do
      student = create_role(:student)

      {:ok, _} =
        Accounts.invite_guardian_by_student(student.id, "unknown@example.com", :parent)

      assert {:error, :already_invited} =
               Accounts.invite_guardian_by_student(student.id, "unknown@example.com", :parent)
    end
  end

  describe "fetch_pending_guardian_invite_by_token/1" do
    test "returns {:ok, sg} for a valid token" do
      student = create_role(:student)
      {:ok, sg} = Accounts.invite_guardian_by_student(student.id, "new@example.com", :parent)

      assert {:ok, %StudentGuardian{id: id}} =
               Accounts.fetch_pending_guardian_invite_by_token(sg.invite_token)

      assert id == sg.id
    end

    test "returns {:error, :not_found} for an unknown token" do
      assert {:error, :not_found} =
               Accounts.fetch_pending_guardian_invite_by_token("bogus-token")
    end

    test "returns {:error, :expired} for a token past its expiry" do
      student = create_role(:student)
      {:ok, sg} = Accounts.invite_guardian_by_student(student.id, "new@example.com", :parent)

      past = DateTime.add(DateTime.utc_now(), -60, :second) |> DateTime.truncate(:second)

      {:ok, _} =
        sg
        |> StudentGuardian.changeset(%{invite_token_expires_at: past})
        |> FunSheep.Repo.update()

      assert {:error, :expired} =
               Accounts.fetch_pending_guardian_invite_by_token(sg.invite_token)
    end

    test "returns {:error, :consumed} for a non-pending token row" do
      student = create_role(:student)
      {:ok, sg} = Accounts.invite_guardian_by_student(student.id, "new@example.com", :parent)

      {:ok, _} =
        sg
        |> StudentGuardian.changeset(%{status: :revoked})
        |> FunSheep.Repo.update()

      assert {:error, :consumed} =
               Accounts.fetch_pending_guardian_invite_by_token(sg.invite_token)
    end
  end

  describe "claim_guardian_invite_by_token/2" do
    test "claims and activates the link when a parent clicks through" do
      student = create_role(:student)
      {:ok, sg} = Accounts.invite_guardian_by_student(student.id, "mom@example.com", :parent)

      # Parent signs up later and has this email.
      parent = create_role(:parent, %{email: "mom@example.com"})

      assert {:ok, %StudentGuardian{} = claimed} =
               Accounts.claim_guardian_invite_by_token(sg.invite_token, parent)

      assert claimed.guardian_id == parent.id
      assert claimed.status == :active
      assert claimed.invite_token == nil
      assert claimed.invite_token_expires_at == nil
      assert claimed.accepted_at != nil
    end

    test "returns relationship_mismatch when claimer's role disagrees" do
      student = create_role(:student)
      {:ok, sg} = Accounts.invite_guardian_by_student(student.id, "mr@example.com", :parent)
      teacher = create_role(:teacher, %{email: "mr@example.com"})

      assert {:error, :relationship_mismatch} =
               Accounts.claim_guardian_invite_by_token(sg.invite_token, teacher)
    end

    test "returns not_a_guardian for student claimers" do
      student = create_role(:student)
      {:ok, sg} = Accounts.invite_guardian_by_student(student.id, "mom@example.com", :parent)

      assert {:error, :not_a_guardian} =
               Accounts.claim_guardian_invite_by_token(sg.invite_token, student)
    end

    test "refuses to claim an expired token" do
      student = create_role(:student)
      {:ok, sg} = Accounts.invite_guardian_by_student(student.id, "mom@example.com", :parent)
      parent = create_role(:parent, %{email: "mom@example.com"})

      past = DateTime.add(DateTime.utc_now(), -60, :second) |> DateTime.truncate(:second)

      {:ok, _} =
        sg
        |> StudentGuardian.changeset(%{invite_token_expires_at: past})
        |> FunSheep.Repo.update()

      assert {:error, :expired} =
               Accounts.claim_guardian_invite_by_token(sg.invite_token, parent)
    end
  end
end
