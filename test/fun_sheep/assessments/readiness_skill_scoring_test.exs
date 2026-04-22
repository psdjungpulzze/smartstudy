defmodule FunSheep.Assessments.ReadinessSkillScoringTest do
  @moduledoc """
  Tests weakest-N aggregate (I-10), per-skill status (I-9), and
  all_skills_mastered?/1 + unmastered_skills/1 (I-8).
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.Assessments
  alias FunSheep.Assessments.ReadinessCalculator
  alias FunSheep.{Courses, Questions, ContentFixtures}

  defp mk_question(course, chapter, section, difficulty, tag) do
    {:ok, q} =
      Questions.create_question(%{
        validation_status: :passed,
        content: "Q-#{tag}",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: difficulty,
        options: %{"A" => "a", "B" => "b"},
        course_id: course.id,
        chapter_id: chapter.id,
        section_id: section.id,
        classification_status: :admin_reviewed
      })

    q
  end

  defp attempt(user_role, question, is_correct) do
    {:ok, att} =
      Questions.create_question_attempt(%{
        user_role_id: user_role.id,
        question_id: question.id,
        answer_given: if(is_correct, do: "A", else: "B"),
        is_correct: is_correct
      })

    att
  end

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter} =
      Courses.create_chapter(%{name: "Ch 1", position: 1, course_id: course.id})

    {:ok, sec_strong} =
      Courses.create_section(%{name: "Strong", position: 1, chapter_id: chapter.id})

    {:ok, sec_weak} =
      Courses.create_section(%{name: "Weak", position: 2, chapter_id: chapter.id})

    {:ok, schedule} =
      Assessments.create_test_schedule(%{
        name: "Midterm",
        test_date: Date.add(Date.utc_today(), 7),
        scope: %{"chapter_ids" => [chapter.id]},
        user_role_id: user_role.id,
        course_id: course.id
      })

    %{
      user_role: user_role,
      course: course,
      chapter: chapter,
      sec_strong: sec_strong,
      sec_weak: sec_weak,
      schedule: schedule
    }
  end

  test "weak section surfaces and blocks 100% readiness", ctx do
    s1 = mk_question(ctx.course, ctx.chapter, ctx.sec_strong, :medium, "s1")
    attempt(ctx.user_role, s1, true)

    weak_qs =
      for i <- 1..10,
          do: mk_question(ctx.course, ctx.chapter, ctx.sec_weak, :medium, "w#{i}")

    for {q, i} <- Enum.with_index(weak_qs), do: attempt(ctx.user_role, q, i < 2)

    result = ReadinessCalculator.calculate(ctx.user_role.id, ctx.schedule)

    assert result.skill_scores[ctx.sec_weak.id].score == 20.0
    assert result.skill_scores[ctx.sec_weak.id].status == :weak
    refute ReadinessCalculator.all_skills_mastered?(result)
    assert result.aggregate_score < 100.0
  end

  test "aggregate = 100 iff every skill is :mastered", ctx do
    strongs =
      for i <- 1..3,
          do: mk_question(ctx.course, ctx.chapter, ctx.sec_strong, :medium, "s#{i}")

    weaks =
      for i <- 1..3,
          do: mk_question(ctx.course, ctx.chapter, ctx.sec_weak, :medium, "w#{i}")

    Enum.each(strongs ++ weaks, &attempt(ctx.user_role, &1, true))

    result = ReadinessCalculator.calculate(ctx.user_role.id, ctx.schedule)

    assert result.skill_scores[ctx.sec_strong.id].status == :mastered
    assert result.skill_scores[ctx.sec_weak.id].status == :mastered
    assert result.aggregate_score == 100.0
    assert ReadinessCalculator.all_skills_mastered?(result)
    assert ReadinessCalculator.unmastered_skills(result) == []
  end

  test "sections with zero attempts are :insufficient_data", ctx do
    result = ReadinessCalculator.calculate(ctx.user_role.id, ctx.schedule)
    assert result.skill_scores[ctx.sec_strong.id].status == :insufficient_data
    assert result.skill_scores[ctx.sec_weak.id].status == :insufficient_data
  end

  test "persisted readiness stores skill_scores (JSONB round-trip)", ctx do
    s1 = mk_question(ctx.course, ctx.chapter, ctx.sec_strong, :medium, "s1")
    attempt(ctx.user_role, s1, true)

    {:ok, record} = Assessments.calculate_and_save_readiness(ctx.user_role.id, ctx.schedule.id)
    reloaded = FunSheep.Repo.reload(record)

    stored =
      reloaded.skill_scores
      |> Map.values()
      |> Enum.map(& &1["status"])

    assert "insufficient_data" in stored
  end
end
