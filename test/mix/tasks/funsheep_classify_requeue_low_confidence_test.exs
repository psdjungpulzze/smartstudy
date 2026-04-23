defmodule Mix.Tasks.Funsheep.Classify.RequeueLowConfidenceTest do
  @moduledoc """
  Companion to PR #73 (lower classifier threshold). Verifies the one-shot
  requeue task that flips :low_confidence + :passed questions back to
  :uncategorized so the worker can re-run them at the new (lower) threshold.

  Must NOT touch :pending or :failed questions — those would leak unverified
  content if marked classifiable.
  """

  use FunSheep.DataCase, async: false

  alias FunSheep.{Courses, Questions, Repo}
  alias FunSheep.Questions.Question

  defp setup_questions do
    {:ok, course} = Courses.create_course(%{name: "Bio", subject: "Biology", grade: "10"})
    {:ok, ch} = Courses.create_chapter(%{name: "Cells", position: 1, course_id: course.id})
    {:ok, sec} = Courses.create_section(%{name: "Mito", position: 1, chapter_id: ch.id})

    # 3 :passed + :low_confidence — should be reset
    targets =
      for i <- 1..3 do
        {:ok, q} =
          Questions.create_question(%{
            content: "Q#{i}",
            answer: "A",
            question_type: :short_answer,
            difficulty: :easy,
            course_id: course.id,
            chapter_id: ch.id,
            section_id: sec.id,
            validation_status: :passed,
            classification_status: :low_confidence,
            classification_confidence: 0.6
          })

        q
      end

    # 1 :passed + :ai_classified — should NOT be touched
    {:ok, untouched_classified} =
      Questions.create_question(%{
        content: "Q-already",
        answer: "A",
        question_type: :short_answer,
        difficulty: :easy,
        course_id: course.id,
        chapter_id: ch.id,
        section_id: sec.id,
        validation_status: :passed,
        classification_status: :ai_classified,
        classification_confidence: 0.9
      })

    # 1 :pending + :low_confidence — should NOT be touched (validation gate)
    {:ok, untouched_pending} =
      Questions.create_question(%{
        content: "Q-pending",
        answer: "A",
        question_type: :short_answer,
        difficulty: :easy,
        course_id: course.id,
        chapter_id: ch.id,
        validation_status: :pending,
        classification_status: :low_confidence
      })

    # 1 :passed + :low_confidence + chapter_id NULL — should NOT be touched
    # (classifier needs chapter_id to find candidate sections)
    {:ok, _q} =
      Questions.create_question(%{
        content: "Q-orphan",
        answer: "A",
        question_type: :short_answer,
        difficulty: :easy,
        course_id: course.id,
        chapter_id: nil,
        validation_status: :passed,
        classification_status: :low_confidence
      })

    %{
      course: course,
      targets: targets,
      untouched_classified: untouched_classified,
      untouched_pending: untouched_pending
    }
  end

  test "resets only :passed + :low_confidence + chapter_id-set questions" do
    %{targets: targets, untouched_classified: kept, untouched_pending: pending} =
      setup_questions()

    Mix.Tasks.Funsheep.Classify.RequeueLowConfidence.run([])

    for q <- targets do
      reloaded = Repo.get!(Question, q.id)
      assert reloaded.classification_status == :uncategorized
      assert is_nil(reloaded.section_id)
      assert is_nil(reloaded.classified_at)
      assert is_nil(reloaded.classification_confidence)
    end

    # :ai_classified untouched
    classified_reloaded = Repo.get!(Question, kept.id)
    assert classified_reloaded.classification_status == :ai_classified

    # :pending untouched
    pending_reloaded = Repo.get!(Question, pending.id)
    assert pending_reloaded.classification_status == :low_confidence
    assert pending_reloaded.validation_status == :pending
  end

  test "--dry-run reports without writing" do
    %{targets: targets} = setup_questions()

    Mix.Tasks.Funsheep.Classify.RequeueLowConfidence.run(["--dry-run"])

    for q <- targets do
      reloaded = Repo.get!(Question, q.id)
      assert reloaded.classification_status == :low_confidence
    end
  end

  test "--course filter scopes to one course" do
    %{course: target_course, targets: target_qs} = setup_questions()
    %{targets: other_targets} = setup_questions()

    Mix.Tasks.Funsheep.Classify.RequeueLowConfidence.run(["--course", target_course.id])

    for q <- target_qs do
      assert Repo.get!(Question, q.id).classification_status == :uncategorized
    end

    for q <- other_targets do
      assert Repo.get!(Question, q.id).classification_status == :low_confidence
    end
  end

  test "is idempotent on repeat runs" do
    %{targets: targets} = setup_questions()

    Mix.Tasks.Funsheep.Classify.RequeueLowConfidence.run([])
    # After first run, all targets are :uncategorized — second run finds 0
    Mix.Tasks.Funsheep.Classify.RequeueLowConfidence.run([])

    for q <- targets do
      assert Repo.get!(Question, q.id).classification_status == :uncategorized
    end
  end
end
