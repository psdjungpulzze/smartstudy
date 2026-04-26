defmodule FunSheep.Workers.SectionRegenerationWorker do
  @moduledoc """
  Oban worker that regenerates granular concept sections for a chapter.

  After CourseDiscoveryWorker ran, many chapters had no sections, so
  QuestionClassificationWorker fell back to `ensure_default_section/1`
  which created a single "Overview" section per chapter. That leaves all
  questions lumped in one bucket — per-concept readiness is meaningless.

  This worker:
    1. Skips chapters that already have >= 4 non-default sections
       (already well-structured).
    2. Calls the AI with the chapter name + course context to generate
       5–10 specific concept sections.
    3. Creates the new sections in DB.
    4. Resets any questions in the old "Overview" section to
       `:uncategorized` so QuestionClassificationWorker re-classifies them
       against the new granular sections.
    5. Deletes the "Overview" section once its questions are untagged.
    6. Enqueues QuestionClassificationWorker for the chapter.
  """

  use Oban.Worker,
    queue: :ai,
    max_attempts: 3,
    unique: [
      period: 300,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias FunSheep.{Courses, Repo}
  alias FunSheep.Questions.Question
  alias FunSheep.Workers.QuestionClassificationWorker

  import Ecto.Query
  require Logger

  @system_prompt "You are an expert curriculum designer. Given a chapter name and course context, list the specific concepts/sections that belong in that chapter. Return ONLY a JSON array of section names, ordered as they appear in a standard textbook. Be specific and granular — each name should identify one distinct concept a student needs to master."

  @llm_opts %{
    model: "gpt-4o-mini",
    max_tokens: 600,
    temperature: 0.2,
    source: "section_regeneration_worker"
  }

  # Skip if a chapter already has at least this many non-default sections.
  @min_sections_to_skip 4

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"chapter_id" => chapter_id}}) do
    chapter = Courses.get_chapter!(chapter_id)
    course = Courses.get_course!(chapter.course_id)
    existing = Courses.list_sections_by_chapter(chapter_id)

    if already_structured?(existing) do
      Logger.info("[SectionRegen] Skip #{chapter.name} — #{length(existing)} sections already")
      :ok
    else
      Logger.info("[SectionRegen] Regenerating: #{chapter.name}")
      prompt = build_prompt(chapter, course)

      case ai_client().call(@system_prompt, prompt, @llm_opts) do
        {:ok, response} ->
          case parse_section_names(response) do
            {:ok, names} when length(names) >= 2 ->
              apply_new_sections(chapter_id, names, existing)

            {:ok, names} ->
              Logger.warning(
                "[SectionRegen] Too few sections (#{length(names)}) for #{chapter.name}"
              )

              :ok

            {:error, reason} ->
              Logger.error("[SectionRegen] Parse failed for #{chapter.name}: #{inspect(reason)}")
              {:error, :parse_failed}
          end

        {:error, reason} ->
          Logger.error("[SectionRegen] AI call failed for #{chapter.name}: #{inspect(reason)}")
          {:error, :ai_unavailable}
      end
    end
  end

  @doc "Enqueue one job per chapter in a course. Returns {:ok, chapter_count}."
  def enqueue_for_course(course_id) when is_binary(course_id) do
    chapters = Courses.list_chapters_by_course(course_id)

    Enum.each(chapters, fn ch ->
      %{"chapter_id" => ch.id} |> new() |> Oban.insert()
    end)

    {:ok, length(chapters)}
  end

  # --- Private ---

  defp already_structured?(sections) do
    non_default = Enum.reject(sections, &default_section?/1)
    length(non_default) >= @min_sections_to_skip
  end

  defp default_section?(%{name: name}), do: name in ["Overview", ""]

  defp build_prompt(chapter, course) do
    textbook =
      case course.custom_textbook_name do
        nil -> ""
        name -> "\nTextbook: #{name}"
      end

    """
    Course: #{course.subject}, Grade #{Enum.join(course.grades || [], ", ")}#{textbook}
    Chapter: #{chapter.name}

    List 5-10 specific concepts or sections that belong in this chapter.
    Each concept should be a distinct, testable topic a student needs to master.

    Example format for a "Cell Structure" chapter:
    ["Cell Theory and History", "Prokaryotic vs. Eukaryotic Cells", "Cell Membrane Structure",
     "Nucleus and Genetic Material", "Mitochondria and Energy Production",
     "Endoplasmic Reticulum and Golgi Apparatus", "Cytoskeleton and Cell Movement"]

    Return ONLY a JSON array of strings. No other text.
    """
  end

  defp parse_section_names(text) when is_binary(text) do
    cleaned =
      text
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case try_decode(cleaned) do
      {:ok, _} = ok ->
        ok

      {:error, _} ->
        case Regex.run(~r/\[[\s\S]*\]/m, text) do
          [match] -> try_decode(match)
          _ -> {:error, :no_json_array}
        end
    end
  end

  defp try_decode(str) do
    case Jason.decode(str) do
      {:ok, names} when is_list(names) ->
        valid =
          names
          |> Enum.filter(&is_binary/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        {:ok, valid}

      _ ->
        {:error, :bad_json}
    end
  end

  defp apply_new_sections(chapter_id, names, existing) do
    overview = Enum.find(existing, &default_section?/1)

    names
    |> Enum.with_index(1)
    |> Enum.each(fn {name, pos} ->
      Courses.create_section(%{name: name, position: pos, chapter_id: chapter_id})
    end)

    Logger.info("[SectionRegen] Created #{length(names)} sections for chapter #{chapter_id}")

    if overview do
      {count, _} =
        from(q in Question, where: q.section_id == ^overview.id)
        |> Repo.update_all(
          set: [
            section_id: nil,
            classification_status: :uncategorized,
            classification_confidence: nil
          ]
        )

      Logger.info(
        "[SectionRegen] Reset #{count} questions from Overview in chapter #{chapter_id}"
      )

      Repo.delete(overview)
    end

    QuestionClassificationWorker.enqueue_for_chapter(chapter_id)
    :ok
  end

  defp ai_client, do: Application.get_env(:fun_sheep, :ai_client_impl, FunSheep.AI.Client)
end
