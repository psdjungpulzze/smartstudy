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

    # Collect OCR text + filename-derived chapter signal from all materials.
    # The filename signal (e.g. "Biology Chapter 39 - 22.jpg" → 39) is a strong
    # authoritative prior that we pass to the AI so it stops under-counting on
    # big books where the OCR budget truncates most of the content.
    materials = completed_structure_materials(course_id)
    ocr_text = collect_ocr_text(materials)
    filename_chapters = extract_filename_chapter_numbers(materials)

    if ocr_text == "" do
      Logger.warning("[EnrichDiscovery] No OCR text found for course #{course_id}")
      # Skip re-discovery, go straight to question generation
      trigger_question_generation(course)
      :ok
    else
      # Run AI discovery with OCR text as primary context.
      broadcast(course_id, %{sub_step: "Discovering chapters from uploaded textbook..."})

      chapters = discover_chapters_from_materials(course, ocr_text, filename_chapters)

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

  # When the filename of a material contains "Chapter N" (or Unit/Module/Part),
  # pull N out as an authoritative signal. Works across mixed casing and the
  # trailing page-number suffix some scanners add (e.g. "Biology Chapter 39 - 22.jpg").
  @filename_chapter_pattern ~r/\b(?:chapter|unit|module|part)\s*(\d+)\b/i

  # Per-material cap for the "many small materials" sampling strategy.
  # Enough to catch a chapter title + first few paragraphs on a single page.
  @sampled_per_material_chars 2_000

  defp completed_structure_materials(course_id) do
    Content.list_materials_by_course(course_id)
    |> Enum.filter(fn m ->
      m.ocr_status == :completed and m.material_kind in @structure_kinds
    end)
  end

  # Adaptive snippet builder. The old path assumed each material was a full
  # textbook (20+ pages) and that the TOC lived in the front matter. That
  # breaks when users upload one JPG per page — hundreds of 1-page
  # materials where the per-material "take 25 front pages + regex-scan page
  # 26+" logic collapses to "show page 1, scan nothing" and the global 80K
  # truncation keeps only the first ~20 of hundreds of pages. Pick the
  # strategy from the shape of the upload.
  defp collect_ocr_text(materials) do
    max_pages =
      materials
      |> Enum.map(&page_count/1)
      |> Enum.max(fn -> 0 end)

    cond do
      materials == [] -> ""
      max_pages >= 10 -> per_material_snippet(materials)
      true -> sampled_snippet(materials)
    end
  end

  defp page_count(material) do
    Content.list_ocr_pages_by_material(material.id) |> length()
  end

  # Original strategy: each material has real front matter + deep content.
  # TOC lives in the first 25 pages; headings elsewhere are surfaced via regex.
  defp per_material_snippet(materials) do
    materials
    |> Enum.map(&build_material_snippet/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n===== NEXT MATERIAL =====\n\n")
  end

  # "Many small materials" strategy: allocate the character budget evenly
  # across all materials (grouped by filename-derived chapter when possible,
  # so we don't blow budget on 20 pages of the same chapter). Each material
  # contributes its filename as a label + up to ~2K chars of OCR text. The
  # label is critical — it's what lets the AI tie a sampled page back to a
  # chapter number even when the page text itself doesn't say "Chapter 39".
  #
  # Total output is capped at @prompt_char_budget — when the grouping
  # doesn't reduce enough (e.g. filenames are random and every material
  # becomes its own {:other, id} group), per-sample size shrinks so the
  # union still fits.
  defp sampled_snippet(materials) do
    grouped = group_materials_by_filename_chapter(materials)

    ordered_groups =
      grouped
      |> Enum.sort_by(fn {key, _} -> chapter_sort_key(key) end)

    group_count = length(ordered_groups)

    per_sample_chars =
      case group_count do
        0 -> 0
        n -> min(@sampled_per_material_chars, div(@prompt_char_budget, n) - 100)
      end
      |> max(200)

    samples =
      ordered_groups
      |> Enum.flat_map(fn {chapter_key, group} ->
        group
        |> Enum.sort_by(& &1.file_name)
        |> Enum.take(1)
        |> Enum.map(&material_sample(&1, chapter_key, per_sample_chars))
      end)
      |> Enum.reject(&(&1 == ""))

    samples |> Enum.join("\n\n===== NEXT SAMPLE =====\n\n")
  end

  defp group_materials_by_filename_chapter(materials) do
    Enum.group_by(materials, fn m ->
      case filename_chapter_number(m.file_name) do
        nil -> {:other, m.id}
        n -> {:chapter, n}
      end
    end)
  end

  defp chapter_sort_key({:chapter, n}), do: {0, n}
  defp chapter_sort_key({:other, id}), do: {1, id}

  defp material_sample(material, chapter_key, max_chars) do
    label =
      case chapter_key do
        {:chapter, n} -> "[filename chapter #{n}] #{material.file_name}"
        {:other, _} -> "[unlabeled] #{material.file_name}"
      end

    text =
      Content.list_ocr_pages_by_material(material.id)
      |> Enum.sort_by(& &1.page_number)
      |> Enum.map(& &1.extracted_text)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")
      |> String.slice(0, max_chars)
      |> String.trim()

    case text do
      "" -> ""
      t -> label <> "\n" <> t
    end
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

  # Returns a sorted, deduped list of chapter numbers mined from the
  # filenames of the uploaded materials. Empty when filenames don't follow
  # a "Chapter N" convention — in that case we fall through to pure
  # OCR-driven discovery.
  @doc false
  def extract_filename_chapter_numbers(materials) do
    materials
    |> Enum.map(&filename_chapter_number(&1.file_name))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp filename_chapter_number(nil), do: nil

  defp filename_chapter_number(file_name) when is_binary(file_name) do
    case Regex.run(@filename_chapter_pattern, file_name) do
      [_, n] ->
        case Integer.parse(n) do
          {num, ""} when num > 0 and num < 1_000 -> num
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp filename_chapter_number(_), do: nil

  defp discover_chapters_from_materials(course, ocr_text, filename_chapters) do
    subject = course.subject
    grade = course.grade

    truncated_text =
      if String.length(ocr_text) > @prompt_char_budget do
        String.slice(ocr_text, 0, @prompt_char_budget) <> "\n\n[... text truncated ...]"
      else
        ocr_text
      end

    filename_signal = build_filename_signal(filename_chapters)

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
    #{filename_signal}

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

  # Surface filename-derived chapter numbers as authoritative context so the
  # AI returns the full chapter list even when the OCR budget truncates most
  # of the book. Empty string when filenames don't reveal a chapter scheme —
  # the AI falls back to OCR-only reasoning.
  defp build_filename_signal([]), do: ""

  defp build_filename_signal(chapter_numbers) do
    list =
      chapter_numbers
      |> Enum.sort()
      |> Enum.map(&Integer.to_string/1)
      |> Enum.join(", ")

    """

    AUTHORITATIVE FILENAME SIGNAL:
    The filenames of the uploaded pages reference these chapter numbers: [#{list}].
    Return one entry in the JSON array for EACH of these chapter numbers
    (#{length(chapter_numbers)} chapters total), even if the sampled text
    doesn't cover every chapter. Use the sampled OCR text to fill in each
    chapter's real name; if a chapter's name isn't present in the sample,
    use "Chapter N" as a placeholder for number N.
    """
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
