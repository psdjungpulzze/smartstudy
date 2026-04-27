defmodule FunSheep.Workers.WebSourceScraperWorker do
  @moduledoc """
  Oban worker that scrapes exactly one DiscoveredSource for questions.

  This is the per-source worker in the coordinator/fan-out pattern.
  `WebQuestionScraperWorker` (the coordinator) enqueues one job per
  pending `DiscoveredSource`; this worker processes it independently.
  Each job can be retried on failure without losing other sources' progress.

  Flow:
    1. Load source by ID
    2. Acquire a domain rate-limit slot (DomainRateLimiter)
    3. Fetch the page (plain → renderer fallback for SPA hosts)
    4. Extract questions (site-specific Floki extractor → AI fallback)
    5. Insert questions, enqueue validation + classification
    6. Mark source processed / failed
  """

  use Oban.Worker,
    queue: :web_scrape,
    max_attempts: 3,
    unique: [period: 3600, fields: [:worker, :args]]

  alias FunSheep.{Content, Courses, Repo}
  alias FunSheep.Questions.{Question, Deduplicator}
  alias FunSheep.Scraper.{DomainRateLimiter, SiteExtractor, SourceReputation}

  require Logger

  @system_prompt "You are a question extractor for an educational platform. Extract practice questions from the educational web content provided. Return ONLY a JSON array. If no extractable questions are found, return []. Do not invent questions."

  @llm_opts %{
    model: "gpt-4o-mini",
    max_tokens: 4_000,
    temperature: 0.1,
    source: "web_source_scraper_worker"
  }

  @max_page_size 100_000

  @ai_chunk_size 24_000
  @ai_max_chunks 8
  @ai_chunk_overlap 1_000

  # Minimum text length before falling back to Playwright renderer
  @min_plain_text_bytes 1_500

  # Renderer output below this size is flagged as suspicious (SPA shell / anti-bot wall)
  @renderer_small_output_bytes 1_500

  # Maximum binary document size (50 MB)
  @max_doc_bytes 50 * 1024 * 1024

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

  @document_extensions ~w(.docx .pptx .xlsx)
  @skip_extensions ~w(.doc .ppt .xls .zip .mp4 .mp3 .wav .png .jpg .jpeg .gif .svg)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => source_id}}) do
    source = Content.get_discovered_source!(source_id)
    course = Courses.get_course_with_chapters!(source.course_id)

    # Respect per-domain rate limits before fetching
    DomainRateLimiter.acquire(source.url)

    count = do_scrape_and_extract(source, course)

    :telemetry.execute(
      [:fun_sheep, :scraper, :source_complete],
      %{questions_extracted: count},
      %{source_id: source.id, url: source.url, outcome: if(count > 0, do: :ok, else: :empty)}
    )

    Phoenix.PubSub.broadcast(
      FunSheep.PubSub,
      "course:#{source.course_id}:pipeline",
      {:source_complete, %{source_id: source.id, url: source.url, questions_extracted: count}}
    )

    :ok
  end

  @doc """
  Enqueues one scraping job for the given discovered source.
  Returns `{:ok, job}` or `{:error, changeset}`.
  """
  def enqueue_for_source(%{id: source_id}) do
    %{"source_id" => source_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  # --- Core scraping ---

  defp do_scrape_and_extract(source, course) do
    cond do
      pdf_url?(source.url) or document_url?(source.url) ->
        ext = url_ext(source.url)
        Logger.info("[SourceScraper] Binary doc (#{ext}), routing to pipeline: #{source.url}")
        attach_binary_source(source, course)

      skip_url?(source.url) ->
        Logger.debug(
          "[SourceScraper] Skipping unsupported format (#{url_ext(source.url)}): #{source.url}"
        )

        Content.update_discovered_source(source, %{status: "skipped"})
        0

      true ->
        Content.update_discovered_source(source, %{status: "scraping"})

        case fetch_page(source.url) do
          {:ok, raw_html} ->
            stripped = strip_html(raw_html)

            Content.update_discovered_source(source, %{
              scraped_text: safe_slice(stripped, @max_page_size),
              content_size_bytes: byte_size(raw_html),
              status: "scraped"
            })

            questions = extract_questions_from_html(raw_html, stripped, course, source)

            grounding_ref = %{"type" => "url", "id" => source.url, "title" => source.title}

            {inserted, inserted_ids} =
              Enum.reduce(questions, {0, []}, fn q, {count, ids} ->
                case insert_question(q, course, grounding_ref) do
                  {:ok, inserted_q} -> {count + 1, [inserted_q.id | ids]}
                  {:error, _} -> {count, ids}
                end
              end)

            FunSheep.Workers.QuestionValidationWorker.enqueue(inserted_ids,
              course_id: course.id,
              queue: :web_validation
            )

            FunSheep.Workers.QuestionClassificationWorker.enqueue_for_questions(inserted_ids)

            Content.update_discovered_source(source, %{
              status: "processed",
              questions_extracted: inserted
            })

            inserted

          {:error, reason} ->
            error_msg = inspect(reason)
            Logger.warning("[SourceScraper] Failed to fetch #{source.url}: #{error_msg}")

            Content.update_discovered_source(source, %{
              status: "failed",
              error_message: error_msg
            })

            0
        end
    end
  end

  # --- Binary document handling ---

  defp attach_binary_source(source, course) do
    filename =
      (URI.parse(source.url).path || "document")
      |> String.split("/")
      |> List.last()
      |> URI.decode()

    ext = url_ext(source.url)
    content_type = content_type_for_ext(ext)

    with {:ok, bytes} <- fetch_document_bytes(source.url),
         storage_key = "materials/#{Ecto.UUID.generate()}/#{filename}",
         {:ok, _} <- FunSheep.Storage.put(storage_key, bytes, content_type: content_type),
         {:ok, material} <-
           FunSheep.Content.create_uploaded_material(%{
             file_path: storage_key,
             file_name: filename,
             file_type: content_type,
             file_size: byte_size(bytes),
             material_kind: :sample_questions,
             user_role_id: course.created_by_id,
             course_id: course.id,
             ocr_status: :pending
           }) do
      FunSheep.Workers.OCRMaterialWorker.new(%{material_id: material.id, course_id: course.id})
      |> Oban.insert()

      Content.update_discovered_source(source, %{status: "processed"})

      Logger.info(
        "[SourceScraper] Document queued for pipeline: material=#{material.id}, source=#{source.id}, ext=#{ext}"
      )

      0
    else
      {:error, reason} ->
        error_msg = inspect(reason)

        Logger.warning(
          "[SourceScraper] Document download/storage failed for #{source.url}: #{error_msg}"
        )

        Content.update_discovered_source(source, %{status: "failed", error_message: error_msg})
        0
    end
  end

  defp fetch_document_bytes(url) do
    case Req.get(url,
           headers: [
             {"user-agent",
              "Mozilla/5.0 (compatible; FunSheep StudyBot/1.0; +https://funsheep.app)"}
           ],
           receive_timeout: 60_000,
           max_redirects: 5
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        if byte_size(body) > @max_doc_bytes do
          {:error, {:document_too_large, byte_size(body)}}
        else
          {:ok, body}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp content_type_for_ext(".pdf"), do: "application/pdf"

  defp content_type_for_ext(".docx"),
    do: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

  defp content_type_for_ext(".pptx"),
    do: "application/vnd.openxmlformats-officedocument.presentationml.presentation"

  defp content_type_for_ext(".xlsx"),
    do: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

  defp content_type_for_ext(_), do: "application/octet-stream"

  # --- Page fetching ---

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
            case fetch_via_renderer(url) do
              {:ok, js_text} when byte_size(js_text) > byte_size(text) -> {:ok, js_text}
              _ -> {:ok, text}
            end
          else
            {:ok, text}
          end

        {:error, _} = err ->
          case fetch_via_renderer(url) do
            {:ok, text} -> {:ok, text}
            _ -> err
          end
      end
    end
  end

  defp fetch_page(_), do: {:error, :invalid_url}

  defp fetch_plain(url) do
    opts = [
      headers: [
        {"user-agent",
         "Mozilla/5.0 (compatible; FunSheep StudyBot/1.0; +https://funsheep.app)"}
      ],
      receive_timeout: 15_000,
      max_redirects: 3
    ] ++ extra_req_opts()

    case Req.get(url, opts) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Allows tests to inject `plug: {Req.Test, __MODULE__}` without hitting the network.
  defp extra_req_opts, do: Application.get_env(:fun_sheep, :scraper_req_opts, [])

  defp needs_js_rendering?(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        h = String.downcase(host)
        Enum.any?(@spa_hosts, fn spa -> h == spa or String.ends_with?(h, "." <> spa) end)

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

    case Req.post("#{renderer_url}/render", [json: body, receive_timeout: 60_000] ++ extra_req_opts()) do
      {:ok, %{status: 200, body: %{"content" => content}}} when is_binary(content) ->
        if byte_size(content) < @renderer_small_output_bytes do
          Logger.warning(
            "[SourceScraper] Renderer small output (#{byte_size(content)} bytes) for #{url} — possible SPA shell"
          )
        end

        {:ok, content}

      {:ok, %{status: status}} ->
        Logger.warning("[SourceScraper] Renderer status #{status} for #{url}")
        {:error, {:renderer_status, status}}

      {:error, reason} ->
        Logger.debug("[SourceScraper] Renderer unavailable (#{inspect(reason)}) for #{url}")
        {:error, reason}
    end
  end

  # Pick a renderer URL at random for horizontal scaling. Comma-separated
  # PLAYWRIGHT_RENDERER_URLS env var (or single PLAYWRIGHT_RENDERER_URL).
  defp renderer_base_url do
    urls =
      Application.get_env(
        :fun_sheep,
        :playwright_renderer_urls,
        ["http://localhost:3000"]
      )

    Enum.random(urls)
  end

  # --- HTML/text stripping ---

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

  # --- Question extraction ---

  defp extract_questions_from_html(raw_html, stripped, course, source) do
    ref = %{source_url: source.url, source_title: source.title}

    opts = [
      subject: course.subject,
      source: :web,
      source_ref: ref,
      grounding_refs: [%{"type" => "url", "id" => source.url}]
    ]

    case SiteExtractor.extract(raw_html, source.url, opts) do
      {:ok, [_ | _] = questions} -> questions
      _ -> extract_questions_from_text(stripped, course, source)
    end
  end

  defp extract_questions_from_text(text, course, source) do
    ref = %{source_url: source.url, source_title: source.title}

    ai_questions =
      FunSheep.Questions.Extractor.extract(text,
        subject: course.subject,
        source: :web,
        source_ref: ref,
        grounding_refs: [%{"type" => "url", "id" => source.url}]
      )

    if ai_questions != [] do
      ai_questions
    else
      (extract_with_regex(text, source) ++ extract_with_ai(text, course, source))
      |> Enum.map(&legacy_to_gate_shape/1)
      |> Enum.filter(&FunSheep.Questions.Extractor.accept_legacy?/1)
      |> Enum.uniq_by(fn q -> String.downcase(String.trim(q.content)) end)
    end
  end

  defp legacy_to_gate_shape(%{} = q), do: q

  defp extract_with_regex(text, source) do
    mc_pattern =
      ~r/(\d+)[.\)]\s+(.+?)\n\s*[Aa][.\)]\s*(.+?)\n\s*[Bb][.\)]\s*(.+?)\n\s*[Cc][.\)]\s*(.+?)\n\s*[Dd][.\)]\s*(.+?)(?=\n\d+[.\)]|\z)/s

    mc_questions =
      Regex.scan(mc_pattern, text)
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
      end)

    qa_questions =
      Regex.scan(
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
      end)

    tf_questions =
      Regex.scan(~r/(\d+)[.\)]\s+(.{20,}?)\s*\(?\s*(True|False)\s*\)?/mi, text)
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
      end)

    mc_questions ++ qa_questions ++ tf_questions
  end

  defp extract_with_ai(text, course, source) do
    chunks = chunk_text(text, @ai_chunk_size, @ai_chunk_overlap) |> Enum.take(@ai_max_chunks)

    if chunks == [] do
      []
    else
      chunks
      |> Task.async_stream(
        fn {chunk, idx} -> extract_ai_chunk(chunk, idx, length(chunks), course, source) end,
        max_concurrency: 4,
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

    case ai_client().call(@system_prompt, prompt, @llm_opts) do
      {:ok, response} ->
        parse_ai_questions(response, source)

      {:error, reason} ->
        Logger.warning("[SourceScraper] AI extraction failed (chunk #{idx}): #{inspect(reason)}")
        []
    end
  end

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

  # --- Question insertion ---

  defp insert_question(q_data, course, grounding_ref) do
    chapter_id = match_to_chapter(q_data.content, course.chapters)
    fingerprint = Deduplicator.fingerprint(q_data.content)
    source_url = q_data[:source_url]
    source_tier = SourceReputation.tier(source_url)

    grounding_refs =
      if grounding_ref, do: %{"refs" => [grounding_ref]}, else: %{}

    attrs = %{
      content: q_data.content,
      answer: q_data.answer,
      question_type: q_data.question_type,
      options: q_data.options,
      difficulty: q_data.difficulty,
      is_generated: false,
      source_type: :web_scraped,
      generation_mode: "from_web_context",
      grounding_refs: grounding_refs,
      course_id: course.id,
      chapter_id: chapter_id,
      source_url: source_url,
      content_fingerprint: fingerprint,
      source_tier: source_tier,
      metadata: %{
        "source" => "web_scrape",
        "source_title" => q_data[:source_title]
      }
    }

    %Question{}
    |> Question.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing)
  end

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
      |> Enum.max_by(fn {_, hits} -> hits end)

    case best do
      {ch, hits} when hits > 0 -> ch.id
      _ -> nil
    end
  end

  # --- Normalization helpers ---

  defp normalize_tf("True"), do: "True"
  defp normalize_tf("true"), do: "True"
  defp normalize_tf(_), do: "False"

  defp normalize_type("multiple_choice"), do: :multiple_choice
  defp normalize_type("true_false"), do: :true_false
  defp normalize_type("short_answer"), do: :short_answer
  defp normalize_type("free_response"), do: :free_response
  defp normalize_type(_), do: :short_answer

  defp normalize_diff("easy"), do: :easy
  defp normalize_diff("hard"), do: :hard
  defp normalize_diff(_), do: :medium

  defp safe_slice(text, max) when is_binary(text) do
    if String.valid?(text), do: String.slice(text, 0, max), else: ""
  end

  defp url_ext(url) when is_binary(url) do
    uri = URI.parse(url)
    path = uri.path || ""
    path |> Path.extname() |> String.downcase()
  end

  defp url_ext(_), do: ""

  defp pdf_url?(url), do: url_ext(url) == ".pdf"
  defp document_url?(url), do: url_ext(url) in @document_extensions
  defp skip_url?(url), do: url_ext(url) in @skip_extensions

  defp ai_client, do: Application.get_env(:fun_sheep, :ai_client_impl, FunSheep.AI.Client)
end
