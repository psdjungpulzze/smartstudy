defmodule FunSheep.PracticeRequestsTest do
  @moduledoc """
  Covers the context API for Flow A: `create/3`, `view/1`, `accept/2`,
  `decline/3`, `expire/1`, `list_pending_for_guardian/1`,
  `count_pending_for_student/1`, `send_reminder/1`, `build_snapshot/1`.
  """

  use FunSheep.DataCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  import Swoosh.TestAssertions

  alias FunSheep.Accounts
  alias FunSheep.PracticeRequests
  alias FunSheep.PracticeRequests.Request

  setup do
    # Capture telemetry events for assertions.
    test_pid = self()
    handler_id = "test-handler-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:fun_sheep, :practice_request, :created],
        [:fun_sheep, :practice_request, :viewed],
        [:fun_sheep, :practice_request, :accepted],
        [:fun_sheep, :practice_request, :declined],
        [:fun_sheep, :practice_request, :expired],
        [:fun_sheep, :practice_request, :reminded]
      ],
      fn event, measurements, metadata, _ ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

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

  defp link_parent(parent, student) do
    {:ok, _} =
      Accounts.create_student_guardian(%{
        guardian_id: parent.id,
        student_id: student.id,
        relationship_type: :parent,
        status: :active,
        invited_at: DateTime.utc_now() |> DateTime.truncate(:second),
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    :ok
  end

  defp setup_pair do
    student = create_role(:student, %{display_name: "Lia"})

    parent =
      create_role(:parent, %{
        display_name: "Anna Smith",
        email: "anna_#{System.unique_integer([:positive])}@t.com"
      })

    link_parent(parent, student)
    %{student: student, parent: parent}
  end

  describe "create/3" do
    test "stores a pending request with an activity snapshot and emits telemetry" do
      %{student: s, parent: p} = setup_pair()

      assert {:ok, %Request{} = req} =
               PracticeRequests.create(s.id, p.id, %{reason_code: :streak})

      assert req.status == :pending
      assert req.reason_code == :streak
      assert is_map(req.metadata)
      assert Map.has_key?(req.metadata, "streak_days")
      assert Map.has_key?(req.metadata, "captured_at")

      assert_received {:telemetry, [:fun_sheep, :practice_request, :created], _, %{request_id: rid}}
      assert rid == req.id
    end

    test "rejects a second pending request from the same student" do
      %{student: s, parent: p} = setup_pair()

      {:ok, _} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})
      assert {:error, :already_pending} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})
    end

    test "enforces 48-hour cooldown after a decline" do
      %{student: s, parent: p} = setup_pair()

      {:ok, req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})
      {:ok, _} = PracticeRequests.decline(req.id, "maybe later")

      # Within the cooldown window, creation fails.
      assert {:error, :decline_cooldown} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})
    end

    test "allows a new request after the 48h cooldown lapses" do
      %{student: s, parent: p} = setup_pair()

      {:ok, req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})
      {:ok, declined} = PracticeRequests.decline(req.id, nil)

      # Backdate the decision by 49 hours to simulate cooldown expiry.
      far_past = DateTime.add(DateTime.utc_now(), -49 * 3600, :second) |> DateTime.truncate(:second)

      Ecto.Changeset.change(declined, decided_at: far_past, updated_at: far_past)
      |> FunSheep.Repo.update!()

      assert {:ok, _new_req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})
    end

    test ":other reason requires reason_text" do
      %{student: s, parent: p} = setup_pair()

      assert {:error, %Ecto.Changeset{}} =
               PracticeRequests.create(s.id, p.id, %{reason_code: :other})
    end

    test "dispatches an email via the ParentRequestEmailWorker (testing: :inline)" do
      %{student: s, parent: p} = setup_pair()

      {:ok, _req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})

      # In testing: :inline Oban mode, the worker runs synchronously during
      # `Oban.insert`, and the Swoosh test adapter captures the email.
      assert_email_sent(fn email ->
        assert email.to |> Enum.any?(fn {_n, addr} -> addr == p.email end)
        assert email.subject =~ s.display_name
        assert email.subject =~ "asked you for more practice"
      end)
    end
  end

  describe "view/1" do
    test "transitions :pending -> :viewed and emits telemetry" do
      %{student: s, parent: p} = setup_pair()
      {:ok, req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})

      assert {:ok, viewed} = PracticeRequests.view(req.id)
      assert viewed.status == :viewed
      assert not is_nil(viewed.viewed_at)

      assert_received {:telemetry, [:fun_sheep, :practice_request, :viewed], _, _}
    end

    test "is idempotent — no-op on already viewed" do
      %{student: s, parent: p} = setup_pair()
      {:ok, req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})
      {:ok, _} = PracticeRequests.view(req.id)

      assert {:ok, same} = PracticeRequests.view(req.id)
      assert same.status == :viewed
    end
  end

  describe "accept/2" do
    test "transitions to :accepted and emits telemetry" do
      %{student: s, parent: p} = setup_pair()
      {:ok, req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})

      assert {:ok, accepted} = PracticeRequests.accept(req.id, %{subscription_id: Ecto.UUID.generate()})
      assert accepted.status == :accepted
      assert not is_nil(accepted.decided_at)

      assert_received {:telemetry, [:fun_sheep, :practice_request, :accepted], _, _}
    end

    test "second concurrent accept returns {:not_pending, :accepted}" do
      %{student: s, parent: p} = setup_pair()
      {:ok, req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})

      assert {:ok, _} = PracticeRequests.accept(req.id)
      assert {:error, {:not_pending, :accepted}} = PracticeRequests.accept(req.id)
    end

    test "returns :not_found for unknown id" do
      assert {:error, :not_found} = PracticeRequests.accept(Ecto.UUID.generate())
    end
  end

  describe "decline/3" do
    test "stamps parent_note and emits telemetry" do
      %{student: s, parent: p} = setup_pair()
      {:ok, req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})

      assert {:ok, declined} = PracticeRequests.decline(req.id, "Not this week — keep going 💚")
      assert declined.status == :declined
      assert declined.parent_note == "Not this week — keep going 💚"

      assert_received {:telemetry, [:fun_sheep, :practice_request, :declined], _, _}
    end

    test "accepts nil parent_note" do
      %{student: s, parent: p} = setup_pair()
      {:ok, req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})
      assert {:ok, _} = PracticeRequests.decline(req.id, nil)
    end

    test "rejects on non-pending state" do
      %{student: s, parent: p} = setup_pair()
      {:ok, req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})
      {:ok, _} = PracticeRequests.decline(req.id, nil)
      assert {:error, :not_pending} = PracticeRequests.decline(req.id, "retry?")
    end
  end

  describe "expire/1" do
    test "transitions :pending -> :expired and emits telemetry" do
      %{student: s, parent: p} = setup_pair()
      {:ok, req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})

      assert {:ok, expired} = PracticeRequests.expire(req.id)
      assert expired.status == :expired

      assert_received {:telemetry, [:fun_sheep, :practice_request, :expired], _, _}
    end

    test "rejects if already in a terminal state" do
      %{student: s, parent: p} = setup_pair()
      {:ok, req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})
      {:ok, _} = PracticeRequests.accept(req.id)
      assert {:error, :not_pending} = PracticeRequests.expire(req.id)
    end
  end

  describe "list_pending_for_guardian/1 + count_pending_for_student/1" do
    test "lists pending + viewed requests addressed to the guardian" do
      %{student: s, parent: p} = setup_pair()

      {:ok, r1} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})
      # Create a second student + request to the same parent
      s2 = create_role(:student)
      link_parent(p, s2)
      {:ok, r2} = PracticeRequests.create(s2.id, p.id, %{reason_code: :upcoming_test})

      ids = PracticeRequests.list_pending_for_guardian(p.id) |> Enum.map(& &1.id)
      assert Enum.sort(ids) == Enum.sort([r1.id, r2.id])
    end

    test "count_pending_for_student returns 1 while pending, 0 after terminal" do
      %{student: s, parent: p} = setup_pair()
      assert PracticeRequests.count_pending_for_student(s.id) == 0

      {:ok, req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})
      assert PracticeRequests.count_pending_for_student(s.id) == 1

      {:ok, _} = PracticeRequests.decline(req.id, nil)
      assert PracticeRequests.count_pending_for_student(s.id) == 0
    end
  end

  describe "send_reminder/1" do
    test "stamps reminder_sent_at exactly once" do
      %{student: s, parent: p} = setup_pair()
      {:ok, req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})

      assert {:ok, reminded} = PracticeRequests.send_reminder(req.id)
      assert not is_nil(reminded.reminder_sent_at)

      assert_received {:telemetry, [:fun_sheep, :practice_request, :reminded], _, _}
    end

    test "second call returns :already_reminded (max 1 per request, §4.5)" do
      %{student: s, parent: p} = setup_pair()
      {:ok, req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})

      {:ok, _} = PracticeRequests.send_reminder(req.id)
      assert {:error, :already_reminded} = PracticeRequests.send_reminder(req.id)
    end

    test "rejects for terminal requests" do
      %{student: s, parent: p} = setup_pair()
      {:ok, req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})
      {:ok, _} = PracticeRequests.accept(req.id)
      assert {:error, :not_pending} = PracticeRequests.send_reminder(req.id)
    end
  end

  describe "build_snapshot/1 — §4.6 / §8.2 (no fake content)" do
    test "includes streak, minutes, sessions, accuracy, captured_at" do
      %{student: s} = setup_pair()

      snap = PracticeRequests.build_snapshot(s.id)
      assert Map.has_key?(snap, "streak_days")
      assert Map.has_key?(snap, "weekly_minutes")
      assert Map.has_key?(snap, "weekly_sessions")
      assert Map.has_key?(snap, "accuracy_pct")
      assert Map.has_key?(snap, "captured_at")
    end

    test "upcoming_test is nil when none scheduled" do
      %{student: s} = setup_pair()
      snap = PracticeRequests.build_snapshot(s.id)
      assert is_nil(snap["upcoming_test"])
    end
  end
end
