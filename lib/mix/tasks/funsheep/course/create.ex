defmodule Mix.Tasks.Funsheep.Course.Create do
  @shortdoc "Create a standardized test course from a JSON spec"

  @moduledoc """
  Creates a test course (chapters, sections, TestFormatTemplate, CourseBundle)
  from a JSON spec. Idempotent — safe to run multiple times; existing records
  are skipped rather than duplicated.

  ## Usage

      mix funsheep.course.create --spec '<json>'
      mix funsheep.course.create --file path/to/spec.json

  ## COURSE_SPEC format

  See `.claude/commands/course-create.md` for the full JSON spec format and
  field documentation.

  ## Examples

      mix funsheep.course.create --spec '{"name":"ACT Math","test_type":"act","subject":"mathematics","grades":["10","11","12","College"],"description":"ACT Math prep","price_cents":2900,"chapters":[{"name":"Pre-Algebra","sections":["Number Theory","Fractions"]}],"exam_simulation":{"time_limit_minutes":60,"sections":[{"name":"Math","question_type":"multiple_choice","count":60,"time_limit_minutes":60}]}}'
  """

  use Mix.Task

  @requirements ["app.start"]

  alias FunSheep.Courses.CourseBuilder

  @switches [spec: :string, file: :string]

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    json =
      cond do
        spec = opts[:spec] ->
          spec

        file = opts[:file] ->
          case File.read(file) do
            {:ok, contents} -> contents
            {:error, reason} -> Mix.raise("Could not read file #{file}: #{inspect(reason)}")
          end

        true ->
          Mix.raise("Pass --spec '<json>' or --file <path>")
      end

    case CourseBuilder.parse_spec(json) do
      {:ok, spec} ->
        Mix.shell().info("Creating course: #{spec["name"]}...")

        case CourseBuilder.create_from_spec(spec) do
          {:ok, result} ->
            print_summary(result)

          {:error, reason} ->
            Mix.shell().error("Failed to create course: #{inspect(reason)}")
            System.halt(1)
        end

      {:error, reason} ->
        Mix.shell().error("Invalid spec: #{reason}")
        System.halt(1)
    end
  end

  defp print_summary(%{course: course, chapters: chapters, template: template, bundle: bundle}) do
    section_count =
      Enum.reduce(chapters, 0, fn {_ch, sections}, acc -> acc + length(sections) end)

    Mix.shell().info("""

    ✓ Course: #{course.name} (#{course.id})
      Test type: #{course.catalog_test_type}
      Subject: #{course.subject}
      Chapters: #{length(chapters)} | Sections: #{section_count}
      Processing status: #{course.processing_status}
      Price: #{format_price(course.price_cents, course.currency)}
    """)

    if template do
      Mix.shell().info("  ✓ Exam template: #{template.name}")
    end

    if bundle do
      Mix.shell().info("  ✓ Bundle: #{bundle.name} (#{bundle.id})")
    end

    Mix.shell().info("""
    Next: visit /admin/course-builder to generate questions and publish.
    """)
  end

  defp format_price(nil, _), do: "free"

  defp format_price(cents, currency),
    do:
      "$#{div(cents, 100)}.#{rem(cents, 100) |> to_string() |> String.pad_leading(2, "0")} #{String.upcase(currency || "usd")}"
end
