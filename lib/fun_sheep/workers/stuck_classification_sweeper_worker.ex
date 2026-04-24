defmodule FunSheep.Workers.StuckClassificationSweeperWorker do
  @moduledoc """
  Finds questions with `classification_status = :uncategorized` that have no
  live classification job and re-enqueues
  `QuestionClassificationWorker.enqueue_for_chapter/1` for each affected chapter.

  Why this exists: `QuestionClassificationWorker` is only enqueued from
  `AIQuestionGenerationWorker` at question-insert time (line 639). Questions
  that were inserted before the classification pipeline existed, or that
  survived a zombie incident, have no self-healing path and stay
  `:uncategorized` forever — invisible to the adaptive delivery engine.

  Runs every 4 hours. Any chapter with an `:uncategorized` question older than
  `@stuck_threshold_hours` and no live classification job gets enqueued.
  `QuestionClassificationWorker` has a 2-minute uniqueness window, so repeated
  sweeps collapse to one job per chapter.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 2,
    unique: [
      period: 3600,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  import Ecto.Query
  require Logger

  alias FunSheep.Questions.Question
  alias FunSheep.Workers.QuestionClassificationWorker
  alias FunSheep.Repo

  # Only sweep chapters whose uncategorized questions are older than this to
  # avoid racing with a classification job that just inserted new questions.
  @stuck_threshold_hours 2

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@stuck_threshold_hours * 3600, :second)

    chapters_with_live_jobs =
      from(j in "oban_jobs",
        where:
          j.worker == "Elixir.FunSheep.Workers.QuestionClassificationWorker" and
            j.state in ["available", "scheduled", "executing", "retryable"],
        select: fragment("?->>'chapter_id'", j.args)
      )
      |> Repo.all()
      |> MapSet.new()

    stuck_chapter_ids =
      from(q in Question,
        where: q.classification_status == :uncategorized and q.inserted_at < ^cutoff,
        distinct: true,
        select: q.chapter_id
      )
      |> Repo.all()
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&MapSet.member?(chapters_with_live_jobs, to_string(&1)))

    enqueued =
      Enum.count(stuck_chapter_ids, fn chapter_id ->
        case QuestionClassificationWorker.enqueue_for_chapter(chapter_id) do
          {:ok, %{conflict?: true}} ->
            false

          {:ok, _job} ->
            Logger.info("[StuckClassify] Re-enqueued classification for chapter #{chapter_id}")
            true

          _error ->
            false
        end
      end)

    if enqueued > 0 do
      Logger.info("[StuckClassify] Enqueued #{enqueued} classification jobs for stuck chapters")
    end

    :ok
  end
end
