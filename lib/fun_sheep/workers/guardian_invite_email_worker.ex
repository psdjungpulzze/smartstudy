defmodule FunSheep.Workers.GuardianInviteEmailWorker do
  @moduledoc """
  Sends the "a student invited you to FunSheep" email when a student
  enters a grown-up's address that doesn't yet correspond to a
  FunSheep account.

  Triggered by `Accounts.invite_guardian_by_student/3` when it falls
  into the email-only branch.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias FunSheep.Accounts.StudentGuardian
  alias FunSheep.Mailer
  alias FunSheep.Repo
  alias FunSheepWeb.Emails.GuardianInviteEmail

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"student_guardian_id" => sg_id}}) do
    case Repo.get(StudentGuardian, sg_id) do
      nil ->
        {:cancel, :student_guardian_not_found}

      %StudentGuardian{status: :pending} = sg ->
        deliver(sg)

      %StudentGuardian{status: status} ->
        {:cancel, {:not_pending, status}}
    end
  end

  defp deliver(%StudentGuardian{} = sg) do
    case GuardianInviteEmail.build(sg) do
      {:ok, email} ->
        case Mailer.deliver(email) do
          {:ok, _meta} ->
            :telemetry.execute(
              [:fun_sheep, :guardian_invite_email, :sent],
              %{count: 1},
              %{
                student_guardian_id: sg.id,
                student_id: sg.student_id,
                invited_email: sg.invited_email
              }
            )

            :ok

          {:error, reason} ->
            Logger.error("[GuardianInviteEmail] delivery failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.warning(
          "[GuardianInviteEmail] cannot build email for #{sg.id}: #{inspect(reason)}"
        )

        {:cancel, reason}
    end
  end
end
