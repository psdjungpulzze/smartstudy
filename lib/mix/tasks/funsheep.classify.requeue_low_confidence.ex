defmodule Mix.Tasks.Funsheep.Classify.RequeueLowConfidence do
  @shortdoc "Reset :low_confidence + :passed questions to :uncategorized + re-enqueue classification"

  @moduledoc """
  After lowering the classifier confidence threshold (`fix/classifier-threshold`,
  PR #73), the existing `:low_confidence` questions need a re-classification pass
  so the new threshold can graduate them to `:ai_classified`. The worker only
  loads `:uncategorized` questions, so we reset them first.

  Scope: `validation_status = :passed` only — never touches `:pending` or
  `:failed` (those would leak unverified content to students). Also requires
  `chapter_id IS NOT NULL` since the classifier uses the chapter to find
  candidate sections.

  Idempotent: re-running on questions already promoted to `:ai_classified`
  by an earlier pass is a no-op (they no longer match the WHERE clause).

  ## Usage

      mix funsheep.classify.requeue_low_confidence              # all courses
      mix funsheep.classify.requeue_low_confidence --course ID  # one course
      mix funsheep.classify.requeue_low_confidence --dry-run    # report only
  """

  use Mix.Task

  import Ecto.Query

  alias FunSheep.Questions.Question
  alias FunSheep.Repo
  alias FunSheep.Workers.QuestionClassificationWorker

  @switches [course: :string, dry_run: :boolean]
  @batch_size 50

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    dry_run? = Keyword.get(opts, :dry_run, false)
    if dry_run?, do: Mix.shell().info("DRY RUN — no writes will be made.")

    base =
      from(q in Question,
        where:
          q.validation_status == :passed and q.classification_status == :low_confidence and
            not is_nil(q.chapter_id),
        select: q.id
      )

    query =
      case opts[:course] do
        nil -> base
        cid -> from(q in base, where: q.course_id == ^cid)
      end

    ids = Repo.all(query)
    Mix.shell().info("Found #{length(ids)} :low_confidence questions to requeue.")

    if ids == [] or dry_run? do
      :ok
    else
      {n, _} =
        from(q in Question, where: q.id in ^ids)
        |> Repo.update_all(
          set: [
            classification_status: :uncategorized,
            section_id: nil,
            classified_at: nil,
            classification_confidence: nil
          ]
        )

      Mix.shell().info("Reset to :uncategorized: #{n}")

      enqueued =
        ids
        |> Enum.chunk_every(@batch_size)
        |> Enum.reduce(0, fn batch, acc ->
          case QuestionClassificationWorker.enqueue_for_questions(batch) do
            {:ok, _} ->
              acc + length(batch)

            err ->
              Mix.shell().info("  enqueue err on batch: #{inspect(err)}")
              acc
          end
        end)

      Mix.shell().info("Enqueued: #{enqueued} (in chunks of #{@batch_size})")
    end
  end
end
