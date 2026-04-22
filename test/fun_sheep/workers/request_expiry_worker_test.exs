defmodule FunSheep.Workers.RequestExpiryWorkerTest do
  use FunSheep.DataCase, async: false

  alias FunSheep.Accounts
  alias FunSheep.PracticeRequests
  alias FunSheep.PracticeRequests.Request
  alias FunSheep.Repo
  alias FunSheep.Workers.RequestExpiryWorker

  defp create_role(role) do
    {:ok, r} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: role,
        email: "#{role}_#{System.unique_integer([:positive])}@t.com",
        display_name: "#{role}"
      })

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

  defp backdate_expires_at(request_id, hours_in_past) do
    past =
      DateTime.add(DateTime.utc_now(), -hours_in_past * 3600, :second)
      |> DateTime.truncate(:second)

    Request
    |> Repo.get!(request_id)
    |> Ecto.Changeset.change(expires_at: past)
    |> Repo.update!()
  end

  test "expires only requests whose expires_at is in the past" do
    s1 = create_role(:student)
    s2 = create_role(:student)
    p = create_role(:parent)
    link_parent(p, s1)
    link_parent(p, s2)

    {:ok, stale} = PracticeRequests.create(s1.id, p.id, %{reason_code: :streak})
    {:ok, fresh} = PracticeRequests.create(s2.id, p.id, %{reason_code: :streak})

    backdate_expires_at(stale.id, 1)

    assert :ok = RequestExpiryWorker.perform(%Oban.Job{args: %{}})

    assert Repo.get!(Request, stale.id).status == :expired
    assert Repo.get!(Request, fresh.id).status == :pending
  end

  test "is idempotent — a second run on all-fresh data is a no-op" do
    s = create_role(:student)
    p = create_role(:parent)
    link_parent(p, s)
    {:ok, _} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})

    assert :ok = RequestExpiryWorker.perform(%Oban.Job{args: %{}})
    assert :ok = RequestExpiryWorker.perform(%Oban.Job{args: %{}})
  end

  test "skips already-terminal requests even if expires_at is in the past" do
    s = create_role(:student)
    p = create_role(:parent)
    link_parent(p, s)
    {:ok, req} = PracticeRequests.create(s.id, p.id, %{reason_code: :streak})
    {:ok, _} = PracticeRequests.accept(req.id)

    backdate_expires_at(req.id, 100)
    assert :ok = RequestExpiryWorker.perform(%Oban.Job{args: %{}})

    # Still :accepted, not :expired
    assert Repo.get!(Request, req.id).status == :accepted
  end
end
