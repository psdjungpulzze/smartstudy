defmodule Mix.Tasks.Toc.Rebase do
  @moduledoc """
  Manually kick a TOC rediscovery for a course.

  Useful for courses that were created BEFORE TOC-rebasing existed (so
  the web-discovered 16 chapters got locked in) and never had their
  textbook upload re-processed.

  Enqueues `EnrichDiscoveryWorker` for the given course. The worker
  runs normally: collects OCR, runs AI discovery, proposes a new TOC
  through `Courses.TOCRebase`, and applies it non-destructively.

  ## Usage

      mix toc.rebase d44628ca-6579-48da-a83b-466e12b1c19b

      # Inspect only — dry-run. Shows current vs candidate without applying.
      mix toc.rebase d44628ca-6579-48da-a83b-466e12b1c19b --dry-run

  ## In production (Cloud Run)

  Cloud Run doesn't expose a Mix task directly. Either:
  - Run via Cloud Run Jobs (`gcloud run jobs create` with `mix toc.rebase`
    as the command), or
  - Shell into a one-off release: `bin/fun_sheep rpc
    'FunSheep.Workers.EnrichDiscoveryWorker.new(%{course_id: "..."})
    |> Oban.insert()'`
  """

  use Mix.Task

  @shortdoc "Rebase a course's TOC from OCR'd textbook material"

  @impl Mix.Task
  def run([course_id | rest]) do
    Mix.Task.run("app.start")

    dry_run? = "--dry-run" in rest

    case FunSheep.Repo.get(FunSheep.Courses.Course, course_id) do
      nil ->
        Mix.shell().error("Course #{course_id} not found.")
        exit({:shutdown, 1})

      course ->
        current = FunSheep.Courses.TOCRebase.current(course.id)

        Mix.shell().info("Course: #{course.name} (#{course.id})")
        Mix.shell().info("Current TOC: #{format_toc(current)}")

        if dry_run? do
          Mix.shell().info("--dry-run: not enqueuing. Use without --dry-run to rediscover.")
        else
          {:ok, _} =
            %{course_id: course.id}
            |> FunSheep.Workers.EnrichDiscoveryWorker.new()
            |> Oban.insert()

          Mix.shell().info("Enqueued EnrichDiscoveryWorker. Watch worker logs.")
        end
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix toc.rebase <course_id> [--dry-run]")
    exit({:shutdown, 1})
  end

  defp format_toc(nil), do: "(none applied yet)"

  defp format_toc(toc) do
    "#{toc.chapter_count} chapters, source=#{toc.source}, score=#{toc.score}"
  end
end
