defmodule FunSheep.Workers.ParentRequestEmailWorkerTest do
  @moduledoc """
  Tests quiet-hours logic and the actual dispatch path for the parent
  request email (§4.6.1, §9.3).
  """

  use FunSheep.DataCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  import Swoosh.TestAssertions

  alias FunSheep.Accounts
  alias FunSheep.PracticeRequests
  alias FunSheep.PracticeRequests.Request
  alias FunSheep.Repo
  alias FunSheep.Workers.ParentRequestEmailWorker

  defp create_role(role, attrs \\ %{}) do
    defaults = %{
      interactor_user_id: Ecto.UUID.generate(),
      role: role,
      email: "#{role}_#{System.unique_integer([:positive])}@t.com",
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

  defp setup_request(parent_attrs \\ %{}) do
    parent =
      create_role(
        :parent,
        Map.merge(
          %{display_name: "Mom", email: "mom_#{System.unique_integer([:positive])}@t.com"},
          parent_attrs
        )
      )

    student = create_role(:student, %{display_name: "Kid"})
    link_parent(parent, student)
    {:ok, req} = PracticeRequests.create(student.id, parent.id, %{reason_code: :streak})
    {req, parent, student}
  end

  describe "in_quiet_hours?/2 (§9.3)" do
    test "true at 23:00 UTC" do
      eleven_pm = DateTime.new!(~D[2026-04-22], ~T[23:00:00], "Etc/UTC")
      assert ParentRequestEmailWorker.in_quiet_hours?(eleven_pm, "Etc/UTC")
    end

    test "true at 03:00 UTC" do
      three_am = DateTime.new!(~D[2026-04-22], ~T[03:00:00], "Etc/UTC")
      assert ParentRequestEmailWorker.in_quiet_hours?(three_am, "Etc/UTC")
    end

    test "false at 09:00 UTC" do
      nine_am = DateTime.new!(~D[2026-04-22], ~T[09:00:00], "Etc/UTC")
      refute ParentRequestEmailWorker.in_quiet_hours?(nine_am, "Etc/UTC")
    end

    test "false at 21:00 UTC (just before cutoff)" do
      nine_pm = DateTime.new!(~D[2026-04-22], ~T[21:00:00], "Etc/UTC")
      refute ParentRequestEmailWorker.in_quiet_hours?(nine_pm, "Etc/UTC")
    end
  end

  describe "next_send_time/2 (§9.3)" do
    test "returns now when not in quiet hours" do
      noon = DateTime.new!(~D[2026-04-22], ~T[12:00:00], "Etc/UTC")
      assert ParentRequestEmailWorker.next_send_time(noon, "Etc/UTC") == noon
    end

    test "returns 7am local on the same day when called before 7am" do
      four_am = DateTime.new!(~D[2026-04-22], ~T[04:00:00], "Etc/UTC")
      expected = DateTime.new!(~D[2026-04-22], ~T[07:00:00], "Etc/UTC")
      assert ParentRequestEmailWorker.next_send_time(four_am, "Etc/UTC") == expected
    end

    test "returns 7am next day when called at/after 10pm" do
      eleven_pm = DateTime.new!(~D[2026-04-22], ~T[23:00:00], "Etc/UTC")
      expected = DateTime.new!(~D[2026-04-23], ~T[07:00:00], "Etc/UTC")
      assert ParentRequestEmailWorker.next_send_time(eleven_pm, "Etc/UTC") == expected
    end
  end

  describe "resolve_timezone/1" do
    test "uses the guardian's timezone when present" do
      {req, p, _s} = setup_request(%{timezone: "Asia/Seoul"})
      req = Repo.preload(req, [:guardian, :student])
      assert ParentRequestEmailWorker.resolve_timezone(req) == "Asia/Seoul"
      assert p.timezone == "Asia/Seoul"
    end

    test "falls back to the student's timezone when guardian has none" do
      parent = create_role(:parent, %{display_name: "Dad"})
      student = create_role(:student, %{display_name: "Kid", timezone: "Australia/Sydney"})
      link_parent(parent, student)
      {:ok, req} = PracticeRequests.create(student.id, parent.id, %{reason_code: :streak})
      req = Repo.preload(req, [:guardian, :student])
      assert ParentRequestEmailWorker.resolve_timezone(req) == "Australia/Sydney"
    end

    test "falls back to Etc/UTC when neither has a timezone" do
      {req, _p, _s} = setup_request()
      req = Repo.preload(req, [:guardian, :student])
      assert ParentRequestEmailWorker.resolve_timezone(req) == "Etc/UTC"
    end
  end

  describe "perform/1 — delivery path" do
    test "delivers the email when not in quiet hours and marks telemetry" do
      # Telemetry capture
      test_pid = self()
      handler = "email-sent-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler,
        [:fun_sheep, :practice_request, :email_sent],
        fn _, m, meta, _ -> send(test_pid, {:email_sent, m, meta}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      # The create/3 call in setup already triggers dispatch via
      # testing: :inline Oban, so an email should have been sent.
      {req, parent, _s} = setup_request()

      assert_email_sent(fn email ->
        assert email.to |> Enum.any?(fn {_n, addr} -> addr == parent.email end)
      end)

      # Telemetry fired — metadata contains request_id
      assert_received {:email_sent, _, %{request_id: rid}}
      assert rid == req.id
    end

    test "cancels gracefully when guardian has no email" do
      # Parent created without email by bypassing changeset validations.
      # In practice: a parent UserRole with :email=nil is invalid, but we
      # still want the worker to cancel rather than crash if the DB state
      # ever gets there.
      parent = create_role(:parent, %{display_name: "Mom"})
      student = create_role(:student, %{display_name: "Kid"})
      link_parent(parent, student)
      {:ok, req} = PracticeRequests.create(student.id, parent.id, %{reason_code: :streak})

      # Null the email on the parent record via raw update to simulate
      # bad data — real validation blocks this.
      import Ecto.Query
      from(u in FunSheep.Accounts.UserRole, where: u.id == ^parent.id)
      |> Repo.update_all(set: [email: nil])

      # Manually invoke perform/1 (the email was already sent during
      # create/3; this is the degraded-state re-attempt path).
      job = %Oban.Job{args: %{"request_id" => req.id}}
      assert {:cancel, :no_guardian_email} = ParentRequestEmailWorker.perform(job)
    end

    test "cancels when the request is in a terminal state" do
      {req, _p, _s} = setup_request()
      {:ok, _} = PracticeRequests.accept(req.id)

      job = %Oban.Job{args: %{"request_id" => req.id}}
      assert {:cancel, {:not_pending, :accepted}} = ParentRequestEmailWorker.perform(job)
    end

    test "returns :cancel when request does not exist" do
      job = %Oban.Job{args: %{"request_id" => Ecto.UUID.generate()}}
      assert {:cancel, :request_not_found} = ParentRequestEmailWorker.perform(job)
    end
  end
end
