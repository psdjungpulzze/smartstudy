defmodule FunSheep.Workers.StuckValidationSweeperWorker do
  @moduledoc """
  Finds questions stuck at `validation_status = :pending` with no live Oban
  job to process them and re-enqueues them through
  `FunSheep.Questions.requeue_pending_validations/1`.

  Why this exists: a batch validation job that raises (e.g. Interactor
  returns an error mid-batch) retries up to `max_attempts`, then is
  `discarded`. The default `Oban.Plugins.Pruner` removes discarded jobs
  after 60s. The questions in that job stay `:pending` forever because
  nothing re-enqueues from the question side — leaving the UI stuck at
  "Validating questions for accuracy — X remaining" indefinitely.
  (Observed in prod on course `d44628ca-...` 2026-04-22 — 2282 zombies.)

  Runs on a 15-minute cron. Any course with a `:pending` question older
  than `@stuck_threshold_minutes` has all its pending questions re-enqueued.
  Idempotent: `QuestionValidationWorker.enqueue/2` has a 2-minute uniqueness
  window, so repeated sweeps collapse under a single job per id-set.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 2,
    unique: [
      period: 600,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  import Ecto.Query
  require Logger

  alias FunSheep.Courses.Course
  alias FunSheep.Questions
  alias FunSheep.Questions.Question
  alias FunSheep.Repo

  # Long enough that a normal in-flight validation job doesn't get
  # double-enqueued (validator `unique` is 2min, its retry backoff is
  # ~minutes), short enough that zombies surface within a useful window.
  @stuck_threshold_minutes 30

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    force = Map.get(args, "force", false)

    # `force: true` sweeps every course with any :pending question regardless
    # of age. Default path applies the age threshold so the cron doesn't
    # fight in-flight validators.
    base_query =
      from(q in Question,
        join: c in Course, on: c.id == q.course_id,
        where: q.validation_status == :pending,
        where: c.processing_status != "cancelled",
        distinct: true,
        select: q.course_id
      )

    query =
      if force do
        base_query
      else
        cutoff =
          DateTime.utc_now()
          |> DateTime.add(-@stuck_threshold_minutes, :minute)

        from(q in base_query, where: q.inserted_at < ^cutoff)
      end

    course_ids = Repo.all(query)

    total =
      Enum.reduce(course_ids, 0, fn course_id, acc ->
        {:ok, n} = Questions.requeue_pending_validations(course_id)

        if n > 0 do
          Logger.info("[Sweeper] Re-enqueued #{n} :pending questions for course #{course_id}")
        end

        acc + n
      end)

    if total > 0 do
      Logger.info(
        "[Sweeper] Swept #{total} stuck :pending questions across #{length(course_ids)} courses"
      )
    end

    :ok
  end
end
