defmodule Mix.Tasks.Funsheep.Validation.Resweep do
  @shortdoc "Re-enqueue all questions stuck at validation_status = :pending"

  @moduledoc """
  Finds every course with at least one `:pending` question and calls
  `FunSheep.Questions.requeue_pending_validations/1` for each.

  Use when a validation pipeline crash has left courses with "Validating
  questions for accuracy — N remaining" frozen in the UI. The 15-minute
  `StuckValidationSweeperWorker` cron handles recurrence going forward;
  this task handles the existing zombies on the first deploy.

  ## Usage

      mix funsheep.validation.resweep              # all courses
      mix funsheep.validation.resweep --course ID  # one course only

  Prints the per-course enqueue counts so the operator can eyeball scope
  before and after.
  """

  use Mix.Task

  import Ecto.Query

  alias FunSheep.Questions
  alias FunSheep.Questions.Question
  alias FunSheep.Repo

  @switches [course: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    course_ids =
      case opts[:course] do
        nil ->
          from(q in Question,
            where: q.validation_status == :pending,
            distinct: true,
            select: q.course_id
          )
          |> Repo.all()

        id ->
          [id]
      end

    if course_ids == [] do
      Mix.shell().info("No courses with :pending questions. Nothing to do.")
    else
      Mix.shell().info("Courses to re-enqueue: #{length(course_ids)}")

      total =
        Enum.reduce(course_ids, 0, fn id, acc ->
          {:ok, n} = Questions.requeue_pending_validations(id)
          Mix.shell().info("  #{id}: #{n} re-enqueued")
          acc + n
        end)

      Mix.shell().info("Total re-enqueued: #{total}")
    end
  end
end
