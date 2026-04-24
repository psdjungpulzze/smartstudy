defmodule FunSheep.Workers.CreditReferralCheckWorker do
  @moduledoc """
  Checks whether a teacher has earned new referral credits when a student joins.

  Enqueued after a student-guardian link becomes :active. Awards 4 quarter-units
  (1 credit) for every completed batch of 10 active students. Idempotent —
  uses the student_guardian id as source_ref_id to prevent double-awarding
  for the same activation event.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias FunSheep.Credits

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "teacher_user_role_id" => teacher_id,
          "student_guardian_id" => sg_id
        }
      }) do
    with {:ok, count} <- Credits.count_active_students(teacher_id) do
      batches = div(count, 10)
      awarded = Credits.count_referral_awards(teacher_id)

      if batches > awarded do
        delta = (batches - awarded) * 4

        case Credits.award_credit(teacher_id, "referral", delta, sg_id, %{student_count: count}) do
          {:ok, _} -> :ok
          {:error, :already_awarded} -> :ok
          error -> error
        end
      else
        :ok
      end
    end
  end
end
