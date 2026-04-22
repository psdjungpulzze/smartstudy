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

  alias FunSheep.{Content, Courses}
  alias FunSheep.Courses.TOCRebase
  alias FunSheep.Interactor.Agents

  require Logger

  # Only textbook-like materials define course structure. Defined here so
  # both the source-label helper and the OCR-text collector can see it —
  # module attributes must be set before their first reference.
  @structure_kinds [:textbook, :supplementary_book]

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
      # Run AI discovery with OCR text as primary context.
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
        # Record the discovery as a candidate TOC. TOCRebase.compare/2
        # then decides whether it's worth applying (beats the
        # improvement gate AND doesn't orphan too many active
        # chapters). The "join-not-replace" apply/2 preserves any
        # chapter that already carries student attempts.
        apply_discovery(course, chapters, ocr_text)
      end
    end
  end

  defp apply_discovery(course, chapters, ocr_text) do
    course_id = course.id
    source = source_label(course, chapters)
    uploader_id = infer_uploader_id(course_id)

    {:ok, new_toc} =
      TOCRebase.propose(course_id, source, %{
        chapters: stringify_chapters(chapters),
        ocr_char_count: String.length(ocr_text)
      })

    current = TOCRebase.current(course_id)

    case TOCRebase.decide_action(new_toc, current, uploader_id) do
      :auto_apply ->
        broadcast(course_id, %{sub_step: "Rebasing course onto discovered textbook structure..."})
        run_apply(course_id, new_toc, source, length(chapters))

      {:pending, reason} ->
        {:ok, _} =
          Courses.get_course!(course_id)
          |> TOCRebase.mark_pending(new_toc, uploader_id)

        Logger.info(
          "[EnrichDiscovery] TOC candidate pending for #{course_id}: #{reason} " <>
            "(score=#{new_toc.score} vs current=#{current && current.score})"
        )

        broadcast(course_id, %{
          pending_toc: %{reason: reason, new_chapter_count: new_toc.chapter_count}
        })

        # Leave the current TOC in place — don't touch chapters. The
        # course processing still "completes" so the student can keep
        # using what's there; the banner will invite approval.
        mark_discovery_complete(
          Courses.get_course!(course_id),
          (current && current.chapter_count) || length(chapters)
        )

      :no_change ->
        Logger.info(
          "[EnrichDiscovery] TOC candidate kept (no-op) for #{course_id}: " <>
            "score=#{new_toc.score} vs current=#{current && current.score}"
        )

        mark_discovery_complete(
          Courses.get_course!(course_id),
          (current && current.chapter_count) || length(chapters)
        )
    end

    :ok
  end

  defp run_apply(course_id, new_toc, source, chapter_count) do
    case TOCRebase.apply(new_toc, course_id) do
      {:ok, stats} ->
        Logger.info(
          "[EnrichDiscovery] Auto-applied #{course_id}: #{stats.kept} kept, " <>
            "#{stats.created} created, #{stats.orphaned} orphaned, " <>
            "#{stats.deleted} deleted (source=#{source})"
        )

        # Eagerly generate questions for brand-new chapters so students
        # don't hit empty topics. Preserved chapters keep their existing
        # questions — skip them to avoid redundant generation.
        enqueue_per_chapter_generation(course_id, stats.new_chapter_ids)

        mark_discovery_complete(Courses.get_course!(course_id), chapter_count)

      {:error, reason} ->
        Logger.error("[EnrichDiscovery] TOC rebase failed for #{course_id}: #{inspect(reason)}")

        Courses.update_course(Courses.get_course!(course_id), %{
          processing_status: "failed",
          processing_step: "Could not restructure chapters. Please try again."
        })
    end
  end

  # Best-effort: the most recent uploaded material's user_role is our
  # proxy for "who triggered this discovery". Falls back to nil — the
  # decision logic handles nil uploader_id.
  defp infer_uploader_id(course_id) do
    Content.list_materials_by_course(course_id)
    |> Enum.filter(&(&1.ocr_status == :completed and &1.material_kind in @structure_kinds))
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> List.first()
    |> case do
      nil -> nil
      material -> material.user_role_id
    end
  end

  # Fire one AIQuestionGenerationWorker job per brand-new chapter (10
  # questions each). Chapters carried forward from the old TOC already
  # have their own questions — we leave those alone so students don't
  # see duplicates and the validator doesn't re-chew 2000 tokens on
  # settled content. The course-level `trigger_question_generation`
  # that runs later will still do its broader pass for coverage.
  defp enqueue_per_chapter_generation(_course_id, []), do: :ok

  defp enqueue_per_chapter_generation(course_id, chapter_ids) do
    Enum.each(chapter_ids, fn chapter_id ->
      FunSheep.Workers.AIQuestionGenerationWorker.enqueue(course_id,
        chapter_id: chapter_id,
        count: 10,
        mode: "from_material"
      )
    end)

    Logger.info(
      "[EnrichDiscovery] Enqueued question generation for " <>
        "#{length(chapter_ids)} new chapter(s) on course #{course_id}"
    )
  end

  defp mark_discovery_complete(course, chapter_count) do
    course_id = course.id

    Courses.update_course(course, %{
      processing_step: "Discovered #{chapter_count} chapters from textbook"
    })

    metadata =
      Map.merge(course.metadata || %{}, %{
        "discovery_complete" => true,
        "ocr_complete" => true,
        "enriched_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    Courses.update_course(Courses.get_course!(course_id), %{metadata: metadata})

    broadcast(course_id, %{step: "Discovered #{chapter_count} chapters", sub_step: nil})
    trigger_question_generation(Courses.get_course!(course_id))
  end

  # Rough heuristic for how authoritative this discovery is. A future
  # improvement: actually flag "partial" vs "full" textbook at upload
  # time (based on page count vs advertised length). For now:
  #   * any textbook material OCR'd → textbook_partial
  #   * if the course metadata says it has a full textbook → textbook_full
  #   * otherwise → web
  defp source_label(course, _chapters) do
    metadata = course.metadata || %{}

    cond do
      metadata["has_full_textbook"] == true -> "textbook_full"
      has_textbook_materials?(course.id) -> "textbook_partial"
      true -> "web"
    end
  end

  defp has_textbook_materials?(course_id) do
    Content.list_materials_by_course(course_id)
    |> Enum.any?(fn m ->
      m.ocr_status == :completed and m.material_kind in @structure_kinds
    end)
  end

  # AI returns maps with atom keys (see parse_chapters_json/1); normalize
  # to string keys so the DiscoveredTOC.chapters JSON column stays stable.
  defp stringify_chapters(chapters) do
    Enum.map(chapters, fn ch ->
      %{
        "name" => Map.get(ch, :name) || Map.get(ch, "name"),
        "sections" =>
          (Map.get(ch, :sections) || Map.get(ch, "sections") || []) |> Enum.map(&to_string/1)
      }
    end)
  end

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
