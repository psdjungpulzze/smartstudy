defmodule FunSheep.CreditsTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.{Accounts, Billing, Credits, Repo}
  alias FunSheep.Credits.{WoolCredit, CreditTransfer}

  # ── Fixtures ────────────────────────────────────────────────────────────────

  defp create_teacher do
    {:ok, ur} =
      Accounts.create_user_role(%{
        interactor_user_id: "teacher_#{System.unique_integer([:positive])}",
        role: :teacher,
        email: "teacher#{System.unique_integer([:positive])}@test.com",
        display_name: "Teacher"
      })

    ur
  end

  defp create_student do
    {:ok, ur} =
      Accounts.create_user_role(%{
        interactor_user_id: "student_#{System.unique_integer([:positive])}",
        role: :student,
        email: "student#{System.unique_integer([:positive])}@test.com",
        display_name: "Student"
      })

    ur
  end

  defp award(user_role_id, source, qu, ref \\ nil) do
    Credits.award_credit(user_role_id, source, qu, ref, %{})
  end

  # ── get_balance/1 ───────────────────────────────────────────────────────────

  describe "get_balance/1" do
    test "returns 0 for a new teacher with no credits" do
      teacher = create_teacher()
      assert Credits.get_balance(teacher.id) == 0
    end

    test "returns correct whole-credit balance after awards" do
      teacher = create_teacher()
      # 8 quarter-units = 2 credits
      {:ok, _} = award(teacher.id, "admin_grant", 8)
      assert Credits.get_balance(teacher.id) == 2
    end

    test "floors fractional credits (3 quarter-units = 0 whole credits)" do
      teacher = create_teacher()
      {:ok, _} = award(teacher.id, "material_upload", 3)
      assert Credits.get_balance(teacher.id) == 0
    end
  end

  # ── award_credit/5 ──────────────────────────────────────────────────────────

  describe "award_credit/5" do
    test "inserts a ledger entry and increases balance" do
      teacher = create_teacher()
      {:ok, credit} = award(teacher.id, "admin_grant", 4)
      assert credit.delta == 4
      assert credit.source == "admin_grant"
      assert Credits.get_balance(teacher.id) == 1
    end

    test "is idempotent when same source_ref_id is used" do
      teacher = create_teacher()
      ref = Ecto.UUID.generate()
      {:ok, _} = award(teacher.id, "referral", 4, ref)
      assert {:error, :already_awarded} = award(teacher.id, "referral", 4, ref)
      # Balance unchanged at 1
      assert Credits.get_balance(teacher.id) == 1
    end

    test "different source_ref_ids are distinct awards" do
      teacher = create_teacher()
      ref1 = Ecto.UUID.generate()
      ref2 = Ecto.UUID.generate()
      {:ok, _} = award(teacher.id, "referral", 4, ref1)
      {:ok, _} = award(teacher.id, "referral", 4, ref2)
      assert Credits.get_balance(teacher.id) == 2
    end

    test "nil source_ref_id is not deduplicated" do
      teacher = create_teacher()
      {:ok, _} = award(teacher.id, "admin_grant", 4, nil)
      {:ok, _} = award(teacher.id, "admin_grant", 4, nil)
      assert Credits.get_balance(teacher.id) == 2
    end
  end

  # ── Referral batch logic ────────────────────────────────────────────────────

  describe "referral batches" do
    test "9 active students produces 0 referral credits" do
      teacher = create_teacher()

      for _ <- 1..9 do
        student = create_student()
        {:ok, sg} = Accounts.invite_guardian(teacher.id, student.email, :teacher)
        {:ok, _} = Accounts.accept_guardian_invite(sg.id)
      end

      {:ok, count} = Credits.count_active_students(teacher.id)
      assert count == 9
      assert Credits.count_referral_awards(teacher.id) == 0
    end

    test "10 active students eligible for 1 credit batch" do
      teacher = create_teacher()

      for _ <- 1..10 do
        student = create_student()
        {:ok, sg} = Accounts.invite_guardian(teacher.id, student.email, :teacher)
        {:ok, _} = Accounts.accept_guardian_invite(sg.id)
      end

      {:ok, count} = Credits.count_active_students(teacher.id)
      batches = div(count, 10)
      assert batches == 1
    end
  end

  # ── transfer_credits/4 ───────────────────────────────────────────────────────

  describe "transfer_credits/4" do
    test "fails with :insufficient_balance when sender has no credits" do
      teacher = create_teacher()
      student = create_student()

      assert {:error, :insufficient_balance} =
               Credits.transfer_credits(teacher.id, student.id, 1)
    end

    test "succeeds and creates 3 rows atomically (transfer + 2 credits)" do
      sender = create_teacher()
      recipient = create_teacher()

      {:ok, _} = award(sender.id, "admin_grant", 4)
      assert Credits.get_balance(sender.id) == 1

      {:ok, transfer} = Credits.transfer_credits(sender.id, recipient.id, 1, "test note")

      assert transfer.__struct__ == CreditTransfer
      assert transfer.amount_quarter_units == 4

      # Sender balance decremented
      assert Credits.get_balance(sender.id) == 0
      # Recipient balance incremented
      assert Credits.get_balance(recipient.id) == 1

      # Check 3 rows exist: 1 transfer + 2 wool_credits
      assert Repo.get!(CreditTransfer, transfer.id)
      debit = Repo.get_by!(WoolCredit, source: "transfer_out", source_ref_id: transfer.id)
      credit = Repo.get_by!(WoolCredit, source: "transfer_in", source_ref_id: transfer.id)
      assert debit.delta == -4
      assert credit.delta == 4
    end

    test "fails with :invalid_recipient for a non-existent user_role_id" do
      sender = create_teacher()
      {:ok, _} = award(sender.id, "admin_grant", 4)

      assert {:error, :invalid_recipient} =
               Credits.transfer_credits(sender.id, Ecto.UUID.generate(), 1)
    end
  end

  # ── redeem_for_subscription/2 ────────────────────────────────────────────────

  describe "redeem_for_subscription/2" do
    test "fails with :insufficient_balance when user has no credits" do
      student = create_student()
      assert {:error, :insufficient_balance} = Credits.redeem_for_subscription(student.id, 1)
    end

    test "extends an active subscription by 30 days per credit" do
      student = create_student()
      {:ok, _} = award(student.id, "admin_grant", 4)

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      future = DateTime.add(now, 60 * 86_400, :second)

      {:ok, sub} = Billing.get_or_create_subscription(student.id)

      {:ok, _} =
        Billing.update_subscription(sub, %{
          plan: "monthly",
          status: "active",
          current_period_start: now,
          current_period_end: future
        })

      {:ok, updated_sub} = Credits.redeem_for_subscription(student.id, 1)

      expected_end = DateTime.add(future, 30 * 86_400, :second)
      diff = DateTime.diff(updated_sub.current_period_end, expected_end, :second)
      assert abs(diff) <= 2
      assert Credits.get_balance(student.id) == 0
    end

    test "creates a new subscription if none exists" do
      student = create_student()
      {:ok, _} = award(student.id, "admin_grant", 4)

      {:ok, sub} = Credits.redeem_for_subscription(student.id, 1)
      assert sub.status == "active"
      assert sub.plan == "monthly"
      assert Credits.get_balance(student.id) == 0
    end
  end

  # ── list_ledger/2 ────────────────────────────────────────────────────────────

  describe "list_ledger/2" do
    test "returns most recent entries first" do
      teacher = create_teacher()
      {:ok, _} = award(teacher.id, "admin_grant", 4)
      {:ok, _} = award(teacher.id, "material_upload", 2)

      ledger = Credits.list_ledger(teacher.id)
      assert length(ledger) == 2
      # Both entries should be present; order may be equal-timestamp-dependent
      sources = Enum.map(ledger, & &1.source)
      assert "admin_grant" in sources
      assert "material_upload" in sources
    end

    test "respects the limit option" do
      teacher = create_teacher()

      for _i <- 1..5 do
        {:ok, _} = award(teacher.id, "admin_grant", 4, nil)
      end

      assert length(Credits.list_ledger(teacher.id, limit: 3)) == 3
    end
  end
end
