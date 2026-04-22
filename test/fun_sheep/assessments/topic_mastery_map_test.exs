defmodule FunSheep.Assessments.TopicMasteryMapTest do
  @moduledoc """
  Covers `FunSheep.Assessments.topic_mastery_map/2`, `recent_attempts_for_topic/3`,
  and `topic_accuracy_trend/3` (spec §5.3).
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.{Assessments, Courses, Questions, Repo}
  alias FunSheep.ContentFixtures

  setup do
    student = ContentFixtures.create_user_role(%{role: :student})
    course = ContentFixtures.create_course(%{created_by_id: student.id})

    {:ok, chapter_a} =
      Courses.create_chapter(%{name: "Fractions", position: 1, course_id: course.id})

    {:ok, chapter_b} =
      Courses.create_chapter(%{name: "Geometry", position: 2, course_id: course.id})

    {:ok, section_a1} =
      Courses.create_section(%{name: "Adding", position: 1, chapter_id: chapter_a.id})

    {:ok, section_a2} =
      Courses.create_section(%{name: "Multiplying", position: 2, chapter_id: chapter_a.id})

    {:ok, section_b1} =
      Courses.create_section(%{name: "Triangles", position: 1, chapter_id: chapter_b.id})

    {:ok, schedule} =
      Assessments.create_test_schedule(%{
        name: "Unit Exam",
        test_date: Date.add(Date.utc_today(), 10),
        scope: %{"chapter_ids" => [chapter_a.id, chapter_b.id]},
        user_role_id: student.id,
        course_id: course.id
      })

    %{
      student: student,
      course: course,
      chapter_a: chapter_a,
      chapter_b: chapter_b,
      section_a1: section_a1,
      section_a2: section_a2,
      section_b1: section_b1,
      schedule: schedule
    }
  end

  defp question!(attrs) do
    {:ok, q} =
      Questions.create_question(
        Map.merge(
          %{
            content: "Q",
            answer: "A",
            question_type: :short_answer,
            difficulty: :easy
          },
          attrs
        )
      )

    q
  end

  defp attempt!(user, question, is_correct) do
    {:ok, _} =
      %Questions.QuestionAttempt{}
      |> Questions.QuestionAttempt.changeset(%{
        user_role_id: user.id,
        question_id: question.id,
        is_correct: is_correct,
        time_taken_seconds: 15,
        answer_given: "x"
      })
      |> Repo.insert()
  end

  test "builds chapter → topic grid with real accuracy", ctx do
    q1 =
      question!(%{
        course_id: ctx.course.id,
        chapter_id: ctx.chapter_a.id,
        section_id: ctx.section_a1.id
      })

    q2 =
      question!(%{
        course_id: ctx.course.id,
        chapter_id: ctx.chapter_a.id,
        section_id: ctx.section_a2.id
      })

    # section_a1: 2/3 correct
    attempt!(ctx.student, q1, true)
    attempt!(ctx.student, q1, true)
    attempt!(ctx.student, q1, false)

    # section_a2: 0/2 correct
    attempt!(ctx.student, q2, false)
    attempt!(ctx.student, q2, false)

    grid = Assessments.topic_mastery_map(ctx.student.id, ctx.schedule.id)
    assert length(grid) == 2

    [ch_a, ch_b] = grid
    assert ch_a.chapter_name == "Fractions"
    assert ch_b.chapter_name == "Geometry"

    a1 = Enum.find(ch_a.topics, &(&1.section_id == ctx.section_a1.id))
    a2 = Enum.find(ch_a.topics, &(&1.section_id == ctx.section_a2.id))

    assert a1.accuracy == 66.7
    assert a1.attempts_count == 3
    assert a2.accuracy == 0.0
    assert a2.attempts_count == 2

    [b1] = ch_b.topics
    assert b1.section_id == ctx.section_b1.id
    assert b1.attempts_count == 0
    assert b1.status == :insufficient_data
  end

  test "returns [] for a test schedule with no chapter scope", ctx do
    {:ok, schedule} =
      Assessments.create_test_schedule(%{
        name: "Empty",
        test_date: Date.add(Date.utc_today(), 7),
        scope: %{},
        user_role_id: ctx.student.id,
        course_id: ctx.course.id
      })

    assert Assessments.topic_mastery_map(ctx.student.id, schedule.id) == []
  end

  test "returns [] for non-existent schedule", ctx do
    assert Assessments.topic_mastery_map(ctx.student.id, Ecto.UUID.generate()) == []
  end

  test "recent_attempts_for_topic/3 returns newest-first with question preloaded", ctx do
    q =
      question!(%{
        course_id: ctx.course.id,
        chapter_id: ctx.chapter_a.id,
        section_id: ctx.section_a1.id
      })

    for _ <- 1..3, do: attempt!(ctx.student, q, true)

    [first | _] = Assessments.recent_attempts_for_topic(ctx.student.id, ctx.section_a1.id, 10)
    assert %Questions.Question{} = first.question
    assert first.question.id == q.id
  end

  test "topic_accuracy_trend/3 buckets by day and skips empty days", ctx do
    q =
      question!(%{
        course_id: ctx.course.id,
        chapter_id: ctx.chapter_a.id,
        section_id: ctx.section_a1.id
      })

    attempt!(ctx.student, q, true)
    attempt!(ctx.student, q, false)

    trend = Assessments.topic_accuracy_trend(ctx.student.id, ctx.section_a1.id, 30)
    assert [%{attempts: n}] = trend
    assert n == 2
  end
end
