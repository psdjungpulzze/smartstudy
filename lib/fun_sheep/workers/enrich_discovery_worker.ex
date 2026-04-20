defmodule FunSheep.Workers.EnrichDiscoveryWorker do
  @moduledoc """
  Oban worker that re-discovers course structure after new materials are OCR'd.

  This worker waits for all OCR to complete, then:
    1. Collects all OCR text from the course's materials
    2. Deletes existing chapters/sections (they'll be replaced with textbook-accurate ones)
    3. Runs AI discovery using OCR text as the primary context
    4. Re-generates questions from the enriched content

  Retries with backoff until OCR is complete (max 60 attempts = ~5 minutes).
  """

  use Oban.Worker, queue: :ai, max_attempts: 60

  alias FunSheep.{Content, Courses, Repo}
  alias FunSheep.Courses.{Chapter, Section}
  alias FunSheep.Interactor.Agents

  import Ecto.Query

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"course_id" => course_id}, attempt: attempt}) do
    course = Courses.get_course!(course_id)

    if course.processing_status == "cancelled" do
      :ok
    else
      check_and_proceed(course, attempt)
    end
  end

  defp check_and_proceed(course, attempt) do
    course_id = course.id

    # Check if OCR is done
    ocr_done =
      course.ocr_total_count == 0 or
        course.ocr_completed_count >= course.ocr_total_count

    if ocr_done do
      Logger.info("[EnrichDiscovery] OCR complete, starting re-discovery for #{course_id}")
      run_discovery(course)
    else
      if attempt >= 60 do
        Logger.error("[EnrichDiscovery] OCR timeout for course #{course_id}")

        Courses.update_course(course, %{
          processing_status: "failed",
          processing_step: "Material processing timed out. Try reprocessing."
        })

        :ok
      else
        # Retry in 5 seconds
        {:snooze, 5}
      end
    end
  end

  defp run_discovery(course) do
    course_id = course.id

    broadcast(course_id, %{
      status: "processing",
      step: "Analyzing uploaded materials...",
      sub_step: "Collecting text from uploaded materials..."
    })

    # Collect OCR text from ALL materials (not just new ones)
    ocr_text = collect_ocr_text(course_id)

    if ocr_text == "" do
      Logger.warning("[EnrichDiscovery] No OCR text found for course #{course_id}")
      # Skip re-discovery, go straight to question generation
      trigger_question_generation(course)
      :ok
    else
      # Delete existing chapters — they'll be replaced with textbook-derived ones
      broadcast(course_id, %{sub_step: "Replacing course structure with textbook content..."})

      from(ch in Chapter, where: ch.course_id == ^course_id)
      |> Repo.delete_all()

      # Run AI discovery with OCR text as primary context
      broadcast(course_id, %{sub_step: "Discovering chapters from uploaded textbook..."})

      chapters = discover_chapters_from_materials(course, ocr_text)

      if chapters == [] do
        Logger.error("[EnrichDiscovery] No chapters discovered from materials for #{course_id}")

        Courses.update_course(course, %{
          processing_status: "failed",
          processing_step:
            "Could not identify chapters from uploaded materials. Please try again."
        })

        broadcast(course_id, %{
          status: "failed",
          step: "Could not identify chapters from uploaded materials."
        })

        :ok
      else
        # Create chapters in DB
        broadcast(course_id, %{
          sub_step: "Creating #{length(chapters)} chapters from textbook..."
        })

        create_chapters(chapters, course_id)

        Courses.update_course(course, %{
          processing_step: "Discovered #{length(chapters)} chapters from textbook"
        })

        # Mark discovery complete
        metadata =
          Map.merge(course.metadata || %{}, %{
            "discovery_complete" => true,
            "ocr_complete" => true,
            "enriched_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          })

        Courses.update_course(Courses.get_course!(course_id), %{metadata: metadata})

        broadcast(course_id, %{
          step: "Discovered #{length(chapters)} chapters",
          sub_step: nil
        })

        # Now generate questions
        trigger_question_generation(Courses.get_course!(course_id))

        :ok
      end
    end
  end

  defp collect_ocr_text(course_id) do
    materials = Content.list_materials_by_course(course_id)
    completed = Enum.filter(materials, fn m -> m.ocr_status == :completed end)

    completed
    |> Enum.flat_map(fn mat ->
      Content.list_ocr_pages_by_material(mat.id)
    end)
    |> Enum.sort_by(& &1.page_number)
    |> Enum.map(& &1.extracted_text)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n---PAGE BREAK---\n\n")
  end

  defp discover_chapters_from_materials(course, ocr_text) do
    subject = course.subject
    grade = course.grade

    # Truncate OCR text to avoid token limits (keep first ~15k chars)
    truncated_text =
      if String.length(ocr_text) > 15_000 do
        String.slice(ocr_text, 0, 15_000) <> "\n\n[... text truncated ...]"
      else
        ocr_text
      end

    prompt = """
    You are analyzing uploaded textbook pages for a #{subject} (Grade #{grade}) course.

    Below is the OCR-extracted text from the uploaded materials. Use this to identify the
    actual chapter and section structure of the textbook.

    IMPORTANT: Extract the REAL chapter/section names from the text. Do NOT make up generic names.
    Look for:
    - Table of contents
    - Chapter headings (e.g., "Chapter 1:", "Unit 1:", "Module 1:")
    - Section headings (e.g., "1.1", "Section 1.1", bold/numbered subsections)
    - Part/unit divisions

    If the text contains a table of contents, use that as the primary source.
    If not, identify chapters from heading patterns in the body text.

    === UPLOADED TEXT ===
    #{truncated_text}
    === END TEXT ===

    Return a JSON array of chapters. Each chapter should have a "name" and optionally "sections"
    (array of section names). Use the EXACT names from the textbook.

    Example format:
    [
      {"name": "Chapter 1: The Science of Biology", "sections": ["1.1 What is Science?", "1.2 The Nature of Science"]},
      {"name": "Chapter 2: The Chemistry of Life", "sections": ["2.1 The Nature of Matter", "2.2 Properties of Water"]}
    ]

    Return ONLY the JSON array, no other text.
    """

    case Agents.chat("course_discovery", prompt, %{
           metadata: %{
             course_id: course.id,
             subject: subject,
             grade: grade,
             source: "textbook_ocr"
           }
         }) do
      {:ok, response} ->
        case parse_chapters_json(response) do
          {:ok, chapters} ->
            Logger.info(
              "[EnrichDiscovery] Discovered #{length(chapters)} chapters from textbook for #{course.id}"
            )

            chapters

          {:error, reason} ->
            Logger.error("[EnrichDiscovery] Failed to parse: #{inspect(reason)}")
            []
        end

      {:error, reason} ->
        Logger.error("[EnrichDiscovery] AI discovery failed: #{inspect(reason)}")
        []
    end
  end

  defp parse_chapters_json(content) do
    json_str =
      case Regex.run(~r/\[[\s\S]*\]/m, content) do
        [match] -> match
        _ -> content
      end

    case Jason.decode(json_str) do
      {:ok, chapters} when is_list(chapters) ->
        parsed =
          Enum.map(chapters, fn ch ->
            %{
              name: ch["name"] || "Unnamed Chapter",
              sections: (ch["sections"] || []) |> Enum.map(&to_string/1)
            }
          end)

        {:ok, parsed}

      _ ->
        {:error, :invalid_json}
    end
  end

  defp create_chapters(chapters, course_id) do
    chapters
    |> Enum.with_index(1)
    |> Enum.each(fn {chapter_data, position} ->
      {:ok, chapter} =
        %Chapter{}
        |> Chapter.changeset(%{name: chapter_data.name, position: position, course_id: course_id})
        |> Repo.insert()

      if chapter_data[:sections] && chapter_data.sections != [] do
        chapter_data.sections
        |> Enum.with_index(1)
        |> Enum.each(fn {section_name, sec_pos} ->
          %Section{}
          |> Section.changeset(%{
            name: section_name,
            position: sec_pos,
            chapter_id: chapter.id
          })
          |> Repo.insert()
        end)
      end
    end)
  end

  defp trigger_question_generation(course) do
    course_id = course.id

    Courses.update_course(course, %{
      processing_status: "extracting",
      processing_step: "Extracting and generating questions from textbook...",
      metadata:
        Map.merge(course.metadata || %{}, %{
          "discovery_complete" => true,
          "ocr_complete" => true
        })
    })

    broadcast(course_id, %{
      status: "extracting",
      step: "Extracting and generating questions from textbook..."
    })

    %{course_id: course_id}
    |> FunSheep.Workers.QuestionExtractionWorker.new()
    |> Oban.insert()
  end

  defp broadcast(course_id, data) do
    Phoenix.PubSub.broadcast(FunSheep.PubSub, "course:#{course_id}", {:processing_update, data})
  end
end
