defmodule FunSheep.Questions.Validation do
  @moduledoc """
  Validates generated questions against 5 dimensions before they reach students:

    1. Topic relevance — is this question actually on-topic for the chapter/course?
    2. Completeness — does it contain everything the student needs to answer?
    3. Categorization — is it mapped to the correct chapter/section?
    4. Answer correctness — is the recorded answer right?
    5. Explanation — is the explanation accurate and pedagogically useful?

  A question is only shown to students when `validation_status == :passed`.

  This module builds the prompt, calls the direct LLM client, parses the
  structured response, and applies the verdict.
  """

  alias FunSheep.{Courses, Repo}
  alias FunSheep.Questions.Question

  require Logger

  @passed_threshold 95.0
  @review_threshold 70.0

  @llm_opts %{
    model: "gpt-4o-mini",
    max_tokens: 8_000,
    temperature: 0.1,
    source: "questions_validation_context"
  }

  # Interactor only applies `assistant_attrs` on first provision, so the only
  # safe way to push a config change (model, prompt, token cap) is to register
  # under a new name. Prior names: "question_validator" (gpt-4o/4000 tokens),
  # "question_validator_v2" (gpt-4o-mini/2000 tokens),
  # "question_quality_reviewer" (gpt-4o-mini/2000 tokens — caused the
  # 2026-04-22 zombie loop on course d44628ca: 10-question batches' verdicts
  # exceeded 2000 tokens, OpenAI truncated mid-stream, parse_failed kept
  # firing in a loop driven by the sweeper). If config must change again,
  # pick another descriptive name rather than reusing a prior one.
  @assistant_name "question_quality_reviewer_v3"

  @assistant_system_prompt """
  You are a strict curriculum validator. Your job is to evaluate whether each
  question in a batch is ready to be shown to a student studying for an exam.

  For EVERY question, assess FIVE dimensions and return a structured JSON
  verdict:

    1. topic_relevance_score (0-100) — on-topic for the chapter and grade.
       95+ means fully test-worthy. <95 means off-topic, trivial, or
       misaligned with the chapter.
    2. completeness — does it contain everything the student needs to
       answer? Multiple choice must have options. Questions referencing
       visuals must attach them. Short answer must be unambiguous.
    3. categorization — which chapter id best fits the question.
    4. answer_correct — whether the recorded answer is right. If wrong,
       return the corrected answer.
    5. explanation — whether the explanation is accurate and pedagogically
       useful at the student's grade level. If missing or weak, return a
       better one.

  VERDICT RULES:
    * approve — topic_relevance_score >= 95, completeness passed,
      answer correct, explanation valid.
    * needs_fix — fixable issue with topic_relevance_score >= 70.
    * reject — off-topic (<70), unfixable, or fundamentally broken.

  OUTPUT FORMAT:
  Return ONLY a JSON array. No prose, no markdown fences. Each element MUST
  include the question's id plus every field in the verdict schema.
  """

  @doc """
  Validates a list of questions in one Interactor round-trip.

  Returns `{:ok, verdicts}` where `verdicts` is a list of maps keyed by
  question id. Falls back to per-question validation on parse errors.
  """
  @spec validate_batch([Question.t()]) :: {:ok, map()} | {:error, term()}
  def validate_batch([]), do: {:ok, %{}}

  def validate_batch(questions) when is_list(questions) do
    course = load_course(hd(questions).course_id)
    user_prompt = build_batch_user_prompt(course, questions)

    case ai_client().call(@assistant_system_prompt, user_prompt, @llm_opts) do
      {:ok, response} ->
        parse_batch_response(response, questions)

      {:error, reason} = err ->
        Logger.error("[Validation] LLM call failed: #{inspect(reason)}")
        err
    end
  end

  @doc """
  Applies a verdict map to the given question. Returns the updated question
  or an error changeset. Verdict shape:

      %{
        "topic_relevance_score" => 0..100,
        "topic_relevance_reason" => String.t(),
        "completeness" => %{"passed" => boolean(), "issues" => [String.t()]},
        "categorization" => %{"suggested_chapter_id" => String.t() | nil, "confidence" => 0..100},
        "answer_correct" => %{"correct" => boolean(), "corrected_answer" => String.t() | nil},
        "explanation" => %{"valid" => boolean(), "suggested_explanation" => String.t() | nil},
        "verdict" => "approve" | "needs_fix" | "reject"
      }
  """
  @spec apply_verdict(Question.t(), map()) ::
          {:ok, Question.t()} | {:error, Ecto.Changeset.t()}
  def apply_verdict(%Question{} = question, verdict) when is_map(verdict) do
    # Phase 7: a verdict produced by `missing_verdict/0` means the
    # validator LLM returned nothing for this row. Treat that as a
    # transient validator failure — leave the question :pending and
    # let the StuckValidationSweeperWorker re-queue it, INSTEAD of
    # burning a genuine :failed slot on a row that has never been
    # properly reviewed. The April audit had 65 such rows permanently
    # marked :failed for a content issue that was really a validator
    # bug.
    if validator_produced_no_verdict?(verdict) do
      mark_pending_retry(question, verdict)
    else
      {status, score} = derive_status(verdict)

      course = load_course(question.course_id)
      valid_chapter_ids = MapSet.new(course.chapters, & &1.id)

      attrs =
        %{
          validation_status: status,
          validation_score: score,
          validation_report: verdict,
          validated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
        |> maybe_accept_categorization(verdict, valid_chapter_ids)
        |> maybe_accept_explanation(question, verdict)

      question
      |> Question.changeset(attrs)
      |> Repo.update()
    end
  end

  # Identity check against the marker that `parse_batch_response/2`
  # inserts when the LLM response lacked a verdict for a specific
  # question. The worker sees `validation_status: :pending` and
  # `validation_attempts` incremented, so the cap kicks in after a
  # handful of genuinely-stuck tries.
  defp validator_produced_no_verdict?(%{
         "completeness" => %{"issues" => ["no verdict returned"]}
       }),
       do: true

  defp validator_produced_no_verdict?(%{
         "topic_relevance_reason" => "Assistant did not return a verdict for this question"
       }),
       do: true

  defp validator_produced_no_verdict?(_), do: false

  defp mark_pending_retry(question, verdict) do
    question
    |> Question.changeset(%{
      validation_status: :pending,
      validation_score: nil,
      validation_report: verdict,
      # validated_at deliberately NOT touched — the sweeper uses it
      # and nil means "never validated".
      validation_attempts: (question.validation_attempts || 0) + 1
    })
    |> Repo.update()
  end

  @doc """
  Returns the numeric thresholds used to classify verdicts. Exposed so tests
  and the worker can reason about retry boundaries.
  """
  def thresholds, do: %{passed: @passed_threshold, review: @review_threshold}

  defp ai_client, do: Application.get_env(:fun_sheep, :ai_client_impl, FunSheep.AI.Client)

  @behaviour FunSheep.Interactor.AssistantSpec

  @doc """
  Configuration used to register the `question_quality_reviewer` assistant on
  Interactor. Exposed for scripts/preflight checks.
  """
  @impl FunSheep.Interactor.AssistantSpec
  def assistant_attrs do
    %{
      name: @assistant_name,
      description:
        "Validates generated questions across topic relevance, completeness, categorization, answer correctness, and explanation quality.",
      system_prompt: @assistant_system_prompt,
      llm_provider: "openai",
      llm_model: "gpt-4o-mini",
      # 2000 tokens truncated 5+ question verdicts mid-stream and produced
      # bare `[` responses. 8000 fits a 5-question batch comfortably with
      # full reasons + suggested explanations. Keep paired with the smaller
      # batch size in QuestionValidationWorker.
      llm_config: %{temperature: 0.1, max_tokens: 8000},
      metadata: %{app: "funsheep", role: "question_validator"}
    }
  end

  # --- Prompt building ---

  defp load_course(course_id) do
    Courses.get_course_with_chapters!(course_id)
  end

  defp build_batch_user_prompt(course, questions) do
    chapters_block =
      course.chapters
      |> Enum.map_join("\n", fn ch ->
        "- id=#{ch.id} | name=#{ch.name} | position=#{ch.position}"
      end)

    questions_block =
      questions
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {q, idx} -> format_question(idx, q) end)

    """
    COURSE: #{course.name} (#{course.subject}, grade #{course.grade})

    AVAILABLE CHAPTERS:
    #{chapters_block}

    QUESTIONS TO VALIDATE:

    #{questions_block}

    Return ONLY the JSON array. No prose, no markdown fences.
    """
  end

  defp format_question(idx, q) do
    chapter_line =
      case q.chapter_id do
        nil -> "  (no chapter assigned)"
        id -> "  chapter_id: #{id}"
      end

    options_line =
      case q.options do
        nil -> ""
        opts when map_size(opts) == 0 -> ""
        opts -> "  options: #{Jason.encode!(opts)}\n"
      end

    explanation_line =
      case q.explanation do
        nil -> "  explanation: (none)\n"
        "" -> "  explanation: (none)\n"
        text -> "  explanation: #{text}\n"
      end

    """
    Question ##{idx}
      id: #{q.id}
      type: #{q.question_type}
      difficulty: #{q.difficulty}
    #{chapter_line}
      content: #{q.content}
    #{options_line}  answer: #{q.answer}
    #{explanation_line}
    """
  end

  # --- Response parsing ---

  defp parse_batch_response(text, questions) when is_binary(text) do
    with {:ok, decoded} <- extract_json(text),
         verdicts when is_list(verdicts) <- decoded do
      by_id = Map.new(verdicts, &{&1["id"], &1})

      # Default to :needs_review for any question the assistant skipped. This
      # avoids silently auto-passing questions that were never validated.
      full =
        Enum.reduce(questions, %{}, fn q, acc ->
          case Map.get(by_id, q.id) do
            nil -> Map.put(acc, q.id, missing_verdict())
            verdict -> Map.put(acc, q.id, verdict)
          end
        end)

      {:ok, full}
    else
      _ ->
        Logger.error("[Validation] Unparseable response: #{String.slice(text || "", 0, 300)}")

        {:error, :parse_failed}
    end
  end

  defp parse_batch_response(_, _), do: {:error, :parse_failed}

  defp extract_json(text) do
    cleaned =
      text
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    Jason.decode(cleaned)
  end

  defp missing_verdict do
    %{
      "topic_relevance_score" => 0,
      "topic_relevance_reason" => "Assistant did not return a verdict for this question",
      "completeness" => %{"passed" => false, "issues" => ["no verdict returned"]},
      "categorization" => %{"suggested_chapter_id" => nil, "confidence" => 0},
      "answer_correct" => %{"correct" => false, "corrected_answer" => nil},
      "explanation" => %{"valid" => false, "suggested_explanation" => nil},
      "verdict" => "needs_fix"
    }
  end

  # --- Verdict application ---

  defp derive_status(%{"verdict" => "approve"} = v) do
    score = topic_score(v)

    if score >= @passed_threshold do
      {:passed, score}
    else
      # Assistant said approve but score is low — trust the score, flag for review
      {:needs_review, score}
    end
  end

  defp derive_status(%{"verdict" => "needs_fix"} = v) do
    score = topic_score(v)

    cond do
      score >= @review_threshold -> {:needs_review, score}
      true -> {:failed, score}
    end
  end

  defp derive_status(%{"verdict" => "reject"} = v), do: {:failed, topic_score(v)}
  defp derive_status(v), do: {:needs_review, topic_score(v)}

  defp topic_score(%{"topic_relevance_score" => s}) when is_number(s), do: s * 1.0
  defp topic_score(_), do: 0.0

  # Apply suggested chapter only when the assistant is confident it belongs
  # elsewhere (confidence >= 80), we have a concrete chapter id, AND the id
  # actually exists on this course. The validator occasionally hallucinates
  # UUIDs — persisting them triggers questions_chapter_id_fkey violations
  # that leave the question stuck in :pending forever (seen 2026-04-22).
  defp maybe_accept_categorization(
         attrs,
         %{
           "categorization" => %{
             "suggested_chapter_id" => new_id,
             "confidence" => conf
           }
         },
         valid_chapter_ids
       )
       when is_binary(new_id) and is_number(conf) and conf >= 80 do
    if MapSet.member?(valid_chapter_ids, new_id) do
      Map.put(attrs, :chapter_id, new_id)
    else
      Logger.warning(
        "[Validation] Ignoring suggested_chapter_id #{inspect(new_id)}: not in course chapters"
      )

      attrs
    end
  end

  defp maybe_accept_categorization(attrs, _, _), do: attrs

  # If the question has no explanation yet and the validator provided a valid
  # one, accept it. Never overwrite an existing explanation — those go through
  # the :needs_review queue.
  defp maybe_accept_explanation(attrs, %Question{explanation: cur}, %{
         "explanation" => %{"valid" => true, "suggested_explanation" => text}
       })
       when (is_nil(cur) or cur == "") and is_binary(text) and text != "" do
    Map.put(attrs, :explanation, text)
  end

  defp maybe_accept_explanation(attrs, _, _), do: attrs
end
