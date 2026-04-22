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

  use Oban.Worker,
    queue: :ai,
    max_attempts: 60,
    unique: [
      period: 600,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable]
    ]

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

  # Only textbook-like materials define course structure. Sample questions,
  # lecture notes, and syllabi should not drive chapter discovery — they'd
  # pollute the table of contents with unrelated headings.
  @structure_kinds [:textbook, :supplementary_book]

  # How many front pages per textbook material to treat as likely-TOC.
  # Textbooks usually put the table of contents in the first 5–20 pages.
  @toc_front_pages 25

  # Characters of text fed to the AI. gpt-4o supports 128k tokens; 80k
  # characters (~20k tokens) is generous without bloating latency or cost.
  @prompt_char_budget 80_000

  # Matches lines that look like chapter/unit/module headings. Used to surface
  # the table of contents from deep inside the book when the front-matter pages
  # don't contain it.
  @heading_pattern ~r/^\s*(chapter|unit|module|part)\s+[\dIVXLC]+\b.*$/im

  defp collect_ocr_text(course_id) do
    materials = Content.list_materials_by_course(course_id)

    completed =
      Enum.filter(materials, fn m ->
        m.ocr_status == :completed and m.material_kind in @structure_kinds
      end)

    completed
    |> Enum.map(&build_material_snippet/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n===== NEXT MATERIAL =====\n\n")
  end

  # For one textbook material, return:
  #   1. Full OCR text of the first N pages (TOC usually lives here)
  #   2. Every line across the full book matching a chapter-heading pattern
  # Joined together with section markers. This captures the real structure
  # even on books where the TOC is missing or OCR'd poorly.
  defp build_material_snippet(material) do
    pages =
      Content.list_ocr_pages_by_material(material.id)
      |> Enum.sort_by(& &1.page_number)

    front =
      pages
      |> Enum.take(@toc_front_pages)
      |> Enum.map(& &1.extracted_text)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n---PAGE BREAK---\n\n")

    heading_lines =
      pages
      |> Enum.drop(@toc_front_pages)
      |> Enum.flat_map(fn page ->
        (page.extracted_text || "")
        |> String.split("\n")
        |> Enum.filter(&Regex.match?(@heading_pattern, &1))
        |> Enum.map(&String.trim/1)
      end)
      |> Enum.uniq()

    headings_block =
      case heading_lines do
        [] -> ""
        lines -> "\n\n--- HEADINGS FOUND ELSEWHERE IN BOOK ---\n" <> Enum.join(lines, "\n")
      end

    (front <> headings_block) |> String.trim()
  end

  defp discover_chapters_from_materials(course, ocr_text) do
    subject = course.subject
    grade = course.grade

    truncated_text =
      if String.length(ocr_text) > @prompt_char_budget do
        String.slice(ocr_text, 0, @prompt_char_budget) <> "\n\n[... text truncated ...]"
      else
        ocr_text
      end

    prompt = """
    You are analyzing uploaded textbook pages for a #{subject} (Grade #{grade}) course.

    Below is text extracted from the uploaded materials: the full first few
    pages (where the table of contents usually lives), followed by every
    chapter/unit/module heading found elsewhere in the book.

    Use this to identify the COMPLETE, ACTUAL chapter and section structure
    of the textbook.

    IMPORTANT:
    - Extract the REAL chapter/section names from the text. Do NOT make up
      generic names.
    - Include EVERY chapter present in the text. Do not stop at 10, 20, or 30.
      A typical textbook has 20–50 chapters — return all of them.
    - If the table of contents lists chapters, use that as the primary source.
    - If the text only contains heading lines, infer the chapter list from
      those headings.
    - Preserve the original chapter numbering and capitalization.

    Look for:
    - Table of contents entries
    - Chapter headings (e.g., "Chapter 1:", "Unit 1:", "Module 1:")
    - Section headings (e.g., "1.1", "Section 1.1", numbered subsections)
    - Part/unit divisions

    === UPLOADED TEXT ===
    #{truncated_text}
    === END TEXT ===

    Return a JSON array of chapters. Each chapter should have a "name" and
    optionally "sections" (array of section names). Use the EXACT names from
    the textbook.

    Example format:
    [
      {"name": "Chapter 1: The Science of Biology", "sections": ["1.1 What is Science?", "1.2 The Nature of Science"]},
      {"name": "Chapter 2: The Chemistry of Life", "sections": ["2.1 The Nature of Matter", "2.2 Properties of Water"]}
    ]

    Return ONLY the JSON array, no other text.
    """

    case Agents.chat("course_discovery", prompt, %{
           source: "enrich_discovery_worker",
           metadata: %{
             course_id: course.id,
             subject: subject,
             grade: grade,
             origin: "textbook_ocr"
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
