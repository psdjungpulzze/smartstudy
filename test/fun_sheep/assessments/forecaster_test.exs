defmodule FunSheep.Assessments.ForecasterTest do
  @moduledoc """
  Covers `FunSheep.Assessments.Forecaster.forecast/2` (spec §6.2).
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.{Assessments, Repo}
  alias FunSheep.Assessments.{Forecaster, ReadinessScore}
  alias FunSheep.ContentFixtures

  setup do
    student = ContentFixtures.create_user_role(%{role: :student})
    course = ContentFixtures.create_course()

    {:ok, schedule} =
      Assessments.create_test_schedule(%{
        name: "Final",
        test_date: Date.add(Date.utc_today(), 30),
        scope: %{"chapter_ids" => []},
        user_role_id: student.id,
        course_id: course.id
      })

    %{student: student, course: course, schedule: schedule}
  end

  defp snapshot!(student, schedule, score, days_ago) do
    {:ok, rs} =
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

    # Backdate inserted_at (ReadinessScore.changeset doesn't set it)
    backdated = DateTime.utc_now() |> DateTime.add(-days_ago, :day) |> DateTime.truncate(:second)

    Repo.update_all(
      from(r in ReadinessScore, where: r.id == ^rs.id),
      set: [inserted_at: backdated, calculated_at: backdated]
    )

    rs
  end

  test "returns :no_target when target_readiness_score is nil", ctx do
    assert %{status: :insufficient_data, reason: :no_target} =
             Forecaster.forecast(ctx.student.id, ctx.schedule.id)
  end

  test "returns :no_readiness_history when target set but no history", ctx do
    {:ok, schedule} = Assessments.set_target_readiness(ctx.schedule, 80, :guardian)

    assert %{status: :insufficient_data, reason: reason} =
             Forecaster.forecast(ctx.student.id, schedule.id)

    assert reason in [:no_readiness_history, :single_snapshot, :short_history]
  end

  test "projects readiness using recent slope and returns a minute delta", ctx do
    {:ok, schedule} = Assessments.set_target_readiness(ctx.schedule, 85, :guardian)

    # Linearly increasing readiness over 21 days: 50 → 70
    snapshot!(ctx.student, schedule, 50.0, 21)
    snapshot!(ctx.student, schedule, 60.0, 14)
    snapshot!(ctx.student, schedule, 70.0, 0)

    result = Forecaster.forecast(ctx.student.id, schedule.id)

    assert result.status == :ok
    assert result.target == 85
    assert result.projected_readiness > 70.0
    assert result.gap == Float.round(85 - result.projected_readiness, 1)
    assert result.days_to_test == 30
    assert is_integer(result.recommended_daily_minutes)
    assert is_integer(result.minutes_delta)
    assert result.confidence in [:wide_range, :tight]
  end

  test ":test_in_past for a past schedule", ctx do
    {:ok, past} =
      Assessments.create_test_schedule(%{
        name: "Past",
        test_date: Date.add(Date.utc_today(), -5),
        scope: %{"chapter_ids" => []},
        user_role_id: ctx.student.id,
        course_id: ctx.course.id,
        target_readiness_score: 90,
        target_set_by: :guardian,
        target_set_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    snapshot!(ctx.student, past, 50.0, 20)
    snapshot!(ctx.student, past, 70.0, 0)

    assert %{status: :insufficient_data, reason: :test_in_past} =
             Forecaster.forecast(ctx.student.id, past.id)
  end
end
