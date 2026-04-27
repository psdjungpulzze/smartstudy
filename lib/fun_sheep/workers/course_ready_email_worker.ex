defmodule FunSheep.Workers.CourseReadyEmailWorker do
  @moduledoc """
  Sends the "your course is ready" email to the course creator when
  processing completes and questions are validated.

  Fires from Courses.broadcast_finalization/5 when status == "ready".
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 3600, fields: [:worker, :args], states: [:available, :scheduled, :executing]]

  alias FunSheep.Accounts.UserRole
  alias FunSheep.Courses
  alias FunSheep.Repo
  alias FunSheepWeb.Emails.CourseReadyEmail

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"course_id" => course_id}}) do
    course = Courses.get_course!(course_id)

    cond do
      is_nil(course.created_by_id) ->
        Logger.info("[CourseReadyEmail] No creator_id for course #{course_id}, skipping")
        :ok

      true ->
        case Repo.get(UserRole, course.created_by_id) do
          nil ->
            Logger.warning("[CourseReadyEmail] No creator found for course #{course_id}")
            :ok

          %UserRole{email: nil} ->
            Logger.info("[CourseReadyEmail] Creator has no email for course #{course_id}")
            :ok

          %UserRole{email: email, display_name: name} ->
            url = FunSheepWeb.Endpoint.url() <> "/courses/#{course_id}"

            case CourseReadyEmail.build(email, name, course.name, url)
                 |> FunSheep.Mailer.deliver() do
              {:ok, _} ->
                Logger.info("[CourseReadyEmail] Sent to #{email} for course #{course_id}")
                :ok

              {:error, reason} ->
                Logger.warning(
                  "[CourseReadyEmail] Delivery failed for #{email}: #{inspect(reason)}"
                )

                {:error, reason}
            end
        end
    end
  end
end
