defmodule FunSheep.Workers.CreditTestCreatedWorker do
  @moduledoc """
  Awards 1 quarter-unit to a teacher when they create a new test schedule.

  Idempotent — uses the test_schedule id as source_ref_id.
  Only awards credits to users with the :teacher role.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias FunSheep.{Accounts, Assessments, Credits}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"test_schedule_id" => schedule_id}}) do
    schedule = Assessments.get_test_schedule!(schedule_id)
    creator = Accounts.get_user_role!(schedule.user_role_id)

    if creator.role == :teacher do
      case Credits.award_credit(creator.id, "test_created", 1, schedule_id, %{}) do
        {:ok, _} -> :ok
        {:error, :already_awarded} -> :ok
        error -> error
      end
    else
      :ok
    end
  end
end
