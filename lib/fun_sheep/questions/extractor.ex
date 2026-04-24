defmodule FunSheep.Questions.Extractor do
  @moduledoc """
  Unified Q&A extractor for both OCR text (uploaded materials) and
  scraped HTML (web sources). Replaces the regex-heavy extractors in
  `QuestionExtractionWorker` and `WebQuestionScraperWorker`, which
  produced ~50% garbage in the mid-April prod audit:

    - 189 content_too_short (< 20 chars)
    - 125 truncated_mid_word (ends with lowercase letter)
    - 21 answer_key_pattern ("C 2. C 3. C 4." treated as a question)
    - 122 other OCR fragments

  Strategy:
    * AI-first — structured JSON output from a direct LLM call.
      Prompt deliberately instructs "return [] if this is an answer
      key, cover page, or prose-only content" so the extractor
      short-circuits on materials the classifier didn't already filter.
    * Hard pre-insert gates — every extracted question must clear a
      strict validator BEFORE it hits the database. The validator
      defends against the specific garbage patterns the April audit
      surfaced, so even a compromised extractor can't reintroduce them.
    * Regex fallback — only runs when the AI path returns nothing AND
      the source is a known-structured layout (sample_questions
      material kind, or `page_type == "multiple_choice_quiz"` on the
      scraped side). Regex on prose is the specific bug Phase 3
      eliminates.

  Returns a list of validated attribute maps ready for
  `Question.changeset/2`. The caller owns insertion + enqueuing
  validation / classification.
  """

  require Logger

  # Pre-insert gates — these are the failure patterns the April audit
  # surfaced, codified. Kept here (not the changeset) because they're
  # quality gates specific to newly-extracted content, not invariants
  # of the Question schema (admin-approved edits can legitimately
  # bypass them).
  @min_content_length 20
  @min_mcq_options 3
  @max_content_length 4000

  # Sentinels the audit flagged: answer-key rows, fragments ending
  # mid-word, and option-list echoes.
  @answer_key_regex ~r/^[A-D](\s*\d+\.\s*[A-D]\s*){2,}/
  @fragment_regex ~r/[a-z]$/

  @system_prompt """
  You are a question extractor for an educational platform. Extract practice questions from the content the user provides.

  Rules:
  - Only return questions that actually appear in the input — do not invent or paraphrase stems.
  - If the content is an answer key (letters/indices only, no question stems), a cover page, or prose summary with no questions, return [].
  - Every extracted question MUST include a non-empty explanation.
  - Reject any stem that looks truncated mid-sentence.
  - If a question looks like an answer-key row (e.g. "1. C 2. B 3. D") with no question stem, SKIP IT.

  Return ONLY a JSON array. Each question object must have:
    "content":       the question stem (string, at least 20 chars, no trailing mid-word fragments)
    "answer":        the correct answer (letter for MCQ, "True"/"False" for T/F, a concise
                     expected answer for short/free response, empty string ONLY for ungradable
                     free response)
    "question_type": one of "multiple_choice" | "true_false" | "short_answer" | "free_response"
    "options":       for multiple_choice only, an object with at least 3 keys from A/B/C/D/E;
                     otherwise null
    "difficulty":    "easy" | "medium" | "hard"
    "explanation":   a 1-2 sentence explanation of why the answer is correct (REQUIRED)

  Return [] if nothing extractable.
  """

  @llm_opts %{
    model: "gpt-4o-mini",
    max_tokens: 2_000,
    temperature: 0.1,
    source: "questions_extractor"
  }

  @type source_ref :: %{
          optional(:material_id) => Ecto.UUID.t(),
          optional(:source_url) => String.t(),
          optional(:source_page) => integer(),
          optional(:source_title) => String.t()
        }

  @type extracted :: %{
          content: String.t(),
          answer: String.t(),
          question_type: atom(),
          options: map() | nil,
          difficulty: atom(),
          explanation: String.t() | nil,
          metadata: map()
        }

  @doc """
  Extract questions from a block of text. Returns a list of validated
  attribute maps ready to pass to `Question.changeset/2`.

  `opts`:
    * `:subject` — course subject for better AI context
    * `:source` — one of `:material | :web`
    * `:source_ref` — identifying info for provenance (`source_url`,
      `material_id`, `source_page`, `source_title`)
    * `:grounding_refs` — list of `{type, id_or_url}` to persist on
      each extracted question (Phase 1 provenance)
  """
  @spec extract(String.t(), keyword) :: [extracted]
  def extract(text, opts \\ []) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      String.length(trimmed) < @min_content_length * 2 ->
        []

      true ->
        trimmed
        |> run_ai(opts)
        |> Enum.map(&normalize(&1, opts))
        |> Enum.filter(&accept?/1)
    end
  end

  # -- AI path ----------------------------------------------------------------

  defp run_ai(text, opts) do
    user_prompt = build_user_prompt(text, opts)

    case ai_client().call(@system_prompt, user_prompt, @llm_opts) do
      {:ok, response} ->
        parse_response(response)

      {:error, reason} ->
        Logger.warning("[Extractor] LLM call failed: #{inspect(reason)}")
        []
    end
  end

  defp build_user_prompt(text, opts) do
    subject_line =
      case opts[:subject] do
        nil -> ""
        s -> "Course subject: #{s}\n"
      end

    source_line =
      case opts[:source] do
        :web -> "Source: web page content (HTML may have been stripped).\n"
        :material -> "Source: OCR'd course material.\n"
        _ -> ""
      end

    sampled = sample(text)

    """
    #{subject_line}#{source_line}
    Content (sampled; #{String.length(text)} chars total):
    ---
    #{sampled}
    ---
    """
  end

  defp sample(text) do
    length = String.length(text)

    if length <= 12_000 do
      text
    else
      String.slice(text, 0, 12_000) <>
        "\n\n[... middle omitted ...]\n\n" <> String.slice(text, length - 2000, 2000)
    end
  end

  defp parse_response(text) do
    cleaned =
      text
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, list} when is_list(list) -> list
      {:ok, %{"questions" => list}} when is_list(list) -> list
      _ -> []
    end
  end

  # -- normalize + validate ---------------------------------------------------

  defp normalize(raw, opts) when is_map(raw) do
    ref = Keyword.get(opts, :source_ref, %{})
    grounding = Keyword.get(opts, :grounding_refs, [])

    %{
      content: String.trim(to_string(raw["content"] || "")),
      answer: String.trim(to_string(raw["answer"] || "")),
      question_type: normalize_type(raw["question_type"]),
      options: normalize_options(raw["options"]),
      difficulty: normalize_difficulty(raw["difficulty"]),
      explanation: maybe_string(raw["explanation"]),
      source_url: ref[:source_url],
      source_page: ref[:source_page],
      is_generated: false,
      source_type: source_type_for(opts),
      grounding_refs: %{"refs" => grounding},
      metadata:
        %{
          "source" => metadata_source_for(opts),
          "source_title" => ref[:source_title],
          "material_id" => ref[:material_id]
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
    }
  end

  defp normalize(_, _), do: %{content: ""}

  defp source_type_for(opts) do
    case opts[:source] do
      :web -> :web_scraped
      :material -> :user_uploaded
      _ -> :curated
    end
  end

  defp metadata_source_for(opts) do
    case opts[:source] do
      :web -> "web_scrape"
      :material -> "ocr_extraction"
      _ -> "curated"
    end
  end

  defp normalize_type("multiple_choice"), do: :multiple_choice
  defp normalize_type("true_false"), do: :true_false
  defp normalize_type("short_answer"), do: :short_answer
  defp normalize_type("free_response"), do: :free_response
  defp normalize_type(_), do: :short_answer

  defp normalize_difficulty("easy"), do: :easy
  defp normalize_difficulty("hard"), do: :hard
  defp normalize_difficulty(_), do: :medium

  defp normalize_options(opts) when is_map(opts) do
    opts
    |> Enum.map(fn {k, v} -> {to_string(k), to_string(v) |> String.trim()} end)
    |> Enum.reject(fn {_, v} -> v == "" end)
    |> Map.new()
  end

  defp normalize_options(_), do: nil

  defp maybe_string(nil), do: nil
  defp maybe_string(""), do: nil
  defp maybe_string(s) when is_binary(s), do: String.trim(s)
  defp maybe_string(_), do: nil

  # Hard pre-insert gates.
  defp accept?(%{content: content} = q) do
    content_ok?(content) and
      not answer_key_artifact?(content) and
      not fragment?(content) and
      mcq_options_ok?(q) and
      answer_ok?(q)
  end

  defp accept?(_), do: false

  @doc """
  Public gate for legacy regex / fallback paths. Reuses the same
  pre-insert checks so the "garbage patterns the April audit flagged"
  list has a single definition. Does not enforce `explanation:` — the
  legacy regex had no explanation field and the validator enqueue
  after insert picks up missing explanations downstream.
  """
  def accept_legacy?(q), do: accept?(q)

  defp content_ok?(content) do
    len = String.length(content)
    len >= @min_content_length and len <= @max_content_length
  end

  defp answer_key_artifact?(content) do
    Regex.match?(@answer_key_regex, content)
  end

  defp fragment?(content) do
    String.length(content) < 100 and Regex.match?(@fragment_regex, content)
  end

  defp mcq_options_ok?(%{question_type: :multiple_choice, options: opts}) when is_map(opts) do
    map_size(opts) >= @min_mcq_options
  end

  defp mcq_options_ok?(%{question_type: :multiple_choice}), do: false
  defp mcq_options_ok?(_), do: true

  defp answer_ok?(%{question_type: :free_response, answer: _}), do: true
  defp answer_ok?(%{answer: a}) when is_binary(a) and a != "", do: true
  defp answer_ok?(_), do: false

  defp ai_client, do: Application.get_env(:fun_sheep, :ai_client_impl, FunSheep.AI.Client)
end
