defmodule Mix.Tasks.Funsheep.Delivery.Unstuck do
  @shortdoc "Backfill missing sections + promote :low_confidence questions so students can practice"

  @moduledoc """
  One-shot data fix for the delivery-blocked state observed 2026-04-22:
  courses had hundreds of `validation_status = :passed` questions that
  never reached students because the chapter had no sections, so the
  classifier stamped every question with `classification_status =
  :low_confidence` (`reason: "no_sections_in_chapter"`). Adaptive
  delivery filters require both `section_id IS NOT NULL` and
  `classification_status in (:ai_classified, :admin_reviewed)`, so the
  questions stayed invisible to practice / quick-test / readiness.

  This task:

    1. Finds every chapter with at least one question but zero sections.
    2. Creates an "Overview" section for each (idempotent — uses
       `Courses.ensure_default_section/1`).
    3. For every question in those chapters where
       `validation_status = :passed` and `section_id IS NULL`,
       sets `section_id = overview.id`,
       `classification_status = :ai_classified`,
       `classification_confidence = 1.0`,
       `classified_at = now`. The question was already chapter-classified;
       with only one section in the chapter, the LLM had nothing to add.

  Going forward the classifier auto-provisions the default section when a
  chapter has none (see `QuestionClassificationWorker.classify_one/2`),
  so this backfill only needs to run once per affected environment.

  ## Usage

      mix funsheep.delivery.unstuck                # all courses
      mix funsheep.delivery.unstuck --course ID    # one course
      mix funsheep.delivery.unstuck --dry-run      # report only, no writes

  Prints per-course counts so the operator can verify the blast radius
  before and after.
  """

  use Mix.Task

  import Ecto.Query

  alias FunSheep.Courses
  alias FunSheep.Courses.{Chapter, Section}
  alias FunSheep.Questions.Question
  alias FunSheep.Repo

  @switches [course: :string, dry_run: :boolean]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    dry_run? = Keyword.get(opts, :dry_run, false)
    if dry_run?, do: Mix.shell().info("DRY RUN — no writes will be made.")

    chapter_ids = sectionless_chapters_with_questions(opts[:course])

    if chapter_ids == [] do
      Mix.shell().info("No chapters need backfill — every chapter with questions has sections.")
    else
      Mix.shell().info("Chapters needing default section: #{length(chapter_ids)}")

      {sections_created, questions_promoted} =
        Enum.reduce(chapter_ids, {0, 0}, fn chapter_id, {s_acc, q_acc} ->
          {created?, section_id} = ensure_section(chapter_id, dry_run?)
          promoted = promote_questions(chapter_id, section_id, dry_run?)

          Mix.shell().info(
            "  chapter=#{chapter_id} section=#{if created?, do: "created", else: "existing"} " <>
              "promoted=#{promoted}"
          )

          {s_acc + if(created?, do: 1, else: 0), q_acc + promoted}
        end)

      Mix.shell().info(
        "Done. sections_created=#{sections_created} questions_promoted=#{questions_promoted}"
      )
    end
  end

  # Chapters that have at least one question but zero sections, optionally
  # filtered to a single course.
  defp sectionless_chapters_with_questions(course_filter) do
    from(c in Chapter,
      left_join: s in Section,
      on: s.chapter_id == c.id,
      join: q in Question,
      on: q.chapter_id == c.id,
      where: is_nil(s.id),
      group_by: c.id,
      select: c.id
    )
    |> filter_by_course(course_filter)
    |> Repo.all()
  end

  defp filter_by_course(query, nil), do: query

  defp filter_by_course(query, course_id) do
    from([c, _, _] in query, where: c.course_id == ^course_id)
  end

  defp ensure_section(_chapter_id, true), do: {false, "DRY-RUN-SECTION-ID"}

  defp ensure_section(chapter_id, false) do
    pre_existed? = Courses.list_sections_by_chapter(chapter_id) != []
    {:ok, section} = Courses.ensure_default_section(chapter_id)
    {!pre_existed?, section.id}
  end

  # Promote questions in this chapter that already passed validation but are
  # invisible to delivery because they lack section_id / proper classification.
  # Bumping :pending or :failed questions would leak unverified content to
  # students, so we only touch :passed.
  defp promote_questions(chapter_id, _section_id, true) do
    from(q in Question,
      where:
        q.chapter_id == ^chapter_id and q.validation_status == :passed and
          is_nil(q.section_id)
    )
    |> Repo.aggregate(:count)
  end

  defp promote_questions(chapter_id, section_id, false) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      from(q in Question,
        where:
          q.chapter_id == ^chapter_id and q.validation_status == :passed and
            is_nil(q.section_id)
      )
      |> Repo.update_all(
        set: [
          section_id: section_id,
          classification_status: :ai_classified,
          classification_confidence: 1.0,
          classified_at: now,
          updated_at: now
        ]
      )

    count
  end
end
