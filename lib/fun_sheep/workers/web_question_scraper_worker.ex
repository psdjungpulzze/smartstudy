defmodule FunSheep.Workers.WebQuestionScraperWorker do
  @moduledoc """
  Oban worker that scrapes discovered source URLs for questions.

  For each discovered source in "discovered" status:
  1. Fetches the page content
  2. Extracts questions using regex patterns + AI
  3. Categorizes questions into the course's chapter structure
  4. Inserts questions into the question bank

  Handles various question formats:
  - Multiple choice (A/B/C/D)
  - True/False
  - Short answer with solutions
  - Numbered problem sets
  """

  use Oban.Worker,
    queue: :ai,
    max_attempts: 2,
    unique: [
      period: 300,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias FunSheep.{Content, Courses, Repo}
  alias FunSheep.Questions.Question
  alias FunSheep.Interactor.Agents

  require Logger

  @max_sources_per_run 500
  @max_page_size 100_000

  # How many sources to fetch + extract in parallel within one job.
  # Each source hits Playwright renderer + OpenAI — 5 is a reasonable balance
  # between throughput and not hammering upstream services.
  @source_concurrency 5

  # AI extraction text chunking
  @ai_chunk_size 18_000
  @ai_max_chunks 4
  @ai_chunk_overlap 500

  # Minimum text length (in bytes) after plain fetch before we retry via the
  # JS-rendering Playwright service. Short responses typically mean an SPA
  # returned shell HTML/JS without the actual content.
  @min_plain_text_bytes 1_500

  # Hosts known to require JavaScript rendering — always go through the
  # Playwright renderer for these, skipping the plain Req fetch entirely.
  @spa_hosts ~w(
    quizlet.com
    khanacademy.org
    collegeboard.org
    albert.io
    brainly.com
    brainly.com.br
    chegg.com
    coursehero.com
    studocu.com
    slader.com
    numerade.com
    sparknotes.com
    gradesaver.com
    study.com
    magoosh.com
    varsitytutors.com
    proprofs.com
  )

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"course_id" => course_id}}) do
    course = Courses.get_course_with_chapters!(course_id)
    sources = Content.list_scrapable_sources(course_id) |> Enum.take(@max_sources_per_run)

    if sources == [] do
      Logger.info("[Scraper] No scrapable sources for course #{course_id}")

      # Even with no scrapable URLs, generate questions from the discovered
      # textbook/source knowledge using AI
      generate_from_discovered_knowledge(course)
      :ok
    else
      total = length(sources)

      broadcast(course_id, %{
        sub_step: "Processing 0/#{total} sources…"
      })

      total_questions =
        sources
        |> Task.async_stream(
          fn source -> scrape_and_extract(source, course) end,
          max_concurrency: @source_concurrency,
          # Individual source timeout — renderer can take ~45s + AI chunks add up
          timeout: 180_000,
          on_timeout: :kill_task,
          ordered: false
        )
        |> Stream.with_index(1)
        |> Enum.reduce(0, fn
          {{:ok, inserted}, done}, count ->
            broadcast(course_id, %{sub_step: "Processing #{done}/#{total} sources…"})
            count + inserted

          {{:exit, reason}, done}, count ->
            Logger.warning("[Scraper] Source task failed: #{inspect(reason)}")
            broadcast(course_id, %{sub_step: "Processing #{done}/#{total} sources…"})
            count
        end)

      Logger.info("[Scraper] Extracted #{total_questions} questions from #{total} sources")

      Courses.update_course(course, %{
        processing_step: "Extracted #{total_questions} questions from web sources"
      })

      broadcast(course_id, %{
        step: "Extracted #{total_questions} questions from web sources",
        questions_scraped: total_questions
      })

      # If there are still scrapable sources (e.g. 500 cap exceeded, or new ones
      # were added mid-run), re-enqueue so the user doesn't have to click again.
      remaining = Content.list_scrapable_sources(course_id)

      if remaining != [] do
        Logger.info("[Scraper] #{length(remaining)} sources remain, re-enqueueing")
        enqueue(course_id)
      end

      :ok
    end
  end

  @doc """
  Enqueues a scraping job for a course.

  Oban uniqueness prevents duplicate jobs from stacking up for the same course —
  if one is already queued/running/retryable, this returns the existing job.
  """
  def enqueue(course_id) do
    %{course_id: course_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  # --- Scrape a single source ---

  defp scrape_and_extract(source, course) do
    Content.update_discovered_source(source, %{status: "scraping"})

    case fetch_page(source.url) do
      {:ok, text} ->
        Content.update_discovered_source(source, %{
          scraped_text: String.slice(text, 0, @max_page_size),
          content_size_bytes: byte_size(text),
          status: "scraped"
        })

        # Extract questions from the scraped text
        questions = extract_questions_from_text(text, course, source)

        # Insert questions
        {inserted, inserted_ids} =
          Enum.reduce(questions, {0, []}, fn q, {count, ids} ->
            case insert_question(q, course) do
              {:ok, inserted_q} -> {count + 1, [inserted_q.id | ids]}
              {:error, _} -> {count, ids}
            end
          end)

        FunSheep.Workers.QuestionValidationWorker.enqueue(inserted_ids,
          course_id: course.id
        )

        Content.update_discovered_source(source, %{
          status: "processed",
          questions_extracted: inserted
        })

        inserted

      {:error, reason} ->
        Logger.warning("[Scraper] Failed to fetch #{source.url}: #{inspect(reason)}")
        Content.update_discovered_source(source, %{status: "failed"})
        0
    end
  end

  # --- Page Fetching ---

  defp fetch_page(url) when is_binary(url) do
    if needs_js_rendering?(url) do
      case fetch_via_renderer(url) do
        {:ok, text} -> {:ok, text}
        {:error, _} -> fetch_plain(url)
      end
    else
      case fetch_plain(url) do
        {:ok, text} ->
          if byte_size(text) < @min_plain_text_bytes do
            # Plain fetch returned shell content — likely an SPA. Retry via renderer.
            case fetch_via_renderer(url) do
              {:ok, js_text} when byte_size(js_text) > byte_size(text) -> {:ok, js_text}
              _ -> {:ok, text}
            end
          else
            {:ok, text}
          end

        {:error, _} = err ->
          # Plain fetch failed — give the renderer a shot as last resort.
          case fetch_via_renderer(url) do
            {:ok, text} -> {:ok, text}
            _ -> err
          end
      end
    end
  end

  defp fetch_page(_), do: {:error, :invalid_url}

  defp fetch_plain(url) do
    case Req.get(url,
           headers: [
             {"user-agent",
              "Mozilla/5.0 (compatible; FunSheep StudyBot/1.0; +https://funsheep.app)"}
           ],
           receive_timeout: 15_000,
           max_redirects: 3
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, strip_html(body)}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp needs_js_rendering?(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        host = String.downcase(host)
        Enum.any?(@spa_hosts, fn spa -> host == spa or String.ends_with?(host, "." <> spa) end)

      _ ->
        false
    end
  end

  defp fetch_via_renderer(url) do
    renderer_url = renderer_base_url()

    body = %{
      url: url,
      textOnly: false,
      waitForNetworkIdle: true,
      waitAfterLoad: 2500,
      timeout: 45_000
    }

    case Req.post("#{renderer_url}/render",
           json: body,
           receive_timeout: 60_000
         ) do
      {:ok, %{status: 200, body: %{"content" => content}}} when is_binary(content) ->
        {:ok, strip_html(content)}

      {:ok, %{status: status}} ->
        Logger.warning("[Scraper] Renderer returned status #{status} for #{url}")
        {:error, {:renderer_status, status}}

      {:error, reason} ->
        Logger.debug("[Scraper] Renderer unavailable (#{inspect(reason)}) for #{url}")
        {:error, reason}
    end
  end

  defp renderer_base_url do
    System.get_env("PLAYWRIGHT_RENDERER_URL") ||
      Application.get_env(:fun_sheep, :playwright_renderer_url, "http://localhost:3000")
  end

  defp strip_html(html) do
    html
    |> String.replace(~r/<script[^>]*>.*?<\/script>/si, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/si, "")
    |> String.replace(~r/<nav[^>]*>.*?<\/nav>/si, "")
    |> String.replace(~r/<footer[^>]*>.*?<\/footer>/si, "")
    |> String.replace(~r/<header[^>]*>.*?<\/header>/si, "")
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/&nbsp;/, " ")
    |> String.replace(~r/&amp;/, "&")
    |> String.replace(~r/&lt;/, "<")
    |> String.replace(~r/&gt;/, ">")
    |> String.replace(~r/&#\d+;/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # --- Question Extraction ---

  defp extract_questions_from_text(text, course, source) do
    # Phase 3: AI-first extraction via `FunSheep.Questions.Extractor`
    # with pre-insert gates applied to every question. The April audit
    # of the web path showed only 1/33 processed sources produced
    # anything usable; most of the extraction either hallucinated stems
    # from non-question content or matched partial HTML text that the
    # old regex couldn't handle. The Extractor short-circuits on
    # "this is not a question set" rather than trying to force matches.
    ref = %{source_url: source.url, source_title: source.title}

    ai_questions =
      FunSheep.Questions.Extractor.extract(text,
        subject: course.subject,
        source: :web,
        source_ref: ref,
        grounding_refs: [%{"type" => "url", "id" => source.url}]
      )

    # Regex fallback ONLY when AI returned nothing. Legacy patterns
    # kept for rigidly-formatted sources (Kaplan-style MCQ PDFs) that
    # we've seen the AI mis-extract from. Regex output still passes
    # through the Extractor's gates so the April-audit garbage patterns
    # are blocked.
    if ai_questions != [] do
      ai_questions
    else
      (extract_with_regex(text, source) ++ extract_with_ai(text, course, source))
      |> Enum.map(&legacy_to_gate_shape/1)
      |> Enum.filter(&FunSheep.Questions.Extractor.accept_legacy?/1)
      |> Enum.uniq_by(fn q -> String.downcase(String.trim(q.content)) end)
    end
  end

  # Coerce the legacy regex-extraction shape into the map the Extractor
  # gates expect. The legacy code uses `:source_url`/`:source_title`
  # top-level atoms; the gates don't care about those, only
  # `:content`, `:answer`, `:question_type`, `:options`.
  defp legacy_to_gate_shape(%{} = q), do: q

  defp extract_with_regex(text, source) do
    questions = []

    # Pattern: numbered MC questions with A) B) C) D)
    mc_pattern =
      ~r/(\d+)[.\)]\s+(.+?)\n\s*[Aa][.\)]\s*(.+?)\n\s*[Bb][.\)]\s*(.+?)\n\s*[Cc][.\)]\s*(.+?)\n\s*[Dd][.\)]\s*(.+?)(?=\n\d+[.\)]|\z)/s

    questions =
      questions ++
        (Regex.scan(mc_pattern, text)
         |> Enum.map(fn [_full, _num, question, a, b, c, d] ->
           %{
             content: String.trim(question),
             answer: "",
             question_type: :multiple_choice,
             options: %{
               "A" => String.trim(a),
               "B" => String.trim(b),
               "C" => String.trim(c),
               "D" => String.trim(d)
             },
             difficulty: :medium,
             source_url: source.url,
             source_title: source.title
           }
         end))

    # Pattern: "Question:" or "Q:" prefix
    questions =
      questions ++
        (Regex.scan(
           ~r/(?:Question|Q)\s*\d*\s*[:.]\s*(.+?)\s*(?:Answer|A)\s*[:.]\s*(.+?)(?=(?:Question|Q)\s*\d*\s*[:.>]|\z)/si,
           text
         )
         |> Enum.map(fn [_full, content, answer] ->
           %{
             content: String.trim(content),
             answer: String.trim(answer),
             question_type: :short_answer,
             options: nil,
             difficulty: :medium,
             source_url: source.url,
             source_title: source.title
           }
         end))

    # Pattern: True/False
    questions =
      questions ++
        (Regex.scan(
           ~r/(\d+)[.\)]\s+(.{20,}?)\s*\(?\s*(True|False)\s*\)?/mi,
           text
         )
         |> Enum.map(fn [_full, _num, content, answer] ->
           %{
             content: String.trim(content),
             answer: normalize_tf(answer),
             question_type: :true_false,
             options: nil,
             difficulty: :easy,
             source_url: source.url,
             source_title: source.title
           }
         end))

    questions
  end

  defp extract_with_ai(text, course, source) do
    chunks = chunk_text(text, @ai_chunk_size, @ai_chunk_overlap) |> Enum.take(@ai_max_chunks)

    if chunks == [] do
      []
    else
      chunks
      |> Task.async_stream(
        fn {chunk, idx} -> extract_ai_chunk(chunk, idx, length(chunks), course, source) end,
        max_concurrency: 2,
        timeout: 120_000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, questions} -> questions
        _ -> []
      end)
    end
  end

  defp extract_ai_chunk(chunk, idx, total, course, source) do
    chunk_note =
      if total > 1 do
        "\n\n(This is part #{idx + 1} of #{total} from the same source — extract only questions visible in THIS excerpt.)"
      else
        ""
      end

    prompt = """
    Extract all practice questions from this educational content about #{course.subject}.

    Content from: #{source.title}#{chunk_note}
    ---
    #{chunk}
    ---

    Return a JSON array of questions found. Each question must have:
    - "content": the question text
    - "answer": the correct answer (use letter for MCQ, "True"/"False" for T/F)
    - "question_type": "multiple_choice", "true_false", or "short_answer"
    - "options": for MCQ only, {"A": "...", "B": "...", "C": "...", "D": "..."}
    - "difficulty": "easy", "medium", or "hard"

    If no questions are found, return an empty array [].
    Return ONLY the JSON array.
    """

    case Agents.chat("question_extract", prompt, %{
           source: "web_question_scraper_worker",
           metadata: %{course_id: course.id, source_url: source.url, chunk: idx}
         }) do
      {:ok, response} ->
        parse_ai_questions(response, source)

      {:error, reason} ->
        Logger.warning("[Scraper] AI extraction failed (chunk #{idx}): #{inspect(reason)}")
        []
    end
  end

  # Splits text into overlapping chunks so questions straddling boundaries
  # aren't lost. Returns [{chunk, index}, ...].
  defp chunk_text(text, chunk_size, overlap) when is_binary(text) do
    trimmed = String.trim(text)
    length = String.length(trimmed)

    cond do
      length < 100 ->
        []

      length <= chunk_size ->
        [{trimmed, 0}]

      true ->
        step = max(chunk_size - overlap, 1)

        0..div(length - 1, step)
        |> Enum.map(fn i ->
          start = i * step
          {String.slice(trimmed, start, chunk_size), i}
        end)
        |> Enum.reject(fn {chunk, _} -> String.length(chunk) < 200 end)
    end
  end

  defp parse_ai_questions(text, source) do
    cleaned =
      text
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, questions} when is_list(questions) ->
        Enum.map(questions, fn q ->
          %{
            content: q["content"] || "",
            answer: q["answer"] || "",
            question_type: normalize_type(q["question_type"]),
            options: q["options"],
            difficulty: normalize_diff(q["difficulty"]),
            source_url: source.url,
            source_title: source.title
          }
        end)

      _ ->
        []
    end
  end

  # --- Knowledge-Based Generation (for sources without URLs) ---

  defp generate_from_discovered_knowledge(course) do
    # Get textbook sources (no URL but have titles)
    textbook_sources = Content.list_discovered_sources_by_type(course.id, "textbook")

    if textbook_sources != [] do
      # Use the discovered textbook names to generate better questions
      textbook_names = Enum.map(textbook_sources, & &1.title) |> Enum.join(", ")

      # Scale per-chapter count by source richness — more textbooks discovered
      # means more curricular coverage to draw from. Floor at 5, cap at 20.
      per_chapter = textbook_sources |> length() |> Kernel.+(4) |> min(20) |> max(5)

      Logger.info(
        "[Scraper] Generating #{per_chapter} questions/chapter from known textbooks: #{textbook_names}"
      )

      # Generate questions per chapter using textbook context
      Enum.each(course.chapters, fn chapter ->
        FunSheep.Workers.AIQuestionGenerationWorker.enqueue(course.id,
          chapter_id: chapter.id,
          count: per_chapter,
          mode: "from_curriculum"
        )
      end)
    end
  end

  # --- Question Insertion ---

  defp insert_question(q_data, course) do
    # Try to match the question to a chapter based on content
    chapter_id = match_to_chapter(q_data.content, course.chapters)

    attrs = %{
      content: q_data.content,
      answer: q_data.answer,
      question_type: q_data.question_type,
      options: q_data.options,
      difficulty: q_data.difficulty,
      is_generated: false,
      course_id: course.id,
      chapter_id: chapter_id,
      source_url: q_data[:source_url],
      metadata: %{
        "source" => "web_scrape",
        "source_title" => q_data[:source_title]
      }
    }

    %Question{}
    |> Question.changeset(attrs)
    |> Repo.insert()
  end

  # Match a question to the most relevant chapter by keyword overlap
  defp match_to_chapter(_content, []), do: nil

  defp match_to_chapter(content, chapters) do
    content_lower = String.downcase(content)

    best =
      chapters
      |> Enum.map(fn ch ->
        keywords =
          ch.name
          |> String.downcase()
          |> String.replace(~r/^chapter\s*\d+\s*[:\-]\s*/i, "")
          |> String.split(~r/[\s,\-:]+/)
          |> Enum.reject(&(String.length(&1) < 4))

        hits = Enum.count(keywords, &String.contains?(content_lower, &1))
        {ch, hits}
      end)
      |> Enum.max_by(fn {_ch, hits} -> hits end)

    case best do
      {ch, hits} when hits > 0 -> ch.id
      _ -> hd(chapters).id
    end
  end

  # --- Helpers ---

  defp normalize_tf(val) do
    case String.downcase(String.trim(val)) do
      v when v in ["true", "t"] -> "True"
      _ -> "False"
    end
  end

  defp normalize_type("multiple_choice"), do: :multiple_choice
  defp normalize_type("true_false"), do: :true_false
  defp normalize_type("short_answer"), do: :short_answer
  defp normalize_type("free_response"), do: :free_response
  defp normalize_type(_), do: :short_answer

  defp normalize_diff("easy"), do: :easy
  defp normalize_diff("hard"), do: :hard
  defp normalize_diff(_), do: :medium

  defp broadcast(course_id, data) do
    Phoenix.PubSub.broadcast(
      FunSheep.PubSub,
      "course:#{course_id}",
      {:processing_update, data}
    )
  end
end
