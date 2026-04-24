defmodule Mix.Tasks.Funsheep.Courses.RetryFailed do
  @shortdoc "One-off: reprocess a specific list of failed courses"

  @moduledoc """
  Reprocess one or more courses that are stuck in `:failed` or
  indefinitely-`:pending` state. Delegates to
  `FunSheep.Courses.reprocess_course/1`, which deletes any existing
  chapters/questions/OCR pages, resets materials to `:pending`, and
  re-enqueues `ProcessCourseWorker`.

  Used 2026-04-24 to retry the 4 AP Biology courses that failed on
  2026-04-20 during a transient Interactor chapter-discovery outage.

  ## Usage

      mix funsheep.courses.retry_failed --prod-db \\
          --course 6dc1b6cb-... --course c8638228-... --confirm

      # Dry-run: just prints what would be done
      mix funsheep.courses.retry_failed --prod-db --course ...

  Pass `--course` multiple times for multiple IDs.
  """

  use Mix.Task

  alias FunSheep.Courses

  @switches [course: :keep, confirm: :boolean, prod_db: :boolean]

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    if Keyword.get(opts, :prod_db, false) do
      db_url =
        System.get_env("DATABASE_URL") ||
          Mix.raise("--prod-db requires DATABASE_URL env var")

      Application.put_env(:fun_sheep, FunSheep.Repo,
        url: db_url,
        pool_size: 5,
        ssl: false,
        socket_options: []
      )
    end

    Mix.Task.run("app.start")

    dry_run? = not Keyword.get(opts, :confirm, false)

    course_ids =
      opts
      |> Keyword.get_values(:course)
      |> Enum.reject(&(&1 in [nil, ""]))

    if course_ids == [] do
      Mix.raise("Pass at least one --course <id>")
    end

    Mix.shell().info(
      "\n=== RETRY FAILED COURSES (#{if dry_run?, do: "DRY-RUN", else: "CONFIRMED"}) ==="
    )

    Enum.each(course_ids, fn id ->
      try do
        course = Courses.get_course!(id)

        Mix.shell().info("  [#{id}] #{course.name} / status=#{course.processing_status}")

        if not dry_run? do
          case Courses.reprocess_course(id) do
            {:ok, _} ->
              Mix.shell().info("      → reprocess_course enqueued")

            err ->
              Mix.shell().info("      → ERROR: #{inspect(err)}")
          end
        end
      rescue
        Ecto.NoResultsError ->
          Mix.shell().info("  [#{id}] NOT FOUND, skipping")
      end
    end)

    if dry_run?, do: Mix.shell().info("\n(dry-run — pass --confirm to retry)")
  end
end
