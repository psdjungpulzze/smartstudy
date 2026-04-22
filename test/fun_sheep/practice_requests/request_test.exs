defmodule FunSheep.PracticeRequests.RequestTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Accounts
  alias FunSheep.PracticeRequests.Request
  alias FunSheep.Repo

  defp create_user_role(attrs) do
    defaults = %{
      interactor_user_id: Ecto.UUID.generate(),
      role: :student,
      email: "user_#{System.unique_integer([:positive])}@test.com",
      display_name: "Test User"
    }

    {:ok, user_role} = Accounts.create_user_role(Map.merge(defaults, attrs))
    user_role
  end

  defp create_student, do: create_user_role(%{role: :student, display_name: "Kid"})
  defp create_parent, do: create_user_role(%{role: :parent, display_name: "Parent"})

  defp snapshot do
    %{
      "streak_days" => 5,
      "weekly_minutes" => 120,
      "weekly_questions" => 18,
      "accuracy_pct" => 82
    }
  end

  describe "create_changeset/2" do
    test "stamps sent_at and expires_at=sent+7d, defaults status to :pending" do
      student = create_student()
      parent = create_parent()

      cs =
        Request.create_changeset(%Request{}, %{
          student_id: student.id,
          guardian_id: parent.id,
          reason_code: :upcoming_test,
          metadata: snapshot()
        })

      assert cs.valid?
      {:ok, req} = Repo.insert(cs)

      assert req.status == :pending
      assert req.sent_at != nil
      assert DateTime.compare(req.expires_at, req.sent_at) == :gt

      # expires_at ≈ sent_at + 7 days (allow 1s of clock skew in truncation)
      diff = DateTime.diff(req.expires_at, req.sent_at, :second)
      assert_in_delta diff, 7 * 86_400, 2
    end

    test "requires student_id and reason_code" do
      cs = Request.create_changeset(%Request{}, %{})
      refute cs.valid?
      errors = errors_on(cs)
      assert errors[:student_id]
      assert errors[:reason_code]
      # metadata has a default of %{} so it's never "blank" at the schema layer;
      # the PracticeRequests context (PR 2) enforces a non-empty activity snapshot.
    end

    test "accepts each valid reason_code" do
      student = create_student()
      parent = create_parent()

      for code <- [:upcoming_test, :weak_topic, :streak] do
        cs =
          Request.create_changeset(%Request{}, %{
            student_id: student.id,
            guardian_id: parent.id,
            reason_code: code,
            metadata: snapshot()
          })

        assert cs.valid?, "reason_code #{code} should be valid"
      end
    end

    test "rejects reason_code :other without reason_text" do
      student = create_student()
      parent = create_parent()

      cs =
        Request.create_changeset(%Request{}, %{
          student_id: student.id,
          guardian_id: parent.id,
          reason_code: :other,
          metadata: snapshot()
        })

      refute cs.valid?
      assert errors_on(cs)[:reason_text]
    end

    test "accepts reason_code :other when reason_text is provided" do
      student = create_student()
      parent = create_parent()

      cs =
        Request.create_changeset(%Request{}, %{
          student_id: student.id,
          guardian_id: parent.id,
          reason_code: :other,
          reason_text: "I want to beat my brother's score",
          metadata: snapshot()
        })

      assert cs.valid?
    end

    test "rejects reason_text longer than 140 chars" do
      student = create_student()
      parent = create_parent()

      cs =
        Request.create_changeset(%Request{}, %{
          student_id: student.id,
          guardian_id: parent.id,
          reason_code: :other,
          reason_text: String.duplicate("x", 141),
          metadata: snapshot()
        })

      refute cs.valid?
      assert errors_on(cs)[:reason_text]
    end

    test "enforces one pending request per student (partial unique index)" do
      student = create_student()
      parent = create_parent()

      {:ok, _first} =
        Request.create_changeset(%Request{}, %{
          student_id: student.id,
          guardian_id: parent.id,
          reason_code: :streak,
          metadata: snapshot()
        })
        |> Repo.insert()

      {:error, cs} =
        Request.create_changeset(%Request{}, %{
          student_id: student.id,
          guardian_id: parent.id,
          reason_code: :streak,
          metadata: snapshot()
        })
        |> Repo.insert()

      assert "already has a pending request" in (errors_on(cs)[:student_id] || [])
    end

    test "allows a new pending request once the previous is no longer pending" do
      student = create_student()
      parent = create_parent()

      {:ok, first} =
        Request.create_changeset(%Request{}, %{
          student_id: student.id,
          guardian_id: parent.id,
          reason_code: :streak,
          metadata: snapshot()
        })
        |> Repo.insert()

      # Transition to declined
      {:ok, _} =
        first
        |> Request.transition_changeset(%{status: :declined, decided_at: DateTime.utc_now()})
        |> Repo.update()

      {:ok, _second} =
        Request.create_changeset(%Request{}, %{
          student_id: student.id,
          guardian_id: parent.id,
          reason_code: :streak,
          metadata: snapshot()
        })
        |> Repo.insert()
    end
  end

  describe "transition_changeset/2" do
    test "rejects unknown status" do
      cs = Request.transition_changeset(%Request{status: :pending}, %{status: :nope})
      refute cs.valid?
      # Ecto.Enum cast fails before validate_inclusion runs, so the error
      # surfaces on :status regardless of which validator catches it.
      assert errors_on(cs)[:status]
    end

    test "accepts each terminal status" do
      for status <- [:viewed, :accepted, :declined, :expired, :cancelled] do
        cs = Request.transition_changeset(%Request{status: :pending}, %{status: status})
        assert cs.valid?, "status #{status} should be valid"
      end
    end

    test "caps parent_note at 500 chars" do
      cs =
        Request.transition_changeset(%Request{status: :pending}, %{
          status: :declined,
          parent_note: String.duplicate("x", 501)
        })

      refute cs.valid?
      assert errors_on(cs)[:parent_note]
    end
  end

  describe "expired?/1" do
    test "returns false when expires_at is nil" do
      refute Request.expired?(%Request{expires_at: nil})
    end

    test "returns false when expires_at is in the future" do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      refute Request.expired?(%Request{expires_at: future})
    end

    test "returns true when expires_at is in the past" do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      assert Request.expired?(%Request{expires_at: past})
    end
  end

  describe "pending?/1" do
    test "returns true for :pending and :viewed" do
      assert Request.pending?(%Request{status: :pending})
      assert Request.pending?(%Request{status: :viewed})
    end

    test "returns false for terminal states" do
      for status <- [:accepted, :declined, :expired, :cancelled] do
        refute Request.pending?(%Request{status: status})
      end
    end
  end

  describe "introspection helpers" do
    test "reason_codes/0 lists all valid codes" do
      assert :upcoming_test in Request.reason_codes()
      assert :weak_topic in Request.reason_codes()
      assert :streak in Request.reason_codes()
      assert :other in Request.reason_codes()
    end

    test "statuses/0 lists all valid statuses" do
      expected = [:pending, :viewed, :accepted, :declined, :expired, :cancelled]
      for s <- expected, do: assert(s in Request.statuses())
    end

    test "ttl_days/0 returns 7 per §4.5" do
      assert Request.ttl_days() == 7
    end
  end
end
