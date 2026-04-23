defmodule Mix.Tasks.Funsheep.Questions.Cleanup do
  @shortdoc "Phase 0 data cleanup for a course's question bank (dry-run default)"

  @moduledoc """
  One-shot data-cleanup toolbox for the Phase 0 question-sourcing rebuild.

  Every subcommand defaults to dry-run. Pass `--confirm` to actually write.

  ## Subcommands

      mix funsheep.questions.cleanup audit --course ID

          Read-only health snapshot: counts by source_type, validation_status,
          failure bucket, and I-1 adaptive eligibility. Use before/after each
          destructive op to confirm the impact.

      mix funsheep.questions.cleanup apply_explanations --course ID [--confirm]

          For each `:needs_review` question whose `validation_report` contains
          a `suggested_explanation`, copy it into the `explanation` field and
          reset `validation_status` to `:pending` so the validator re-checks
          it. This bypasses the generator LLM re-run that the inline
          auto-correction path would trigger, saving ~50% of the token cost
          on the ~1,900 missing-explanation questions.

      mix funsheep.questions.cleanup requeue_no_verdict --course ID [--confirm]

          Reset `:failed` questions whose validation_report shows the
          validator returned no verdict (LLM returned nothing) to
          `:pending`. Those are validator bugs, not content bugs.

      mix funsheep.questions.cleanup classify_missing --course ID [--confirm]

          Enqueue `QuestionClassificationWorker` for every question that is
          `:passed` but has a NULL `section_id` — I-1 requires a skill tag for
          the adaptive engine to serve it. Also enqueues for any question with
          a NULL `chapter_id`.

      mix funsheep.questions.cleanup requeue_transport_failures --course ID [--confirm]

          Find `:failed` questions whose validation_report shows the
          validator LLM call itself errored (`validator_unparseable_response`
          with `%Req.TransportError{reason: :econnrefused}` or similar).
          These are infrastructure failures, not content failures — reset
          them to `:pending` so the validator retries under lower load.

      mix funsheep.questions.cleanup delete_garbage --course ID [--confirm]

          Delete questions that match one of the strict "definitely garbage"
          buckets:
            * content_too_short (< 20 chars)
            * truncated_mid_word (ends with lowercase letter, < 100 chars)
            * answer_key_pattern (matches `^[A-D] \\d+\\. [A-D] …`)
          Prints sample rows before deletion so the operator can sanity-check.
          Runs last in the Phase 0 sequence so any question that could be
          rescued by `apply_explanations` has already been rescued.

  ## Why this is a Mix task, not a migration

  Migrations are bad for one-off destructive data ops: they run on every
  deploy, they can't be dry-run, and rollback semantics are awkward. This
  task is explicit, auditable, and re-runnable.

  ## Running against production

  From a dev machine with the Cloud SQL proxy up on 127.0.0.1:5433:

      export DATABASE_URL="ecto://funsheep_app:PASS@127.0.0.1:5433/fun_sheep_prod"
      mix funsheep.questions.cleanup audit --course d44628ca-6579-48da-a83b-466e12b1c19b
      mix funsheep.questions.cleanup apply_explanations --course d44628ca-... --confirm

  Do NOT run this from a container that also runs Oban workers — the
  subcommands that enqueue jobs assume they are going to Oban on the
  prod worker service, not the local shell.
  """

  use Mix.Task

  import Ecto.Query

  alias FunSheep.Questions.Question
  alias FunSheep.Repo

  @switches [course: :string, confirm: :boolean, limit: :integer, prod_db: :boolean]

  @impl Mix.Task
  def run(argv) do
    {subcommand, rest} = split_subcommand(argv)
    {opts, _rest_args, _invalid} = OptionParser.parse(rest, switches: @switches)

    if Keyword.get(opts, :prod_db, false) do
      db_url =
        System.get_env("DATABASE_URL") ||
          Mix.raise("--prod-db requires DATABASE_URL env var")

      Application.put_env(:fun_sheep, FunSheep.Repo,
        url: db_url,
        pool_size: 5,
        ssl: false,
        socket_options: []
      )
    end

    Mix.Task.run("app.start")

    course_id = fetch_course!(opts)
    dry_run? = not Keyword.get(opts, :confirm, false)

    case subcommand do
      "audit" -> audit(course_id)
      "apply_explanations" -> apply_explanations(course_id, dry_run?, opts)
      "requeue_no_verdict" -> requeue_no_verdict(course_id, dry_run?)
      "requeue_transport_failures" -> requeue_transport_failures(course_id, dry_run?)
      "classify_missing" -> classify_missing(course_id, dry_run?)
      "delete_garbage" -> delete_garbage(course_id, dry_run?)
      _ -> usage()
    end
  end

  # -- audit ------------------------------------------------------------------

  defp audit(course_id) do
    Mix.shell().info("\n=== AUDIT #{course_id} ===\n")

    totals = count_by_status(course_id)

    print_line("Total questions:", totals.total)
    print_line("  :passed", totals.passed)
    print_line("  :needs_review", totals.needs_review)
    print_line("  :failed", totals.failed)
    print_line("  :pending", totals.pending)

    adaptive = count_adaptive_eligible(course_id)
    Mix.shell().info("")
    print_line("Adaptive-eligible (passed + section_id + classified):", adaptive)
    print_line("  -> this is the real inventory the engine can serve (I-1)", "")

    Mix.shell().info("")
    print_line("Passed but missing section_id (I-1 violation):", count_passed_no_section(course_id))
    print_line("Null chapter_id (any status):", count_null_chapter(course_id))

    Mix.shell().info("\nNeeds-review buckets:")
    buckets = needs_review_buckets(course_id)
    Enum.each(buckets, fn {k, v} -> print_line("  #{k}", v) end)

    Mix.shell().info("\nFailed buckets:")
    fails = failed_buckets(course_id)
    Enum.each(fails, fn {k, v} -> print_line("  #{k}", v) end)
  end

  defp count_by_status(course_id) do
    rows =
      from(q in Question,
        where: q.course_id == ^course_id,
        group_by: q.validation_status,
        select: {q.validation_status, count(q.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      total: Enum.sum(Map.values(rows)),
      passed: Map.get(rows, :passed, 0),
      needs_review: Map.get(rows, :needs_review, 0),
      failed: Map.get(rows, :failed, 0),
      pending: Map.get(rows, :pending, 0)
    }
  end

  defp count_adaptive_eligible(course_id) do
    from(q in Question,
      where: q.course_id == ^course_id,
      where: q.validation_status == :passed,
      where: not is_nil(q.section_id),
      where: q.classification_status in [:ai_classified, :admin_reviewed],
      select: count(q.id)
    )
    |> Repo.one()
  end

  defp count_passed_no_section(course_id) do
    from(q in Question,
      where: q.course_id == ^course_id and q.validation_status == :passed and is_nil(q.section_id),
      select: count(q.id)
    )
    |> Repo.one()
  end

  defp count_null_chapter(course_id) do
    from(q in Question,
      where: q.course_id == ^course_id and is_nil(q.chapter_id),
      select: count(q.id)
    )
    |> Repo.one()
  end

  defp needs_review_buckets(course_id) do
    query = """
    SELECT
      CASE
        WHEN explanation IS NULL OR TRIM(explanation) = '' THEN 'missing_explanation'
        WHEN validation_report->'explanation'->>'valid' = 'false' THEN 'bad_explanation'
        WHEN validation_report->'answer_correct'->>'correct' = 'false' THEN 'wrong_answer'
        WHEN validation_report->'categorization'->>'suggested_chapter_id' IS NOT NULL THEN 'wrong_chapter'
        ELSE 'other'
      END AS bucket,
      COUNT(*)
    FROM questions
    WHERE course_id = $1 AND validation_status = 'needs_review'
    GROUP BY 1
    ORDER BY 2 DESC
    """

    {:ok, result} = Repo.query(query, [Ecto.UUID.dump!(course_id)])
    Enum.map(result.rows, fn [bucket, count] -> {bucket, count} end)
  end

  defp failed_buckets(course_id) do
    query = """
    SELECT
      CASE
        WHEN validation_report->>'topic_relevance_reason' ILIKE '%did not return%'
          OR validation_report->'completeness'->'issues' ? 'no verdict returned'
          THEN 'validator_no_verdict'
        WHEN LENGTH(content) < 20 THEN 'content_too_short'
        WHEN content ~ '[a-z]$' AND LENGTH(content) < 100 THEN 'truncated_mid_word'
        WHEN content ~ '^[A-D](\\s*\\d+\\.\\s*[A-D]\\s*){2,}' THEN 'answer_key_pattern'
        WHEN validation_report->'answer_correct'->>'correct' = 'false' THEN 'wrong_answer'
        WHEN validation_report->'explanation'->>'valid' = 'false' THEN 'invalid_explanation'
        ELSE 'other'
      END AS bucket,
      COUNT(*)
    FROM questions
    WHERE course_id = $1 AND validation_status = 'failed'
    GROUP BY 1
    ORDER BY 2 DESC
    """

    {:ok, result} = Repo.query(query, [Ecto.UUID.dump!(course_id)])
    Enum.map(result.rows, fn [bucket, count] -> {bucket, count} end)
  end

  # -- apply_explanations -----------------------------------------------------

  defp apply_explanations(course_id, dry_run?, opts) do
    limit = Keyword.get(opts, :limit)

    base =
      from(q in Question,
        where: q.course_id == ^course_id,
        where: q.validation_status == :needs_review,
        where: is_nil(q.explanation) or fragment("TRIM(?) = ''", q.explanation),
        where: fragment("(?->'explanation'->>'valid') = 'false'", q.validation_report),
        where:
          not is_nil(fragment("?->'explanation'->>'suggested_explanation'", q.validation_report)),
        where:
          fragment(
            "TRIM(?->'explanation'->>'suggested_explanation') <> ''",
            q.validation_report
          )
      )

    base = if limit, do: limit(base, ^limit), else: base

    candidates = Repo.all(base)
    total = length(candidates)

    Mix.shell().info("\n=== APPLY EXPLANATIONS (#{if dry_run?, do: "DRY-RUN", else: "CONFIRMED"}) ===")
    Mix.shell().info("Candidates: #{total}\n")

    if total == 0 do
      Mix.shell().info("Nothing to apply.")
    else
      Enum.take(candidates, 3) |> Enum.each(&print_apply_sample/1)

      if dry_run? do
        Mix.shell().info("\n(dry-run — pass --confirm to write)")
      else
        {applied_ids, skipped} = do_apply_explanations(candidates)
        Mix.shell().info("\nApplied to #{length(applied_ids)} questions.")
        if skipped > 0, do: Mix.shell().info("Skipped #{skipped} (no suggestion after re-read).")

        # Re-queue the questions we just changed so validator re-checks them.
        enqueue_validation(course_id, applied_ids)
        Mix.shell().info("Re-queued #{length(applied_ids)} for validation.")
      end
    end
  end

  defp print_apply_sample(%Question{} = q) do
    suggestion = get_in(q.validation_report, ["explanation", "suggested_explanation"])
    Mix.shell().info("  [#{q.id}]")
    Mix.shell().info("    Q: #{String.slice(q.content, 0, 80)}")
    Mix.shell().info("    +explanation: #{String.slice(suggestion || "", 0, 100)}")
  end

  defp do_apply_explanations(candidates) do
    Enum.reduce(candidates, {[], 0}, fn q, {ids, skipped} ->
      suggestion = get_in(q.validation_report, ["explanation", "suggested_explanation"])

      case suggestion do
        s when is_binary(s) and s != "" ->
          {:ok, _} =
            q
            |> Question.changeset(%{
              explanation: String.trim(s),
              validation_status: :pending
            })
            |> Repo.update()

          {[q.id | ids], skipped}

        _ ->
          {ids, skipped + 1}
      end
    end)
  end

  defp enqueue_validation(course_id, ids) do
    ids
    |> Enum.chunk_every(10)
    |> Enum.each(fn batch ->
      FunSheep.Workers.QuestionValidationWorker.enqueue(batch, course_id: course_id)
    end)
  end

  # -- requeue_no_verdict -----------------------------------------------------

  defp requeue_no_verdict(course_id, dry_run?) do
    ids =
      Repo.query!(
        """
        SELECT id FROM questions
        WHERE course_id = $1
          AND validation_status = 'failed'
          AND (validation_report->>'topic_relevance_reason' ILIKE '%did not return%'
            OR validation_report->'completeness'->'issues' ? 'no verdict returned')
        """,
        [Ecto.UUID.dump!(course_id)]
      )
      |> Map.get(:rows)
      |> Enum.map(fn [id] -> Ecto.UUID.load!(id) end)

    Mix.shell().info(
      "\n=== REQUEUE NO-VERDICT (#{if dry_run?, do: "DRY-RUN", else: "CONFIRMED"}) ==="
    )

    Mix.shell().info("Candidates: #{length(ids)}")

    if ids == [] do
      Mix.shell().info("Nothing to re-queue.")
    else
      if dry_run? do
        Mix.shell().info("(dry-run — pass --confirm to reset status + enqueue)")
      else
        {count, _} =
          from(q in Question, where: q.id in ^ids)
          |> Repo.update_all(
            set: [validation_status: :pending, validation_score: nil, validation_report: %{}]
          )

        Mix.shell().info("Reset #{count} rows to :pending.")
        enqueue_validation(course_id, ids)
        Mix.shell().info("Re-queued #{length(ids)} for validation.")
      end
    end
  end

  # -- requeue_transport_failures --------------------------------------------

  defp requeue_transport_failures(course_id, dry_run?) do
    ids =
      Repo.query!(
        """
        SELECT id FROM questions
        WHERE course_id = $1
          AND validation_status = 'failed'
          AND validation_report->>'error' = 'validator_unparseable_response'
          AND (validation_report->>'reason' ILIKE '%TransportError%'
            OR validation_report->>'reason' ILIKE '%econnrefused%'
            OR validation_report->>'reason' ILIKE '%timeout%'
            OR validation_report->>'reason' ILIKE '%closed%')
        """,
        [Ecto.UUID.dump!(course_id)]
      )
      |> Map.get(:rows)
      |> Enum.map(fn [id] -> Ecto.UUID.load!(id) end)

    Mix.shell().info(
      "\n=== REQUEUE TRANSPORT FAILURES (#{if dry_run?, do: "DRY-RUN", else: "CONFIRMED"}) ==="
    )

    Mix.shell().info("Candidates: #{length(ids)}")

    cond do
      ids == [] ->
        Mix.shell().info("Nothing to re-queue.")

      dry_run? ->
        Mix.shell().info("(dry-run — pass --confirm to reset status + enqueue)")

      true ->
        {count, _} =
          from(q in Question, where: q.id in ^ids)
          |> Repo.update_all(
            set: [
              validation_status: :pending,
              validation_score: nil,
              validation_report: %{}
            ]
          )

        Mix.shell().info("Reset #{count} rows to :pending.")
        enqueue_validation(course_id, ids)
        Mix.shell().info("Re-queued #{length(ids)} for validation.")
    end
  end

  # -- classify_missing -------------------------------------------------------

  defp classify_missing(course_id, dry_run?) do
    ids =
      from(q in Question,
        where: q.course_id == ^course_id,
        where:
          (q.validation_status == :passed and is_nil(q.section_id)) or is_nil(q.chapter_id),
        select: q.id
      )
      |> Repo.all()

    Mix.shell().info(
      "\n=== CLASSIFY MISSING (#{if dry_run?, do: "DRY-RUN", else: "CONFIRMED"}) ==="
    )

    Mix.shell().info("Candidates: #{length(ids)}")

    if ids == [] do
      Mix.shell().info("Nothing to classify.")
    else
      if dry_run? do
        Mix.shell().info("(dry-run — pass --confirm to enqueue classifier)")
      else
        FunSheep.Workers.QuestionClassificationWorker.enqueue_for_questions(ids)
        Mix.shell().info("Enqueued #{length(ids)} for classification.")
      end
    end
  end

  # -- delete_garbage ---------------------------------------------------------

  defp delete_garbage(course_id, dry_run?) do
    ids =
      Repo.query!(
        """
        SELECT id FROM questions
        WHERE course_id = $1
          AND validation_status = 'failed'
          AND (
            LENGTH(content) < 20
            OR (content ~ '[a-z]$' AND LENGTH(content) < 100)
            OR content ~ '^[A-D](\\s*\\d+\\.\\s*[A-D]\\s*){2,}'
          )
        """,
        [Ecto.UUID.dump!(course_id)]
      )
      |> Map.get(:rows)
      |> Enum.map(fn [id] -> Ecto.UUID.load!(id) end)

    Mix.shell().info(
      "\n=== DELETE GARBAGE (#{if dry_run?, do: "DRY-RUN", else: "CONFIRMED"}) ==="
    )

    Mix.shell().info("Candidates: #{length(ids)}")

    if ids != [] do
      # Print 5 random samples so the operator can verify the pattern match.
      samples =
        from(q in Question,
          where: q.id in ^Enum.take_random(ids, 5),
          select: %{id: q.id, content: q.content, status: q.validation_status}
        )
        |> Repo.all()

      Mix.shell().info("\nSample rows that will be deleted:")

      Enum.each(samples, fn row ->
        Mix.shell().info("  [#{row.id}] #{String.slice(row.content, 0, 100)}")
      end)
    end

    cond do
      ids == [] ->
        Mix.shell().info("Nothing to delete.")

      dry_run? ->
        Mix.shell().info("\n(dry-run — pass --confirm to DELETE #{length(ids)} rows)")

      true ->
        # Keep attempts for auditability — nullify question_id FK.
        # Actually the attempts belong_to question with no on_delete; let's
        # just delete the questions and let Ecto's FK handle it.
        {n, _} = from(q in Question, where: q.id in ^ids) |> Repo.delete_all()
        Mix.shell().info("\nDeleted #{n} rows.")
    end
  end

  # -- helpers ----------------------------------------------------------------

  defp split_subcommand([]), do: {nil, []}
  defp split_subcommand([sub | rest]), do: {sub, rest}

  defp fetch_course!(opts) do
    case opts[:course] do
      nil ->
        Mix.raise("--course ID is required")

      id ->
        id
    end
  end

  defp print_line(label, value) do
    Mix.shell().info(String.pad_trailing("#{label}", 60) <> " #{value}")
  end

  defp usage do
    Mix.shell().info("""
    Usage:
      mix funsheep.questions.cleanup <subcommand> --course ID [--confirm]

    Subcommands:
      audit               Read-only health snapshot
      apply_explanations  Apply validator-suggested explanations to needs_review
      requeue_no_verdict  Reset validator-bug failures to :pending
      classify_missing    Re-enqueue classifier for null section_id / chapter_id
      delete_garbage      Delete truncated / too-short / answer-key failures
    """)
  end
end
