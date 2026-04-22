defmodule FunSheep.Assessments.CohortBandsTest do
  @moduledoc """
  Covers `Assessments.cohort_percentile_bands/2` + the ETS cache (spec §6.3).
  """

  use FunSheep.DataCase, async: false

  alias FunSheep.{Assessments, Repo}
  alias FunSheep.Assessments.{CohortCache, ReadinessScore}
  alias FunSheep.ContentFixtures

  setup do
    CohortCache.flush()
    course = ContentFixtures.create_course(%{grade: "10"})

    {:ok, schedule} =
      Assessments.create_test_schedule(%{
        name: "Shared Test",
        test_date: Date.add(Date.utc_today(), 10),
        scope: %{"chapter_ids" => []},
        user_role_id: ContentFixtures.create_user_role(%{role: :student, grade: "10"}).id,
        course_id: course.id
      })

    %{course: course, schedule: schedule}
  end

  defp add_cohort_student(schedule, score, grade) do
    student = ContentFixtures.create_user_role(%{role: :student, grade: grade})

    {:ok, _} =
      %ReadinessScore{}
      |> ReadinessScore.changeset(%{
        user_role_id: student.id,
        test_schedule_id: schedule.id,
        aggregate_score: score,
        chapter_scores: %{},
        topic_scores: %{},
        skill_scores: %{},
        calculated_at: DateTime.utc_now()
      })
      |> Repo.insert()

    student
  end

  test "returns :small_cohort when fewer than 20 students", ctx do
    for s <- 0..9, do: add_cohort_student(ctx.schedule, 50.0 + s, "10")

    assert %{status: :small_cohort, size: n} =
             Assessments.cohort_percentile_bands(ctx.course.id, "10")

    assert n < 20
  end

  test "returns full bands when cohort reaches threshold", ctx do
    for s <- 0..24, do: add_cohort_student(ctx.schedule, 20.0 + s * 3.0, "10")

    CohortCache.flush()
    result = Assessments.cohort_percentile_bands(ctx.course.id, "10")

    assert result.status == :ok
    assert result.size >= 20
    assert is_number(result.p25)
    assert is_number(result.p50)
    assert is_number(result.p75)
    assert is_number(result.p90)
    assert result.p25 <= result.p50
    assert result.p50 <= result.p75
    assert result.p75 <= result.p90
  end

  test "results are cached", ctx do
    for s <- 0..24, do: add_cohort_student(ctx.schedule, 40.0 + s, "10")

    CohortCache.flush()
    first = Assessments.cohort_percentile_bands(ctx.course.id, "10")
    assert first.status == :ok

    # Add another student — without cache invalidation the cached value should persist.
    add_cohort_student(ctx.schedule, 99.0, "10")
    second = Assessments.cohort_percentile_bands(ctx.course.id, "10")
    assert second == first
  end

  test "grade filter is respected", ctx do
    # Build a full cohort in grade 11, then ask for grade 10.
    for s <- 0..24, do: add_cohort_student(ctx.schedule, 40.0 + s, "11")

    CohortCache.flush()
    assert %{status: :small_cohort} = Assessments.cohort_percentile_bands(ctx.course.id, "10")
  end
end
