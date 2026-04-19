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

  use Oban.Worker, queue: :ai, max_attempts: 2

  alias FunSheep.{Content, Courses, Repo}
  alias FunSheep.Questions.Question
  alias FunSheep.Interactor.Agents

  require Logger

  @max_sources_per_run 10
  @max_page_size 100_000

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
      total_questions =
        Enum.reduce(sources, 0, fn source, count ->
          result = scrape_and_extract(source, course)
          count + result
        end)

      Logger.info(
        "[Scraper] Extracted #{total_questions} questions from #{length(sources)} sources"
      )

      Courses.update_course(course, %{
        processing_step: "Extracted #{total_questions} questions from web sources"
      })

      broadcast(course_id, %{
        step: "Extracted #{total_questions} questions from web sources",
        questions_scraped: total_questions
      })

      :ok
    end
  end

  @doc """
  Enqueues a scraping job for a course.
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
        inserted =
          Enum.reduce(questions, 0, fn q, count ->
            case insert_question(q, course) do
              {:ok, _} -> count + 1
              {:error, _} -> count
            end
          end)

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
    case Req.get(url,
           headers: [
             {"user-agent",
              "Mozilla/5.0 (compatible; FunSheep StudyBot/1.0; +https://funsheep.app)"}
           ],
           receive_timeout: 15_000,
           max_redirects: 3
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        # Strip HTML tags to get plain text
        text = strip_html(body)
        {:ok, text}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_page(_), do: {:error, :invalid_url}

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
    # First try regex-based extraction (fast, no API calls)
    regex_questions = extract_with_regex(text, source)

    # Then use AI to extract more questions from the remaining text
    ai_questions = extract_with_ai(text, course, source)

    # Combine, deduplicate
    (regex_questions ++ ai_questions)
    |> Enum.uniq_by(fn q -> String.downcase(String.trim(q.content)) end)
    |> Enum.reject(fn q -> String.length(q.content) < 15 end)
  end

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
    # Truncate text for AI processing
    truncated = String.slice(text, 0, 6000)

    if String.length(truncated) < 100 do
      []
    else
      prompt = """
      Extract all practice questions from this educational content about #{course.subject}.

      Content from: #{source.title}
      ---
      #{truncated}
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
             metadata: %{course_id: course.id, source_url: source.url}
           }) do
        {:ok, response} ->
          parse_ai_questions(response, source)

        {:error, reason} ->
          Logger.warning("[Scraper] AI extraction failed: #{inspect(reason)}")
          []
      end
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

      Logger.info("[Scraper] Generating questions from known textbooks: #{textbook_names}")

      # Generate questions per chapter using textbook context
      Enum.each(course.chapters, fn chapter ->
        FunSheep.Workers.AIQuestionGenerationWorker.enqueue(course.id,
          chapter_id: chapter.id,
          count: 5,
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
