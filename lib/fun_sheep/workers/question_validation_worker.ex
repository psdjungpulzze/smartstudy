defmodule FunSheep.Workers.QuestionValidationWorker do
  @moduledoc """
  Oban worker that validates newly-inserted questions via the
  `question_quality_reviewer` Interactor assistant.

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

  # `unique` prevents accidental duplicate enqueues of the same batch from
  # stacking on the :ai queue. Order is normalized on enqueue so two callers
  # passing the same ids in different order collapse to one job.
  # Runs on its own `:ai_validation` queue so it doesn't compete with
  # question generation / classification / extraction / scraping for slots
  # on the general `:ai` queue. See `config/runtime.exs` for prod concurrency.
  use Oban.Worker,
    queue: :ai_validation,
    max_attempts: 3,
    unique: [
      period: 120,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias FunSheep.{Courses, Repo}
  alias FunSheep.Courses.Course
  alias FunSheep.Questions.{Question, Validation}

  import Ecto.Query
  require Logger

  @correction_system_prompt "You are an expert question editor. Fix validation issues in educational questions while preserving the topic and difficulty. Return ONLY a single JSON object (no array, no markdown)."

  @correction_llm_opts %{
    model: "gpt-4o-mini",
    max_tokens: 1_000,
    temperature: 0.2,
    source: "question_validation_worker"
  }

  # How many questions each Interactor round-trip validates. Dropped from 10
  # to 5 on 2026-04-22 because 10-question verdicts (with reasons + suggested
  # explanations) regularly exceeded the validator assistant's max_tokens
  # budget, causing OpenAI to truncate mid-stream and emit unparseable JSON
  # (the `[`-only response that drove course d44628ca's zombie loop).
  @batch_size 5

  # How many parse_failed attempts a question survives before we mark it
  # `:failed` honestly with an error report. Without this cap the sweeper
  # keeps re-enqueueing questions whose batches always parse-fail (e.g.
  # malformed source data the LLM can't summarize) forever — students see
  # "Course is still processing" for days. 3 attempts ≈ 45 minutes of
  # sweeper retries; if it hasn't parsed by then it isn't going to.
  @max_validation_attempts 3

  # How many questions go into one Oban job. The worker chunks internally
  # into `@batch_size` sub-batches, so an outer chunk of 50 means 5 Interactor
  # calls per job. Bounded so that if the job is discarded after max_attempts,
  # at most this many questions need recovery by
  # `StuckValidationSweeperWorker` — instead of thousands (the 2026-04-22
  # incident had single jobs holding 3398 ids).
  @outer_chunk_size 50

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    question_ids = Map.get(args, "question_ids", [])
    course_id = Map.get(args, "course_id")
    retry_round = Map.get(args, "retry_round", 0)

    course_cancelled =
      course_id &&
        case Repo.get(Course, course_id) do
          nil -> false
          course -> course.processing_status == "cancelled"
        end

    if course_cancelled do
      Logger.info("[Validation] Skipped cancelled course #{course_id}")
      # Mark remaining :pending questions as :failed so the sweeper stops
      # re-enqueuing them every 15 minutes. Without this, the sweeper sees
      # :pending questions for the cancelled course, enqueues ~15 jobs per
      # sweep, those jobs skip and leave the questions :pending — a permanent
      # storm that exhausts the DB connection pool for all other workers.
      cleanup_cancelled_course_questions(course_id)
      :ok
    else

    questions = load_pending(question_ids)

    if questions == [] do
      Logger.info("[Validation] No pending questions for job #{inspect(question_ids)}")
      maybe_finalize_course(course_id)
      :ok
    else
      # For SAT courses, run lightweight structural pre-validation before
      # sending to the LLM validator. Questions that fail structural checks
      # (wrong option count, empty stem, etc.) are marked :failed immediately
      # with a clear reason — no LLM call needed, cheaper and faster.
      course =
        if course_id do
          Repo.get(Course, course_id)
        end

      questions =
        if course && uses_structural_validation?(course) do
          pre_filter_sat_questions(questions, course)
        else
          questions
        end

      batches = Enum.chunk_every(questions, @batch_size)

      # Track sub-batch outcomes so we can distinguish "partial success"
      # (at least one batch worked — commit progress, stuck ones re-enqueued
      # immediately) from "total failure" (every batch failed — raise so Oban
      # retries the whole job with backoff).
      outcomes = Enum.map(batches, &validate_and_apply(&1, retry_round, course_id))

      maybe_finalize_course(course_id)

      if outcomes != [] and Enum.all?(outcomes, &match?({:error, _}, &1)) do
        # Every sub-batch failed. Interactor is likely down or misconfigured —
        # raising lets Oban retry the whole job with backoff. No point
        # re-enqueueing individual questions here since the whole job will retry.
        raise "validation job failed: all #{length(batches)} sub-batches errored"
      else
        # Partial failure: some batches succeeded. Re-enqueue questions from
        # failed sub-batches immediately (60s delay) rather than waiting for
        # the sweeper's 30-minute stuck threshold.
        retry_ids =
          Enum.flat_map(outcomes, fn
            {:error, ids} -> ids
            {:ok} -> []
          end)

        if retry_ids != [] and course_id do
          scheduled_at = DateTime.add(DateTime.utc_now(), 60, :second)
          # Ignore enqueue errors: the sweeper is still a backstop, and in
          # Oban inline test mode the retry job runs synchronously here — if
          # that job itself raises we don't want it to bubble up and mask the
          # partial-success result of the original job.
          try do
            enqueue(retry_ids, course_id: course_id, scheduled_at: scheduled_at)
          rescue
            _ -> :ok
          end
        end

        :ok
      end
    end
    end
  end

  @doc """
  Enqueues validation for a list of question ids. Call this immediately after
  inserting new questions.

  Large lists are chunked into multiple Oban jobs of at most
  `@outer_chunk_size` ids each. Each chunk is a separate job so a failure
  in one doesn't affect the others. Ids within a chunk are sorted so the
  `:unique` constraint deduplicates across callers that pass the same set
  in different orders.

  Returns `:ok` on success, `{:error, reason}` on the first insert failure.
  """
  def enqueue(question_ids, opts \\ [])

  def enqueue([], _opts), do: :ok

  def enqueue(question_ids, opts) when is_list(question_ids) do
    job_opts = Keyword.take(opts, [:scheduled_at])

    question_ids
    |> Enum.sort()
    |> Enum.chunk_every(@outer_chunk_size)
    |> Enum.reduce_while(:ok, fn chunk, :ok ->
      args =
        %{"question_ids" => chunk}
        |> put_if(:course_id, opts[:course_id])
        |> put_if(:retry_round, opts[:retry_round])

      case args |> __MODULE__.new(job_opts) |> Oban.insert() do
        {:ok, _job} -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
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

  # Returns `{:ok}` if the sub-batch produced verdicts (even if some verdicts
  # were :needs_review or :failed). Returns `{:error, retry_ids}` if the
  # validator itself errored — `retry_ids` are question ids that can be
  # re-attempted; the caller decides whether to re-enqueue them or raise.
  defp validate_and_apply(questions, retry_round, course_id) do
    case Validation.validate_batch(questions) do
      {:ok, verdicts} ->
        Enum.each(questions, fn q ->
          verdict = Map.get(verdicts, q.id, %{})
          handle_verdict(q, verdict, retry_round, course_id)
        end)

        # Broadcast so `AssessmentLive` (and anyone else gating on scope
        # readiness) can re-run its check without polling. Validation and
        # classification run on independent queues; whichever finishes last
        # is the one that makes a question visible to students — so we
        # broadcast from both sides.
        chapter_ids =
          questions
          |> Enum.map(& &1.chapter_id)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        if course_id && chapter_ids != [] do
          Phoenix.PubSub.broadcast(
            FunSheep.PubSub,
            "course:#{course_id}",
            {:questions_ready, %{chapter_ids: chapter_ids}}
          )
        end

        {:ok}

      {:error, reason} ->
        # Bump every question's attempt counter and mark any that have
        # exceeded @max_validation_attempts as :failed. Without this the
        # sweeper would keep re-enqueueing them forever and the course would
        # never finalize (the 2026-04-22 d44628ca zombie loop: 912 parse
        # failures in 24h on the same questions).
        {give_up_ids, retry_ids} = bump_attempts_and_collect_giveups(questions)

        if give_up_ids != [] do
          mark_failed_unparseable(give_up_ids, reason)

          Logger.error(
            "[Validation] Marked #{length(give_up_ids)} questions :failed after " <>
              "#{@max_validation_attempts} parse_failed attempts (course #{course_id}, reason: #{inspect(reason)})."
          )
        end

        Logger.error(
          "[Validation] Batch failed for course #{course_id}: #{inspect(reason)}. " <>
            "#{length(retry_ids)} questions eligible for retry; " <>
            "#{length(give_up_ids)} marked :failed (cap reached)."
        )

        {:error, retry_ids}
    end
  end

  # Atomically bump validation_attempts and split into "still retryable"
  # and "give up now" buckets. Returns {give_up_ids, retry_ids}.
  # The `select` reads the post-update row (PG RETURNING), so
  # `q.validation_attempts` is already the incremented value.
  defp bump_attempts_and_collect_giveups(questions) do
    ids = Enum.map(questions, & &1.id)

    {_, updated} =
      from(q in Question,
        where: q.id in ^ids,
        select: %{id: q.id, attempts: q.validation_attempts}
      )
      |> Repo.update_all(inc: [validation_attempts: 1])

    {give_up, retry} =
      Enum.split_with(updated, fn %{attempts: a} -> a >= @max_validation_attempts end)

    {Enum.map(give_up, & &1.id), Enum.map(retry, & &1.id)}
  end

  defp cleanup_cancelled_course_questions(nil), do: :ok

  defp cleanup_cancelled_course_questions(course_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    report = %{
      "error" => "course_cancelled",
      "marked_at" => DateTime.to_iso8601(now)
    }

    {count, _} =
      from(q in Question,
        where: q.course_id == ^course_id and q.validation_status == :pending
      )
      |> Repo.update_all(
        set: [
          validation_status: :failed,
          validation_score: 0.0,
          validation_report: report,
          validated_at: now,
          updated_at: now
        ]
      )

    if count > 0 do
      Logger.info(
        "[Validation] Marked #{count} pending questions :failed for cancelled course #{course_id}"
      )
    end
  end

  defp mark_failed_unparseable(ids, reason) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    report = %{
      "error" => "validator_unparseable_response",
      "reason" => inspect(reason),
      "attempts" => @max_validation_attempts,
      "marked_at" => DateTime.to_iso8601(now)
    }

    from(q in Question, where: q.id in ^ids and q.validation_status == :pending)
    |> Repo.update_all(
      set: [
        validation_status: :failed,
        validation_score: 0.0,
        validation_report: report,
        validated_at: now,
        updated_at: now
      ]
    )
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
  #
  # Additionally gated by `:auto_correction_enabled` config (default false
  # as of April 2026 — the per-flagged-question cost is real and the admin
  # review queue now surfaces these, so a human can trigger correction
  # selectively instead of burning 2× tokens on every needs_review row).
  defp maybe_retry_needs_review(
         %Question{validation_status: :needs_review} = q,
         verdict,
         0,
         course_id
       ) do
    cond do
      not auto_correction_enabled?() ->
        Logger.debug("[Validation] Auto-correction disabled; leaving #{q.id} for admin review.")

        :ok

      correction_worthwhile?(verdict) ->
        do_attempt_correction(q, verdict, course_id)

      true ->
        Logger.debug(
          "[Validation] Correction skipped for #{q.id}: not a fixable verdict; leaving for admin review."
        )

        :ok
    end
  end

  defp maybe_retry_needs_review(_q, _v, _r, _c), do: :ok

  defp do_attempt_correction(q, verdict, course_id) do
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
  end

  defp auto_correction_enabled? do
    Application.get_env(:fun_sheep, :validation_auto_correction_enabled, false)
  end

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

    with {:ok, text} <- ai_client().call(@correction_system_prompt, prompt, @correction_llm_opts),
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

  # --- Structural pre-validation (SAT and metadata-driven courses) ---

  # Returns true when a course should have structural pre-validation applied.
  # This includes SAT courses (explicit) and any course with generation_config
  # validation_rules in its metadata (metadata-driven standardized tests).
  defp uses_structural_validation?(%Course{catalog_test_type: "sat"}), do: true

  defp uses_structural_validation?(%Course{metadata: %{"generation_config" => gen_config}})
       when is_map(gen_config),
       do: Map.has_key?(gen_config, "validation_rules")

  defp uses_structural_validation?(_), do: false

  # Filters questions by structural rules BEFORE the LLM validator runs.
  # Questions that fail are marked :failed immediately; questions that pass are returned
  # for the regular LLM-based validation flow.
  #
  # This is cheaper than sending malformed questions to the LLM, and the error
  # messages are more actionable ("exactly 4 options required" vs. "completeness: fail").
  defp pre_filter_sat_questions(questions, course) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.filter(questions, fn q ->
      case validate_sat_question(q, course) do
        :ok ->
          true

        {:error, reason} ->
          report = %{
            "error" => "structural_validation_failed",
            "reason" => reason,
            "marked_at" => DateTime.to_iso8601(now)
          }

          from(sq in Question, where: sq.id == ^q.id and sq.validation_status == :pending)
          |> Repo.update_all(
            set: [
              validation_status: :failed,
              validation_score: 0.0,
              validation_report: report,
              validated_at: now,
              updated_at: now
            ]
          )

          Logger.warning(
            "[Validation] Structural pre-validation failed for question #{q.id} (course #{course.id}): #{reason}"
          )

          false
      end
    end)
  end

  @doc """
  Validates structural rules for a single standardized-test question.

  When `course.metadata["generation_config"]["validation_rules"]` is present,
  its `mcq_option_count` and `answer_labels` override the SAT defaults.
  Returns `:ok` or `{:error, reason}`.

  Rules applied:
  - All questions: question stem must not be empty
  - MCQ: exactly N options present (N from validation_rules, default 4 for A–D)
  - MCQ: answer must be one of the expected labels
  - Reading & Writing passage questions: passage between 10 and 200 words
    (detected by presence of a blank-line separator in the stem)
  - Numeric short-answer: answer must parse to a number
  """
  @spec validate_sat_question(Question.t(), Course.t()) :: :ok | {:error, String.t()}
  def validate_sat_question(question, course) do
    validation_rules = get_in(course.metadata || %{}, ["generation_config", "validation_rules"])
    required_labels = (validation_rules || %{})["answer_labels"] || ["A", "B", "C", "D"]

    with :ok <- check_non_empty_stem(question),
         :ok <- check_mcq_options_for_labels(question, required_labels),
         :ok <- check_mcq_answer_for_labels(question, required_labels),
         :ok <- check_rw_passage_length(question),
         :ok <- check_numeric_answer(question) do
      :ok
    end
  end

  defp check_non_empty_stem(question) do
    stem = question.content || ""

    if String.trim(stem) == "" do
      {:error, "question stem is empty"}
    else
      :ok
    end
  end

  # Label-parameterized MCQ option check — supports both 4-option (A–D) and
  # 5-option (A–E) tests. Called from validate_sat_question/2 with the
  # labels extracted from course.metadata["generation_config"]["validation_rules"].
  defp check_mcq_options_for_labels(
         %Question{question_type: :multiple_choice} = question,
         required_labels
       ) do
    options = question.options || %{}
    required_keys = Enum.sort(required_labels)
    present_keys = Map.keys(options) |> Enum.map(&String.upcase/1) |> Enum.sort()

    if required_keys == present_keys do
      :ok
    else
      {:error,
       "MCQ must have exactly #{length(required_labels)} options (#{Enum.join(required_labels, ", ")}); found: #{inspect(present_keys)}"}
    end
  end

  defp check_mcq_options_for_labels(_question, _labels), do: :ok

  defp check_mcq_answer_for_labels(
         %Question{question_type: :multiple_choice} = question,
         required_labels
       ) do
    answer = question.answer || ""
    upper_labels = Enum.map(required_labels, &String.upcase/1)

    if String.upcase(String.trim(answer)) in upper_labels do
      :ok
    else
      {:error,
       "MCQ answer must be one of #{Enum.join(upper_labels, ", ")}; got: #{inspect(answer)}"}
    end
  end

  defp check_mcq_answer_for_labels(_question, _labels), do: :ok

  # For Reading & Writing questions: if the question stem contains a blank-line
  # separator (passage + question pattern), verify the passage word count is
  # between 10 and 200 words.
  defp check_rw_passage_length(%Question{question_type: :multiple_choice} = question) do
    content = question.content || ""

    case String.split(content, ~r/\n\n+/, parts: 2) do
      [passage, _question_stem] ->
        word_count = passage |> String.split(~r/\s+/) |> length()

        cond do
          word_count < 10 ->
            {:error, "Reading & Writing passage is too short (#{word_count} words; minimum 10)"}

          word_count > 200 ->
            {:error, "Reading & Writing passage is too long (#{word_count} words; maximum 200)"}

          true ->
            :ok
        end

      # No blank-line separator — single-stem question, no passage length to check
      [_single_part] ->
        :ok
    end
  end

  defp check_rw_passage_length(_question), do: :ok

  # For student-produced response (numeric short answer), validate the answer parses.
  defp check_numeric_answer(%Question{question_type: :short_answer} = question) do
    answer = String.trim(question.answer || "")

    if answer == "" do
      {:error, "numeric short-answer question has an empty answer"}
    else
      case Float.parse(answer) do
        {_n, ""} ->
          :ok

        _ ->
          case Integer.parse(answer) do
            {_n, ""} -> :ok
            _ -> {:error, "numeric short-answer answer '#{answer}' does not parse to a number"}
          end
      end
    end
  end

  defp check_numeric_answer(_question), do: :ok

  defp ai_client, do: Application.get_env(:fun_sheep, :ai_client_impl, FunSheep.AI.Client)
end
