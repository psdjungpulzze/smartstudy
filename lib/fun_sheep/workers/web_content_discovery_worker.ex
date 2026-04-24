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

  use Oban.Worker, queue: :ai, max_attempts: 2

  alias FunSheep.{Content, Courses}

  require Logger

  @system_prompt "You are a web search assistant for educational content. Given a search query, return structured information about the most relevant results. Return ONLY a JSON array, no other text."

  @llm_opts %{
    model: "gpt-4o-mini",
    max_tokens: 2_000,
    temperature: 0.1,
    source: "web_content_discovery_worker"
  }

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
  def perform(%Oban.Job{args: %{"course_id" => course_id}}) do
    course = Courses.get_course_with_chapters!(course_id)

    Logger.info(
      "[WebDiscovery] Starting content discovery for #{course.subject} (#{course.grade})"
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

    # Collect discovered source summaries to pass as context to discovery
    sources = Content.list_discovered_sources(course_id)

    source_context =
      sources
      |> Enum.map(fn s ->
        "- #{s.title} (#{s.source_type}): #{s.description || s.content_preview || ""}"
      end)
      |> Enum.join("\n")

    # Now trigger course structure discovery with web search context
    %{course_id: course_id, source_context: source_context}
    |> FunSheep.Workers.CourseDiscoveryWorker.new()
    |> Oban.insert()

    :ok
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

  defp build_search_queries(course) do
    subject = course.subject || course.name
    grade = course.grade
    textbook_name = get_textbook_name(course)
    chapter_names = Enum.map(course.chapters, & &1.name) |> Enum.take(5)

    uploaded_kinds = Content.course_material_kinds(course.id)
    has_textbook = Enum.any?(uploaded_kinds, &(&1 in [:textbook, :supplementary_book]))
    has_question_bank = :sample_questions in uploaded_kinds

    queries = []

    # 1. Question banks — skip if user already supplied sample questions
    queries =
      if has_question_bank do
        queries
      else
        queries ++
          [
            {"#{subject} grade #{grade} practice questions", "question_bank"},
            {"#{subject} grade #{grade} test questions with answers", "question_bank"},
            {"#{subject} multiple choice questions and answers", "question_bank"}
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
        ap_subject = normalize_ap_subject(subject)

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
          [{"site:#{site} #{subject} grade #{grade} questions", "question_bank"}]
        end)

    # 5. Chapter-specific searches (top 3 chapters)
    queries =
      queries ++
        Enum.flat_map(Enum.take(chapter_names, 3), fn ch_name ->
          clean_name = clean_chapter_name(ch_name)

          [
            {"#{subject} #{clean_name} practice questions", "question_bank"},
            {"#{subject} #{clean_name} quiz", "practice_test"}
          ]
        end)

    # 6. Study guides and review materials
    queries =
      queries ++
        [
          {"#{subject} grade #{grade} study guide", "study_guide"},
          {"#{subject} grade #{grade} review sheet", "study_guide"},
          {"#{subject} grade #{grade} exam review", "study_guide"}
        ]

    # 7. Past papers (especially for standardized courses)
    queries =
      queries ++
        [
          {"#{subject} grade #{grade} past exam papers with answers", "practice_test"},
          {"#{subject} final exam practice test", "practice_test"}
        ]

    queries
  end

  # --- Web Search Execution ---

  defp search_web(query) do
    # Use AI agent to perform web search and return structured results
    prompt = """
    Search the web for: "#{query}"

    Return a JSON array of the top 5-10 most relevant results. Each result should have:
    - "title": the page title
    - "url": the full URL
    - "snippet": a brief description of the content
    - "publisher": the website/publisher name
    - "confidence": how relevant this is (0.0 to 1.0)

    Focus on pages that actually contain practice questions, test banks, or study materials.
    Skip results that are just ads, paywalls with no preview, or irrelevant pages.

    Return ONLY the JSON array.
    """

    case ai_client().call(@system_prompt, prompt, @llm_opts) do
      {:ok, response} ->
        parse_search_response_text(response, query)

      {:error, reason} ->
        Logger.warning("[WebDiscovery] Search failed for '#{query}': #{inspect(reason)}")
        {:error, reason}
    end
  end

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
              confidence: r["confidence"] || 0.5,
              search_query: query
            }
          end)

        {:ok, parsed}

      _ ->
        Logger.error("[WebDiscovery] Failed to parse search response text")
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
          "[WebDiscovery] Dropped hallucinated URL #{inspect(r[:url])}: #{inspect(reason)}"
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

  defp normalize_ap_subject(subject) do
    subject
    |> String.replace(~r/^AP\s+/i, "")
    |> String.trim()
  end

  defp clean_chapter_name(name) do
    name
    |> String.replace(~r/^Chapter\s*\d+\s*[:\-]\s*/i, "")
    |> String.replace(~r/^Unit\s*\d+\s*[:\-]\s*/i, "")
    |> String.trim()
  end

  defp broadcast(course_id, data) do
    Phoenix.PubSub.broadcast(
      FunSheep.PubSub,
      "course:#{course_id}",
      {:processing_update, data}
    )
  end

  defp ai_client, do: Application.get_env(:fun_sheep, :ai_client_impl, FunSheep.AI.Client)
end
