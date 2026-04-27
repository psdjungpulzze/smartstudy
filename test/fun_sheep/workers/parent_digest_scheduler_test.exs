defmodule FunSheep.Workers.ParentDigestSchedulerTest do
  @moduledoc """
  Tests for `FunSheep.Workers.ParentDigestScheduler`.

  Verifies that the scheduler fans out exactly one `ParentDigestWorker` job
  per active guardian+student pair and is a no-op when no pairs are eligible.
  """

  use FunSheep.DataCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  alias FunSheep.{Accounts, Repo}
  alias FunSheep.ContentFixtures
  alias FunSheep.Workers.{ParentDigestScheduler, ParentDigestWorker}

  defp setup_active_pair do
    parent = ContentFixtures.create_user_role(%{role: :parent})
    student = ContentFixtures.create_user_role(%{role: :student, grade: "10"})
    {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
    {:ok, _} = Accounts.accept_guardian_invite(sg.id)
    {parent, student}
  end

  describe "perform/1" do
    test "returns :ok with no eligible recipients" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform_job(ParentDigestScheduler, %{})
      end)
    end

    test "enqueues one ParentDigestWorker job per active guardian+student pair" do
      {parent, student} = setup_active_pair()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform_job(ParentDigestScheduler, %{})

        assert_enqueued(
          worker: ParentDigestWorker,
          args: %{"guardian_id" => parent.id, "student_id" => student.id}
        )
      end)
    end

    test "enqueues separate jobs for multiple active pairs" do
      {p1, s1} = setup_active_pair()
      {p2, s2} = setup_active_pair()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform_job(ParentDigestScheduler, %{})

        assert_enqueued(
          worker: ParentDigestWorker,
          args: %{"guardian_id" => p1.id, "student_id" => s1.id}
        )

        assert_enqueued(
          worker: ParentDigestWorker,
          args: %{"guardian_id" => p2.id, "student_id" => s2.id}
        )
      end)
    end

    test "does not enqueue a job for a guardian with digest_frequency=:off" do
      parent = ContentFixtures.create_user_role(%{role: :parent, digest_frequency: :off})
      student = ContentFixtures.create_user_role(%{role: :student, grade: "10"})
      {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
      {:ok, _} = Accounts.accept_guardian_invite(sg.id)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform_job(ParentDigestScheduler, %{})

        refute_enqueued(
          worker: ParentDigestWorker,
          args: %{"guardian_id" => parent.id, "student_id" => student.id}
        )
      end)
    end

    test "does not enqueue a job for a suspended guardian" do
      parent = ContentFixtures.create_user_role(%{role: :parent})
      student = ContentFixtures.create_user_role(%{role: :student, grade: "10"})
      {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
      {:ok, _} = Accounts.accept_guardian_invite(sg.id)

      import Ecto.Query

      Repo.update_all(
        from(ur in FunSheep.Accounts.UserRole, where: ur.id == ^parent.id),
        set: [suspended_at: DateTime.utc_now() |> DateTime.truncate(:second)]
      )

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform_job(ParentDigestScheduler, %{})

        refute_enqueued(
          worker: ParentDigestWorker,
          args: %{"guardian_id" => parent.id, "student_id" => student.id}
        )
      end)
    end
  end
end
