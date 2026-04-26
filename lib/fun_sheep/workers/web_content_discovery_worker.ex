defmodule FunSheep.Workers.WebContentDiscoveryWorker do
  @moduledoc """
  Oban worker that performs comprehensive web searches to find content
  for a course — textbooks, question banks, practice tests, study guides.

  This is the "deep discovery" that populates questions even when no
  materials are uploaded. It searches for:

  1. Known textbooks for the subject/grade (e.g., Campbell Biology)
  2. Official question banks and practice tests
  3. AP/standardized test prep materials
  4. Educational sites with practice problems
  5. Past exam papers and review sheets

  Results are stored as DiscoveredSource records, which are then
  processed by the WebQuestionScraperWorker.
  """

  use Oban.Worker, queue: :course_setup, max_attempts: 2

  alias FunSheep.{Content, Courses}

  require Logger

  # Anthropic web search — real crawl, no hallucination
  @anthropic_api_url "https://api.anthropic.com/v1/messages"
  @anthropic_api_version "2023-06-01"
  # claude-haiku-4-5: fast, cheap, supports web_search_20250305
  @search_model "claude-haiku-4-5-20251001"
  # Server-side tool: Anthropic executes the search; single round-trip, real URLs
  @search_tool_type "web_search_20250305"
  @search_beta "web-search-2025-03-05"

  @search_sites [
    "quizlet.com",
    "khanacademy.org",
    "openstax.org",
    "collegeboard.org",
    "albert.io",
    "varsitytutors.com",
    "testprep-online.com",
    "sparknotes.com",
    "cliffsnotes.com"
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"course_id" => course_id},
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    course = Courses.get_course_with_chapters!(course_id)

    Logger.info(
      "[WebDiscovery] Starting content discovery for #{course.subject} (grade #{Enum.join(course.grades || [], ", ")})"
    )

    Courses.update_course(course, %{
      processing_step: "Searching the web for course materials..."
    })

    broadcast(course_id, %{step: "Searching the web for course materials..."})

    # Build search queries based on course context
    queries = build_search_queries(course)
    total_queries = length(queries)

    broadcast(course_id, %{
      sub_step: "Searching #{total_queries} queries in parallel..."
    })

    # Run searches concurrently. Total wall-clock becomes ~max(per-query time)
    # instead of the sum. A single slow/timing-out query no longer blocks the
    # rest; `on_timeout: :kill_task` plus an outer timeout keeps the batch
    # bounded even if Interactor's web_search assistant stalls.
    #
    # Concurrency is capped to avoid thundering-herd on the Interactor agent
    # endpoint (which serializes per-OpenAI-account rate limits anyway).
    done = :atomics.new(1, [])

    all_results =
      queries
      |> Task.async_stream(
        fn {query, source_type} ->
          results =
            case search_web(query) do
              {:ok, results} ->
                Enum.map(results, fn r -> Map.put(r, :source_type, source_type) end)

              {:error, _} ->
                []
            end

          completed = :atomics.add_get(done, 1, 1)
          short_query = String.slice(query, 0, 60)

          broadcast(course_id, %{
            sub_step:
              "Searched (#{completed}/#{total_queries}): \"#{short_query}\" — #{length(results)} hits"
          })

          results
        end,
        max_concurrency: 3,
        timeout: 75_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.flat_map(fn
        {:ok, results} -> results
        {:exit, _reason} -> []
      end)

    broadcast(course_id, %{sub_step: "Deduplicating #{length(all_results)} results..."})

    # Deduplicate by URL
    unique_results =
      all_results
      |> Enum.uniq_by(fn r -> r[:url] || r[:title] end)

    broadcast(course_id, %{sub_step: "Validating #{length(unique_results)} URLs..."})

    # The Interactor `web_search` agent is an LLM — it hallucinates URLs that
    # look plausible but resolve to NXDOMAIN, 404, or 403 walls. Persisting
    # these poisons the scraper queue (every retry hits the same dead URL).
    # HEAD-prefilter so only URLs that actually exist make it to the DB.
    unique_results = validate_urls(unique_results)

    broadcast(course_id, %{sub_step: "Saving #{length(unique_results)} verified sources..."})

    # Store discovered sources
    stored_count =
      Enum.reduce(unique_results, 0, fn result, count ->
        attrs = %{
          course_id: course_id,
          source_type: result.source_type,
          title: result[:title] || "Untitled",
          url: result[:url],
          description: result[:description],
          publisher: result[:publisher],
          content_preview: result[:snippet],
          search_query: result[:search_query],
          confidence_score: result[:confidence] || 0.5,
          status: if(result[:url], do: "discovered", else: "skipped")
        }

        case Content.create_discovered_source_if_new(attrs) do
          {:ok, %{id: nil}} -> count
          {:ok, _} -> count + 1
          {:error, _} -> count
        end
      end)

    # Skip known-textbook discovery if user already uploaded a textbook —
    # their upload is the source of truth for textbook content.
    uploaded_has_textbook =
      Content.course_material_kinds(course.id)
      |> Enum.any?(&(&1 in [:textbook, :supplementary_book]))

    textbook_count = if uploaded_has_textbook, do: 0, else: discover_known_textbooks(course)

    total = stored_count + textbook_count

    Logger.info("[WebDiscovery] Found #{total} sources for #{course.subject}")

    # Reload course to get fresh metadata
    course = Courses.get_course!(course_id)

    # Mark web search as complete
    metadata = Map.merge(course.metadata || %{}, %{"web_search_complete" => true})

    Courses.update_course(course, %{
      processing_step: "Found #{total} content sources",
      metadata: metadata
    })

    broadcast(course_id, %{
      step: "Found #{total} content sources",
      sources_found: total,
      status: "web_search_complete"
    })

    # Trigger scraping for discovered sources (parallel with discovery)
    if total > 0 do
      %{course_id: course_id}
      |> FunSheep.Workers.WebQuestionScraperWorker.new()
      |> Oban.insert()
    end

    # Route based on whether the course has uploaded textbook materials.
    #
    # With textbook uploads: EnrichDiscoveryWorker will run after OCR completes
    # and do authoritative chapter discovery from the actual textbook content.
    # Running a web-based CourseDiscovery pass here would mark discovery_complete
    # prematurely and show "Discovering" and "Processing materials" as
    # simultaneously active in the UI — confusing and inaccurate.
    #
    # Without textbook uploads: no OCR will happen, so CourseDiscoveryWorker
    # is the only pass and must run now.
    if uploaded_has_textbook do
      # If by some race condition OCR is already done, advance immediately.
      # Normally OCR completes after web search, so this branch is a safety net.
      course = Courses.get_course!(course_id)

      ocr_done =
        course.ocr_total_count == 0 or course.ocr_completed_count >= course.ocr_total_count

      if ocr_done do
        Logger.info(
          "[WebDiscovery] OCR already complete, triggering EnrichDiscovery for #{course_id}"
        )

        Courses.advance_to_extraction(course_id)
      else
        Logger.info(
          "[WebDiscovery] Textbook uploaded — skipping web-only discovery; EnrichDiscovery will run after OCR"
        )
      end
    else
      # Web-only course: discovery from web search context is the only pass.
      sources = Content.list_discovered_sources(course_id)

      source_context =
        sources
        |> Enum.map(fn s ->
          "- #{s.title} (#{s.source_type}): #{s.description || s.content_preview || ""}"
        end)
        |> Enum.join("\n")

      %{course_id: course_id, source_context: source_context}
      |> FunSheep.Workers.CourseDiscoveryWorker.new()
      |> Oban.insert()
    end

    :ok
  rescue
    exception ->
      Logger.error(
        "[WebDiscovery] Unexpected crash for course #{course_id} (attempt #{attempt}): #{inspect(exception)}"
      )

      if attempt >= max_attempts do
        try do
          course = Courses.get_course!(course_id)

          Courses.update_course(course, %{
            processing_status: "failed",
            processing_step: "Web search failed unexpectedly. Please try again."
          })

          broadcast(course_id, %{
            status: "failed",
            step: "Web search failed unexpectedly. Please try again."
          })
        rescue
          _ -> :ok
        end
      end

      reraise exception, __STACKTRACE__
  end

  @doc """
  Enqueues a web discovery job for a course.
  """
  def enqueue(course_id) do
    %{course_id: course_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  # --- Search Query Building ---

  defp build_search_queries(%{metadata: %{"generation_config" => gen_config}} = course)
       when is_map(gen_config) do
    # Metadata-driven path: derive search queries from generation_config.prompt_context.
    # This handles any standardized test course that has generation_config set via
    # CourseBuilder (ACT, GRE, HSC, etc.), not just SAT.
    prompt_context = gen_config["prompt_context"] || ""
    test_label = String.upcase(course.catalog_test_type || course.name)

    per_section =
      course.chapters
      |> Enum.flat_map(fn chapter ->
        Enum.flat_map(chapter.sections || [], fn section ->
          test_specific_search_queries(section.name, chapter.name, test_label, course.catalog_subject)
        end)
      end)

    if per_section != [] do
      per_section
    else
      # No sections yet — fall back to course-level queries derived from the prompt context
      subject_hint = course.catalog_subject || course.subject || course.name

      [
        {"#{test_label} #{subject_hint} practice questions", "question_bank"},
        {"#{test_label} #{subject_hint} official prep", "question_bank"},
        {"#{test_label} #{subject_hint} test bank sample questions", "practice_test"},
        {"#{prompt_context |> String.slice(0, 80)} practice", "question_bank"}
      ]
    end
  end

  defp build_search_queries(%{catalog_test_type: "sat"} = course) do
    # SAT fallback: courses created before generation_config metadata was added.
    # SAT courses use targeted, domain-specific search queries for each section.
    # Generic queries ("grade X practice questions") produce irrelevant hits for
    # standardised tests — we need College Board / Khan Academy / Albert sources
    # scoped to each exact skill area instead.
    course.chapters
    |> Enum.flat_map(fn chapter ->
      Enum.flat_map(chapter.sections || [], fn section ->
        sat_search_queries(section.name, course.catalog_subject)
      end)
    end)
    |> then(fn per_section ->
      # Add course-level queries in case there are no sections yet
      if per_section == [] do
        [
          {"digital SAT #{course.subject || course.name} practice questions", "question_bank"},
          {"SAT #{course.subject || course.name} Khan Academy practice", "question_bank"},
          {"College Board digital SAT #{course.subject || course.name} sample questions",
           "practice_test"}
        ]
      else
        per_section
      end
    end)
  end

  defp build_search_queries(course) do
    subject = course.subject || course.name
    grade = List.first(course.grades || []) || ""
    textbook_name = get_textbook_name(course)
    chapter_names = Enum.map(course.chapters, & &1.name) |> Enum.take(5)

    uploaded_kinds = Content.course_material_kinds(course.id)
    has_textbook = Enum.any?(uploaded_kinds, &(&1 in [:textbook, :supplementary_book]))
    has_question_bank = :sample_questions in uploaded_kinds

    # Prefer the course name as the search term when it's more specific than the
    # stored subject. "AP US History" is a far better query token than "History".
    search_subject = best_search_subject(course.name, subject)

    queries = []

    # 1. Question banks — skip if user already supplied sample questions
    queries =
      if has_question_bank do
        queries
      else
        queries ++
          [
            {"#{search_subject} grade #{grade} practice questions", "question_bank"},
            {"#{search_subject} grade #{grade} test questions with answers", "question_bank"},
            {"#{search_subject} multiple choice questions and answers", "question_bank"}
          ]
      end

    # 2. Textbook-specific searches — skip if user already uploaded a textbook
    queries =
      if textbook_name && !has_textbook do
        queries ++
          [
            {"#{textbook_name} practice test questions", "question_bank"},
            {"#{textbook_name} chapter review questions", "question_bank"},
            {"#{textbook_name} test bank", "question_bank"},
            {"#{textbook_name} study guide", "study_guide"}
          ]
      else
        queries
      end

    # 3. AP/standardized test content (detect if AP course)
    queries =
      if is_ap_course?(subject, grade) do
        # Derive ap_subject from the course name first (e.g. "AP US History" → "US History"),
        # falling back to the stored subject. This prevents overly generic queries like
        # "AP History ..." that match world/European history as well as US History.
        ap_subject = normalize_ap_subject(course.name) || normalize_ap_subject(subject)

        queries ++
          [
            {"AP #{ap_subject} practice exam free response", "practice_test"},
            {"AP #{ap_subject} multiple choice practice", "practice_test"},
            {"AP #{ap_subject} released exam questions", "practice_test"},
            {"AP #{ap_subject} review questions by topic", "question_bank"},
            {"College Board AP #{ap_subject} practice", "practice_test"}
          ]
      else
        queries
      end

    # 4. Educational platform searches
    queries =
      queries ++
        Enum.flat_map(@search_sites, fn site ->
          [{"site:#{site} #{search_subject} grade #{grade} questions", "question_bank"}]
        end)

    # 5. Chapter-specific searches (top 3 chapters)
    queries =
      queries ++
        Enum.flat_map(Enum.take(chapter_names, 3), fn ch_name ->
          clean_name = clean_chapter_name(ch_name)

          [
            {"#{search_subject} #{clean_name} practice questions", "question_bank"},
            {"#{search_subject} #{clean_name} quiz", "practice_test"}
          ]
        end)

    # 6. Study guides and review materials
    queries =
      queries ++
        [
          {"#{search_subject} grade #{grade} study guide", "study_guide"},
          {"#{search_subject} grade #{grade} review sheet", "study_guide"},
          {"#{search_subject} grade #{grade} exam review", "study_guide"}
        ]

    # 7. Past papers (especially for standardized courses)
    queries =
      queries ++
        [
          {"#{search_subject} grade #{grade} past exam papers with answers", "practice_test"},
          {"#{search_subject} final exam practice test", "practice_test"}
        ]

    queries
  end

  # Returns the more descriptive of the course name and stored subject for use
  # as a search term. The course name ("AP US History") is preferred over a
  # broad subject label ("History") when it adds specificity.
  defp best_search_subject(name, subject) do
    name_stripped = if name, do: String.replace(name, ~r/^AP\s+/i, "") |> String.trim(), else: nil
    subject_stripped = if subject, do: String.trim(subject), else: nil

    cond do
      # Course name is strictly longer (more specific) than the stored subject
      name_stripped && subject_stripped &&
          String.length(name_stripped) > String.length(subject_stripped) ->
        name_stripped

      subject_stripped && subject_stripped != "" ->
        subject_stripped

      true ->
        name || ""
    end
  end

  # --- Web Search Execution (Anthropic web_search_20250305 — real crawl) ---

  defp search_web(query) do
    prompt = """
    Search the web for educational resources matching this query: "#{query}"

    Return a JSON array of up to 10 results you actually found via web search. Each item:
    - "title": the real page title from the search result
    - "url": the actual URL from the search result
    - "snippet": brief description of what the page contains
    - "publisher": website or domain name

    Only include pages that genuinely contain practice questions, quizzes, test banks,
    study guides, or past exam papers. Omit pure ads or pages with no educational content.

    Return ONLY the JSON array, no other text.
    """

    api_key = Application.fetch_env!(:fun_sheep, :anthropic_api_key)

    body = %{
      model: @search_model,
      max_tokens: 4096,
      tools: [%{type: @search_tool_type, name: "web_search", max_uses: 3}],
      messages: [%{role: "user", content: prompt}]
    }

    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", @anthropic_api_version},
      {"anthropic-beta", @search_beta},
      {"content-type", "application/json"}
    ]

    case Req.post(@anthropic_api_url,
           json: body,
           headers: headers,
           receive_timeout: 90_000,
           retry: false,
           finch: FunSheep.Finch
         ) do
      {:ok, %{status: 200, body: resp}} ->
        text = extract_text_from_response(resp)
        parse_search_response_text(text, query)

      {:ok, %{status: status, body: resp_body}} ->
        Logger.warning(
          "[WebDiscovery] Anthropic search HTTP #{status} for '#{query}': #{inspect(resp_body)}"
        )

        {:error, {:http_status, status}}

      {:error, reason} ->
        Logger.warning("[WebDiscovery] Search failed for '#{query}': #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Extracts the final text block from an Anthropic response.
  # When using server-side tools the content array contains tool_use, tool_result,
  # and text blocks — we want the last text block (Claude's final reply).
  defp extract_text_from_response(%{"content" => content}) when is_list(content) do
    content
    |> Enum.filter(&(&1["type"] == "text"))
    |> List.last()
    |> case do
      %{"text" => text} -> text
      _ -> ""
    end
  end

  defp extract_text_from_response(_), do: ""

  defp parse_search_response_text(text, query) do
    cleaned =
      text
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, results} when is_list(results) ->
        parsed =
          Enum.map(results, fn r ->
            %{
              title: r["title"],
              url: r["url"],
              snippet: r["snippet"],
              publisher: r["publisher"],
              confidence: r["confidence"] || 0.8,
              search_query: query
            }
          end)

        {:ok, parsed}

      _ ->
        Logger.error("[WebDiscovery] Failed to parse search response for '#{query}': #{inspect(String.slice(text, 0, 200))}")
        {:error, :parse_failed}
    end
  end

  # --- URL Validation ---

  # HEAD-request each candidate URL in parallel; drop anything that doesn't
  # resolve (NXDOMAIN, timeout, 4xx, 5xx). Some sites block HEAD with 405 —
  # fall back to GET with Range:bytes=0-0 in that case so we don't lose
  # legitimate sources.
  defp validate_urls(results) do
    results
    |> Task.async_stream(
      fn r ->
        case probe_url(r[:url]) do
          :ok -> {:keep, r}
          {:drop, reason} -> {:drop, r, reason}
        end
      end,
      max_concurrency: 20,
      timeout: 10_000,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.flat_map(fn
      {:ok, {:keep, r}} ->
        [r]

      {:ok, {:drop, r, reason}} ->
        Logger.debug(
          "[WebDiscovery] Dropped unreachable URL #{inspect(r[:url])}: #{inspect(reason)}"
        )

        []

      {:exit, _} ->
        []
    end)
  end

  defp probe_url(nil), do: {:drop, :no_url}
  defp probe_url(""), do: {:drop, :empty_url}

  defp probe_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        do_probe(url)

      _ ->
        {:drop, :malformed_url}
    end
  end

  defp do_probe(url) do
    case Req.head(url, receive_timeout: 5_000, max_redirects: 3, retry: false) do
      {:ok, %{status: status}} when status in 200..399 ->
        :ok

      # Some sites reject HEAD with 405/501 but accept GET — try a tiny GET.
      {:ok, %{status: status}} when status in [405, 501] ->
        case Req.get(url,
               receive_timeout: 5_000,
               max_redirects: 3,
               retry: false,
               headers: [{"range", "bytes=0-0"}]
             ) do
          {:ok, %{status: s}} when s in 200..399 -> :ok
          {:ok, %{status: s}} -> {:drop, {:http_status, s}}
          {:error, reason} -> {:drop, reason}
        end

      {:ok, %{status: status}} ->
        {:drop, {:http_status, status}}

      {:error, %Req.TransportError{reason: reason}} ->
        {:drop, {:transport, reason}}

      {:error, reason} ->
        {:drop, reason}
    end
  rescue
    _ -> {:drop, :exception}
  end

  # --- Known Textbook Discovery ---

  # Textbook discovery is done via AI search only — no hardcoded lists.
  # If AI is unavailable, we report 0 textbooks found (honest failure).
  defp discover_known_textbooks(_course), do: 0

  # --- Helpers ---

  defp get_textbook_name(course) do
    cond do
      course.custom_textbook_name && course.custom_textbook_name != "" ->
        course.custom_textbook_name

      course.textbook_id ->
        textbook = Courses.get_textbook!(course.textbook_id)
        "#{textbook.title}#{if textbook.author, do: " by #{textbook.author}", else: ""}"

      true ->
        nil
    end
  end

  defp is_ap_course?(subject, grade) do
    subject_lower = String.downcase(subject || "")
    String.contains?(subject_lower, "ap ") or is_ap_grade?(grade)
  end

  defp is_ap_grade?(grade) do
    grade in ["11", "12", "College"]
  end

  defp normalize_ap_subject(nil), do: nil

  defp normalize_ap_subject(subject) do
    result =
      subject
      |> String.replace(~r/^AP\s+/i, "")
      |> String.trim()

    if result == "", do: nil, else: result
  end

  defp clean_chapter_name(name) do
    name
    |> String.replace(~r/^Chapter\s*\d+\s*[:\-]\s*/i, "")
    |> String.replace(~r/^Unit\s*\d+\s*[:\-]\s*/i, "")
    |> String.trim()
  end

  # --- Metadata-driven (generic standardized test) query generation ---

  # Generates targeted search queries for any standardized test course that has
  # generation_config in its metadata. Uses the test_label (e.g. "ACT", "GRE")
  # and the section/chapter names to build domain-specific queries.
  defp test_specific_search_queries(section_name, chapter_name, test_label, catalog_subject) do
    clean_section = clean_chapter_name(section_name)
    clean_chapter = clean_chapter_name(chapter_name)

    subject_hint =
      case catalog_subject do
        "mathematics" -> "math"
        "english_language" -> "English"
        "reading" -> "reading"
        "science" -> "science"
        "verbal" -> "verbal reasoning"
        "quantitative" -> "quantitative reasoning"
        _ -> catalog_subject || ""
      end

    [
      {"#{test_label} #{subject_hint} practice questions #{clean_section}", "question_bank"},
      {"#{test_label} #{clean_chapter} #{clean_section} practice problems", "question_bank"},
      {"#{test_label} #{subject_hint} official prep #{clean_section}", "practice_test"}
    ]
  end

  # --- SAT-specific query generation ---

  # Generates 3 targeted search queries for a single SAT section name.
  # Queries are scoped to official/trusted SAT prep sources (College Board,
  # Khan Academy, Albert) to maximise the relevance of discovered content.
  defp sat_search_queries(section_name, "mathematics") do
    clean = clean_chapter_name(section_name)

    [
      {"SAT math practice questions #{clean}", "question_bank"},
      {"digital SAT algebra #{clean} practice problems answers", "question_bank"},
      {"Khan Academy SAT math #{clean}", "question_bank"}
    ]
  end

  defp sat_search_queries(section_name, "reading_writing") do
    clean = clean_chapter_name(section_name)

    [
      {"SAT reading writing practice questions #{clean}", "question_bank"},
      {"digital SAT English #{clean} practice problems answers", "question_bank"},
      {"Khan Academy SAT reading writing #{clean}", "question_bank"}
    ]
  end

  defp sat_search_queries(section_name, _catalog_subject) do
    clean = clean_chapter_name(section_name)

    [
      {"SAT practice questions #{clean}", "question_bank"},
      {"digital SAT #{clean} practice problems", "question_bank"},
      {"College Board SAT #{clean} sample questions", "practice_test"}
    ]
  end

  defp broadcast(course_id, data) do
    Phoenix.PubSub.broadcast(
      FunSheep.PubSub,
      "course:#{course_id}",
      {:processing_update, data}
    )
  end

end
