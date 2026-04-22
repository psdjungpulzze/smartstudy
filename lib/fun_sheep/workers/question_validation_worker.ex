defmodule FunSheep.Workers.QuestionValidationWorker do
  @moduledoc """
  Oban worker that validates newly-inserted questions via the
  `question_validator` Interactor assistant.

  Questions are validated in batches of up to `@batch_size` per job. Each job
  takes a list of question ids (typically from one insertion path), loads
  them, sends them as a single prompt, and applies the verdict to each.

  Flow:

    1. Load questions still in `validation_status = :pending`
    2. Call `FunSheep.Questions.Validation.validate_batch/1`
    3. For each verdict:
       * `:passed` → update question, done
       * `:needs_review` → first pass runs a correction retry via
         `question_gen` assistant, then re-validates; second pass persists
         whatever verdict comes back.
       * `:failed` → update question (hidden from student queries)
    4. After the batch, if this job carried a `course_id`, re-check whether
       the course is ready to finalize (all questions settled).
  """

  use Oban.Worker, queue: :ai, max_attempts: 3

  alias FunSheep.{Courses, Repo}
  alias FunSheep.Questions.{Question, Validation}
  alias FunSheep.Interactor.Agents

  import Ecto.Query
  require Logger

  @batch_size 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    question_ids = Map.get(args, "question_ids", [])
    course_id = Map.get(args, "course_id")
    retry_round = Map.get(args, "retry_round", 0)

    questions = load_pending(question_ids)

    if questions == [] do
      Logger.info("[Validation] No pending questions for job #{inspect(question_ids)}")
      maybe_finalize_course(course_id)
      :ok
    else
      questions
      |> Enum.chunk_every(@batch_size)
      |> Enum.each(fn batch -> validate_and_apply(batch, retry_round, course_id) end)

      maybe_finalize_course(course_id)
      :ok
    end
  end

  @doc """
  Enqueues validation for a list of question ids. Call this immediately after
  inserting new questions.
  """
  def enqueue(question_ids, opts \\ [])

  def enqueue([], _opts), do: :ok

  def enqueue(question_ids, opts) when is_list(question_ids) do
    args =
      %{"question_ids" => question_ids}
      |> put_if(:course_id, opts[:course_id])
      |> put_if(:retry_round, opts[:retry_round])

    args
    |> __MODULE__.new()
    |> Oban.insert()
  end

  defp put_if(map, _k, nil), do: map
  defp put_if(map, k, v), do: Map.put(map, to_string(k), v)

  # --- Batch processing ---

  defp load_pending(ids) when is_list(ids) do
    from(q in Question,
      where: q.id in ^ids and q.validation_status == :pending,
      order_by: [asc: q.inserted_at]
    )
    |> Repo.all()
  end

  defp validate_and_apply(questions, retry_round, course_id) do
    case Validation.validate_batch(questions) do
      {:ok, verdicts} ->
        Enum.each(questions, fn q ->
          verdict = Map.get(verdicts, q.id, %{})
          handle_verdict(q, verdict, retry_round, course_id)
        end)

      {:error, reason} ->
        Logger.error(
          "[Validation] Batch failed for course #{course_id}: #{inspect(reason)}. " <>
            "Leaving #{length(questions)} questions as :pending for retry."
        )

        # Don't mark them failed — let Oban retry the job.
        raise "validation batch failed: #{inspect(reason)}"
    end
  end

  defp handle_verdict(question, verdict, retry_round, course_id) do
    case Validation.apply_verdict(question, verdict) do
      {:ok, updated} ->
        maybe_retry_needs_review(updated, verdict, retry_round, course_id)

      {:error, changeset} ->
        Logger.error(
          "[Validation] Failed to persist verdict for #{question.id}: #{inspect(changeset.errors)}"
        )
    end
  end

  # `:needs_review` with retry_round == 0 → attempt ONE auto-correction pass
  # via the question_gen assistant using the validator's suggested fixes.
  # If we still end up in :needs_review after round 1, we leave it there for
  # admin review.
  #
  # Correction runs two extra LLM calls (gen + re-validate), so we only take
  # that cost for fixable issues: wrong recorded answer, or weak/missing
  # explanation. Topic-relevance and completeness issues typically can't be
  # fixed by rewording — route those straight to the review queue.
  defp maybe_retry_needs_review(
         %Question{validation_status: :needs_review} = q,
         verdict,
         0,
         course_id
       ) do
    if correction_worthwhile?(verdict) do
      case attempt_correction(q, verdict) do
        {:ok, corrected_attrs} ->
          {:ok, corrected} =
            q
            |> Question.changeset(Map.put(corrected_attrs, :validation_status, :pending))
            |> Repo.update()

          # Re-enqueue with retry_round=1 so we don't loop forever.
          enqueue([corrected.id], course_id: course_id, retry_round: 1)

        {:error, reason} ->
          Logger.info(
            "[Validation] Correction skipped for #{q.id}: #{inspect(reason)}. Leaving for review."
          )

          :ok
      end
    else
      Logger.debug(
        "[Validation] Correction skipped for #{q.id}: not a fixable verdict; leaving for admin review."
      )

      :ok
    end
  end

  defp maybe_retry_needs_review(_q, _v, _r, _c), do: :ok

  # Only attempt correction when the validator has flagged a concrete fix:
  # a wrong answer with a proposed correction, or a missing/weak explanation
  # with a suggested replacement. Skipping cosmetic or unfixable flags cuts
  # the validator's token burn roughly in half without hurting quality.
  defp correction_worthwhile?(verdict) do
    answer_fixable?(verdict["answer_correct"]) or
      explanation_fixable?(verdict["explanation"])
  end

  defp answer_fixable?(%{"correct" => false, "corrected_answer" => a})
       when is_binary(a) and a != "",
       do: true

  defp answer_fixable?(_), do: false

  defp explanation_fixable?(%{"valid" => false, "suggested_explanation" => e})
       when is_binary(e) and e != "",
       do: true

  defp explanation_fixable?(_), do: false

  # Build a tight correction prompt from the validator's complaint and ask
  # question_gen to return exactly one corrected question in the same JSON
  # shape it uses elsewhere.
  defp attempt_correction(%Question{} = q, verdict) do
    prompt = correction_prompt(q, verdict)

    with {:ok, text} <-
           Agents.chat("question_gen", prompt, %{
             metadata: %{question_id: q.id, kind: "correction"}
           }),
         {:ok, parsed} <- parse_correction(text) do
      {:ok,
       %{
         content: parsed["content"] || q.content,
         answer: parsed["answer"] || q.answer,
         options: parsed["options"] || q.options,
         explanation: parsed["explanation"] || q.explanation
       }}
    end
  end

  defp correction_prompt(q, verdict) do
    issues =
      [
        verdict["topic_relevance_reason"],
        issue_text(verdict["completeness"]),
        answer_fix(verdict["answer_correct"]),
        explanation_fix(verdict["explanation"])
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.map_join("\n- ", & &1)

    """
    A validator flagged this question as needing fixes. Return a corrected
    version that addresses every issue.

    ORIGINAL QUESTION:
    content: #{q.content}
    answer: #{q.answer}
    options: #{Jason.encode!(q.options || %{})}
    explanation: #{q.explanation || "(none)"}

    ISSUES TO FIX:
    - #{issues}

    Return ONLY a single JSON object (no array, no markdown) with:
    {"content": "...", "answer": "...", "options": {...}, "explanation": "..."}
    Keep the same question_type and difficulty. Do not change the topic.
    """
  end

  defp issue_text(%{"passed" => false, "issues" => issues}) when is_list(issues) do
    "Completeness issues: " <> Enum.join(issues, ", ")
  end

  defp issue_text(_), do: nil

  defp answer_fix(%{"correct" => false, "corrected_answer" => a}) when is_binary(a) do
    "Recorded answer is wrong. Correct answer: #{a}"
  end

  defp answer_fix(_), do: nil

  defp explanation_fix(%{"valid" => false, "suggested_explanation" => e}) when is_binary(e) do
    "Explanation is missing/weak. Use: #{e}"
  end

  defp explanation_fix(_), do: nil

  defp parse_correction(text) do
    cleaned =
      text
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, :parse_failed}
    end
  end

  # --- Course finalization ---

  defp maybe_finalize_course(nil), do: :ok

  defp maybe_finalize_course(course_id) do
    pending_count =
      from(q in Question,
        where: q.course_id == ^course_id and q.validation_status == :pending
      )
      |> Repo.aggregate(:count)

    if pending_count == 0 do
      Courses.finalize_after_validation(course_id)
    else
      Logger.debug(
        "[Validation] Course #{course_id} still has #{pending_count} pending questions"
      )

      :ok
    end
  end
end
