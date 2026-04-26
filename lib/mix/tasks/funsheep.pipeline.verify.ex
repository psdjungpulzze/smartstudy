defmodule Mix.Tasks.Funsheep.Pipeline.Verify do
  @shortdoc "Runs the three-criteria pipeline health check for a course"

  @moduledoc """
  Verifies the web question extraction pipeline for a given course against the
  three testable criteria defined in the ROADMAP:

    1. **Reputable sources** — at least 5 DiscoveredSources with `discovery_strategy`
       of "registry" (from Tier 1–2 curated entries), OR at least 10 sources total.
    2. **Not fabrication** — every web_scraped question has a non-empty `source_url`
       pointing to a real DiscoveredSource that exists for the same course.
    3. **Volume** — at least 100 web_scraped questions with `validation_status: :passed`.

  ## Usage

      mix funsheep.pipeline.verify COURSE_ID
      mix funsheep.pipeline.verify COURSE_ID --min-questions 500

  ## Exit codes

    0 — all criteria passed
    1 — one or more criteria failed

  ## Example output

      Course: SAT Math Prep (ID: abc-123)
      ✓ PASS  Criterion 1 — Reputable sources: 8 registry sources (≥ 5 required)
      ✓ PASS  Criterion 2 — Not fabrication: 0 questions without a valid source URL
      ✗ FAIL  Criterion 3 — Volume: 42 passed questions (< 100 required)

      1/3 criteria failed.
  """

  use Mix.Task

  import Ecto.Query

  alias FunSheep.{Repo, Courses}
  alias FunSheep.Content.DiscoveredSource
  alias FunSheep.Questions.Question

  @switches [min_questions: :integer]
  @aliases [q: :min_questions]

  @default_min_questions 100

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)
    min_questions = Keyword.get(opts, :min_questions, @default_min_questions)

    course_id =
      case positional do
        [id | _] -> id
        [] -> Mix.raise("Usage: mix funsheep.pipeline.verify COURSE_ID")
      end

    course = Courses.get_course!(course_id)
    Mix.shell().info("\nCourse: #{course.name} (ID: #{course_id})")
    Mix.shell().info(String.duplicate("─", 60))

    results = [
      check_reputable_sources(course_id),
      check_not_fabrication(course_id),
      check_volume(course_id, min_questions)
    ]

    passed = Enum.count(results, & &1)
    failed = length(results) - passed

    Mix.shell().info("")

    if failed == 0 do
      Mix.shell().info("#{passed}/#{length(results)} criteria passed. Pipeline healthy.")
    else
      Mix.shell().error("#{failed}/#{length(results)} criteria failed.")
      System.halt(1)
    end
  end

  defp check_reputable_sources(course_id) do
    registry_count =
      from(ds in DiscoveredSource,
        where: ds.course_id == ^course_id and ds.discovery_strategy == "registry"
      )
      |> Repo.aggregate(:count)

    total_count =
      from(ds in DiscoveredSource, where: ds.course_id == ^course_id)
      |> Repo.aggregate(:count)

    passed = registry_count >= 5 or total_count >= 10

    label =
      "Criterion 1 — Reputable sources: #{registry_count} registry sources, #{total_count} total"

    print_result(passed, label, "≥ 5 registry or ≥ 10 total required")
    passed
  end

  defp check_not_fabrication(course_id) do
    orphan_count =
      from(q in Question,
        left_join: ds in DiscoveredSource,
        on: ds.course_id == q.course_id and ds.url == q.source_url,
        where:
          q.course_id == ^course_id and
            q.source_type == :web_scraped and
            (is_nil(q.source_url) or is_nil(ds.id))
      )
      |> Repo.aggregate(:count)

    passed = orphan_count == 0
    label = "Criterion 2 — Not fabrication: #{orphan_count} questions without a valid source URL"
    print_result(passed, label, "0 orphan questions required")
    passed
  end

  defp check_volume(course_id, min_questions) do
    passed_count =
      from(q in Question,
        where:
          q.course_id == ^course_id and
            q.source_type == :web_scraped and
            q.validation_status == :passed
      )
      |> Repo.aggregate(:count)

    passed = passed_count >= min_questions
    label = "Criterion 3 — Volume: #{passed_count} passed questions"
    print_result(passed, label, "≥ #{min_questions} required")
    passed
  end

  defp print_result(true, label, _requirement) do
    Mix.shell().info("✓ PASS  #{label}")
  end

  defp print_result(false, label, requirement) do
    Mix.shell().error("✗ FAIL  #{label} (#{requirement})")
  end
end
