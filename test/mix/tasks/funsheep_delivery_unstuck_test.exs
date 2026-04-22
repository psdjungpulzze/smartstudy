defmodule Mix.Tasks.Funsheep.Delivery.UnstuckTest do
  @moduledoc """
  The 2026-04-22 incident left courses with hundreds of `:passed` questions
  invisible to delivery because the chapter had no sections (so the
  classifier stamped them `:low_confidence`). This task is the one-shot
  recovery — it must:

    * Create an Overview section per affected chapter (idempotent).
    * Promote `:passed` + `section_id IS NULL` questions to
      `:ai_classified` with the new section_id.
    * NOT touch :pending / :failed questions (those would leak unverified
      content to students).
    * Be safe to re-run.
  """

  use FunSheep.DataCase, async: false

  alias FunSheep.{Courses, Questions, Repo}
  alias FunSheep.Questions.Question

  defp chapter_with_passed_questions(opts \\ []) do
    {:ok, course} = Courses.create_course(%{name: "AP Bio", subject: "Biology", grade: "11"})

    {:ok, chapter} =
      Courses.create_chapter(%{name: "Cells", position: 1, course_id: course.id})

    for i <- 1..Keyword.get(opts, :passed_count, 3) do
      {:ok, _q} =
        Questions.create_question(%{
          content: "Q#{i}",
          answer: "A",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          chapter_id: chapter.id,
          validation_status: :passed,
          classification_status: :low_confidence
        })
    end

    # Add some non-:passed questions that MUST NOT be touched.
    for status <- [:pending, :failed] do
      {:ok, _q} =
        Questions.create_question(%{
          content: "Q-#{status}",
          answer: "A",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          chapter_id: chapter.id,
          validation_status: status,
          classification_status: :low_confidence
        })
    end

    %{course: course, chapter: chapter}
  end

  test "creates an Overview section and promotes :passed questions in chapters with no sections" do
    %{chapter: chapter} = chapter_with_passed_questions(passed_count: 5)

    Mix.Tasks.Funsheep.Delivery.Unstuck.run([])

    [section] = Courses.list_sections_by_chapter(chapter.id)
    assert section.name == "Overview"
    assert section.position == 1

    promoted =
      Question
      |> Repo.all()
      |> Enum.filter(&(&1.chapter_id == chapter.id))

    {passed, others} = Enum.split_with(promoted, &(&1.validation_status == :passed))
    assert length(passed) == 5

    for q <- passed do
      assert q.section_id == section.id
      assert q.classification_status == :ai_classified
      assert q.classification_confidence == 1.0
      refute is_nil(q.classified_at)
    end

    # :pending / :failed must be untouched
    for q <- others do
      assert is_nil(q.section_id)
      assert q.classification_status == :low_confidence
    end
  end

  test "is idempotent on repeat runs" do
    %{chapter: chapter} = chapter_with_passed_questions(passed_count: 2)

    Mix.Tasks.Funsheep.Delivery.Unstuck.run([])
    Mix.Tasks.Funsheep.Delivery.Unstuck.run([])

    sections = Courses.list_sections_by_chapter(chapter.id)
    assert length(sections) == 1
  end

  test "leaves chapters that already have sections alone" do
    {:ok, course} = Courses.create_course(%{name: "Math", subject: "Math", grade: "10"})

    {:ok, chapter} =
      Courses.create_chapter(%{name: "Algebra", position: 1, course_id: course.id})

    {:ok, _existing} =
      Courses.create_section(%{
        name: "Linear Equations",
        position: 1,
        chapter_id: chapter.id
      })

    {:ok, _q} =
      Questions.create_question(%{
        content: "Solve x + 2 = 5",
        answer: "3",
        question_type: :short_answer,
        difficulty: :easy,
        course_id: course.id,
        chapter_id: chapter.id,
        validation_status: :passed,
        classification_status: :uncategorized
      })

    Mix.Tasks.Funsheep.Delivery.Unstuck.run([])

    sections = Courses.list_sections_by_chapter(chapter.id)
    assert length(sections) == 1
    assert hd(sections).name == "Linear Equations"

    # The question lacked section_id but the chapter already had a section,
    # so the task should NOT touch the question (it's only meant to backfill
    # chapters whose section_id was structurally missing). Re-classification
    # of stale questions in already-sectioned chapters is a separate concern.
    [q] =
      Question
      |> Repo.all()
      |> Enum.filter(&(&1.chapter_id == chapter.id))

    assert is_nil(q.section_id)
    assert q.classification_status == :uncategorized
  end

  test "--course filter scopes to one course" do
    %{course: target} = chapter_with_passed_questions()
    %{chapter: other_chapter} = chapter_with_passed_questions()

    Mix.Tasks.Funsheep.Delivery.Unstuck.run(["--course", target.id])

    # Other course's chapter still has no section.
    assert Courses.list_sections_by_chapter(other_chapter.id) == []
  end

  test "--dry-run reports counts without writing" do
    %{chapter: chapter} = chapter_with_passed_questions(passed_count: 4)

    Mix.Tasks.Funsheep.Delivery.Unstuck.run(["--dry-run"])

    assert Courses.list_sections_by_chapter(chapter.id) == []

    untouched =
      Question
      |> Repo.all()
      |> Enum.filter(&(&1.chapter_id == chapter.id and &1.validation_status == :passed))

    for q <- untouched do
      assert is_nil(q.section_id)
      assert q.classification_status == :low_confidence
    end
  end
end
