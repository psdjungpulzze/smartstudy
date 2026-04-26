defmodule FunSheep.Courses.CourseBuilder do
  @moduledoc """
  Runtime course creation from a JSON spec.

  Used by both `Mix.Tasks.Funsheep.Course.Create` and the admin
  `AdminTestCourseBuilderLive`. All DB writes go through `FunSheep.Repo`
  inside a single transaction so a partial failure rolls back cleanly.

  ## Spec format

  See `.claude/commands/course-create.md` for the full JSON spec format.
  """

  alias FunSheep.Repo
  alias FunSheep.Courses.{Course, Chapter, Section, CourseBundle}
  alias FunSheep.Assessments.TestFormatTemplate

  import Ecto.Query

  require Logger

  @required_spec_keys ~w(name test_type subject grades chapters)

  # --- Public API -----------------------------------------------------------

  @doc """
  Parses a JSON string into a validated spec map.
  Returns `{:ok, spec}` or `{:error, reason}`.
  """
  @spec parse_spec(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse_spec(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, spec} when is_map(spec) -> validate_spec(spec)
      {:ok, _} -> {:error, "Spec must be a JSON object, not an array or scalar"}
      {:error, err} -> {:error, "Invalid JSON: #{Exception.message(err)}"}
    end
  end

  @doc """
  Validates a decoded spec map.
  Returns `{:ok, spec}` or `{:error, reason_string}`.
  """
  @spec validate_spec(map()) :: {:ok, map()} | {:error, String.t()}
  def validate_spec(spec) when is_map(spec) do
    missing = Enum.reject(@required_spec_keys, &Map.has_key?(spec, &1))

    cond do
      missing != [] ->
        {:error, "Missing required fields: #{Enum.join(missing, ", ")}"}

      not is_list(spec["chapters"]) ->
        {:error, "\"chapters\" must be a JSON array"}

      not is_list(spec["grades"]) ->
        {:error, "\"grades\" must be a JSON array of strings"}

      true ->
        {:ok, spec}
    end
  end

  @doc """
  Returns a lightweight preview of what `create_from_spec/1` would create,
  without touching the DB.
  """
  @spec preview_spec(map()) :: map()
  def preview_spec(spec) when is_map(spec) do
    chapters = spec["chapters"] || []

    %{
      name: spec["name"],
      test_type: spec["test_type"],
      subject: spec["subject"],
      chapter_count: length(chapters),
      chapters:
        Enum.map(chapters, fn ch ->
          %{name: ch["name"], section_count: length(ch["sections"] || [])}
        end),
      total_sections:
        Enum.reduce(chapters, 0, fn ch, acc -> acc + length(ch["sections"] || []) end),
      has_exam_simulation: not is_nil(spec["exam_simulation"]),
      has_bundle: not is_nil(spec["bundle"]),
      price_cents: spec["price_cents"]
    }
  end

  @doc """
  Creates a full course structure from a validated spec map inside a single
  DB transaction.

  Returns `{:ok, %{course: course, chapters: [{chapter, [section]}], template: template_or_nil, bundle: bundle_or_nil}}`
  or `{:error, reason}`.

  Idempotent — existing records are skipped rather than duplicated.
  """
  @spec create_from_spec(map()) :: {:ok, map()} | {:error, term()}
  def create_from_spec(spec) when is_map(spec) do
    Repo.transaction(fn ->
      course = find_or_create_course!(spec)
      chapters = create_chapters!(course, spec["chapters"] || [])
      template = maybe_create_format_template!(course, spec["exam_simulation"])
      bundle = maybe_create_bundle!(spec["bundle"], course)
      %{course: course, chapters: chapters, template: template, bundle: bundle}
    end)
  end

  # --- Course creation ------------------------------------------------------

  defp find_or_create_course!(spec) do
    test_type = spec["test_type"]
    name = spec["name"]

    existing =
      Repo.one(
        from c in Course,
          where: c.catalog_test_type == ^test_type and c.name == ^name
      )

    if existing do
      Logger.info("[CourseBuilder] Course already exists: #{name} (#{existing.id})")
      # Update metadata so score_predictor_weights and generation_config are
      # always current even if the course already existed.
      updated_metadata = build_metadata(existing.metadata, spec)

      {:ok, updated} =
        existing
        |> Course.changeset(%{metadata: updated_metadata})
        |> Repo.update()

      updated
    else
      attrs = %{
        name: name,
        subject: spec["subject"],
        grades: spec["grades"] || [],
        description: spec["description"] || "",
        catalog_test_type: test_type,
        catalog_subject: spec["catalog_subject"] || spec["subject"],
        catalog_level: spec["catalog_level"] || "full_section",
        is_premium_catalog: true,
        access_level: "premium",
        processing_status: "pending",
        price_cents: spec["price_cents"],
        currency: spec["currency"] || "usd",
        price_label: spec["price_label"] || "One-time purchase",
        sample_question_count: spec["sample_question_count"] || 10,
        metadata: build_metadata(%{}, spec)
      }

      %Course{}
      |> Course.changeset(attrs)
      |> Repo.insert!()
    end
  end

  defp build_metadata(existing_meta, spec) do
    extra =
      %{}
      |> maybe_put_meta("generation_config", spec["generation_config"])
      |> maybe_put_meta("score_predictor_weights", spec["score_predictor_weights"])
      |> maybe_put_meta("score_range", spec["score_range"])

    Map.merge(existing_meta || %{}, extra)
  end

  defp maybe_put_meta(map, _key, nil), do: map
  defp maybe_put_meta(map, key, value), do: Map.put(map, key, value)

  # --- Chapter + Section creation -------------------------------------------

  defp create_chapters!(course, chapters_spec) do
    chapters_spec
    |> Enum.with_index()
    |> Enum.map(fn {ch_spec, pos} ->
      chapter = find_or_create_chapter!(course, ch_spec["name"], pos)
      sections = create_sections!(chapter, ch_spec["sections"] || [])
      {chapter, sections}
    end)
  end

  defp find_or_create_chapter!(course, name, position) do
    existing =
      Repo.one(
        from ch in Chapter,
          where: ch.course_id == ^course.id and ch.name == ^name
      )

    if existing do
      existing
    else
      %Chapter{}
      |> Chapter.changeset(%{course_id: course.id, name: name, position: position})
      |> Repo.insert!()
    end
  end

  defp create_sections!(chapter, section_names) do
    section_names
    |> Enum.with_index()
    |> Enum.map(fn {section_name, pos} ->
      find_or_create_section!(chapter, section_name, pos)
    end)
  end

  defp find_or_create_section!(chapter, name, position) do
    existing =
      Repo.one(
        from s in Section,
          where: s.chapter_id == ^chapter.id and s.name == ^name
      )

    if existing do
      existing
    else
      %Section{}
      |> Section.changeset(%{chapter_id: chapter.id, name: name, position: position})
      |> Repo.insert!()
    end
  end

  # --- TestFormatTemplate creation ------------------------------------------

  defp maybe_create_format_template!(_course, nil), do: nil

  defp maybe_create_format_template!(course, exam_simulation) do
    template_name = "#{course.name} — Full Exam"

    existing =
      Repo.one(
        from t in TestFormatTemplate,
          where: t.course_id == ^course.id and t.name == ^template_name
      )

    if existing do
      existing
    else
      structure = %{
        "time_limit_minutes" => exam_simulation["time_limit_minutes"],
        "sections" =>
          Enum.map(exam_simulation["sections"] || [], fn s ->
            %{
              "name" => s["name"],
              "question_type" => s["question_type"] || "multiple_choice",
              "count" => s["count"],
              "time_limit_minutes" => s["time_limit_minutes"],
              "chapter_ids" => []
            }
          end)
      }

      %TestFormatTemplate{}
      |> TestFormatTemplate.changeset(%{
        course_id: course.id,
        name: template_name,
        structure: structure
      })
      |> Repo.insert!()
    end
  end

  # --- CourseBundle creation -------------------------------------------------

  defp maybe_create_bundle!(nil, _course), do: nil

  defp maybe_create_bundle!(bundle_spec, _course) do
    bundle_name = bundle_spec["name"]

    existing = Repo.one(from b in CourseBundle, where: b.name == ^bundle_name)

    if existing do
      Logger.info("[CourseBuilder] Bundle already exists: #{bundle_name}")
      existing
    else
      # Resolve course names → IDs
      course_names = bundle_spec["course_names"] || []

      course_ids =
        Enum.map(course_names, fn name ->
          case Repo.one(from c in Course, where: c.name == ^name, select: c.id) do
            nil ->
              Repo.rollback("Bundle references unknown course: \"#{name}\"")

            id ->
              id
          end
        end)

      %CourseBundle{}
      |> CourseBundle.changeset(%{
        name: bundle_name,
        description: bundle_spec["description"] || "",
        price_cents: bundle_spec["price_cents"],
        currency: bundle_spec["currency"] || "usd",
        course_ids: course_ids,
        is_active: true,
        catalog_test_type: infer_test_type(course_names)
      })
      |> Repo.insert!()
    end
  end

  defp infer_test_type([first_name | _rest]) do
    # Best-effort: extract the test type from the first course name
    first_name
    |> String.downcase()
    |> String.split(" ")
    |> List.first("")
    |> String.trim()
  end

  defp infer_test_type([]), do: nil
end
