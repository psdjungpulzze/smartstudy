defmodule FunSheep.Assessments.PercentileHistoryTest do
  @moduledoc """
  Covers `Assessments.readiness_percentile_history/3` (spec §6.1).
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.{Assessments, Repo}
  alias FunSheep.Assessments.ReadinessScore
  alias FunSheep.ContentFixtures

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

    ts =
      DateTime.utc_now() |> DateTime.add(-days_ago, :day) |> DateTime.truncate(:second)

    Repo.update_all(
      from(r in ReadinessScore, where: r.id == ^rs.id),
      set: [inserted_at: ts, calculated_at: ts]
    )
  end

  setup do
    course = ContentFixtures.create_course()
    me = ContentFixtures.create_user_role(%{role: :student, grade: "10"})

    {:ok, my_schedule} =
      Assessments.create_test_schedule(%{
        name: "My Test",
        test_date: Date.add(Date.utc_today(), 14),
        scope: %{"chapter_ids" => []},
        user_role_id: me.id,
        course_id: course.id
      })

    %{course: course, me: me, schedule: my_schedule}
  end

  test "returns [] when cohort is too small", ctx do
    snapshot!(ctx.me, ctx.schedule, 70.0, 3)

    assert Assessments.readiness_percentile_history(ctx.me.id, ctx.schedule.id, 4) == []
  end

  test "bucketizes by week and includes percentile per bucket", ctx do
    # Seed a comparable cohort for the same course — spread scores.
    for {score, days_ago} <- [{40.0, 3}, {55.0, 3}, {65.0, 3}, {80.0, 3}, {90.0, 3}] do
      peer =
        ContentFixtures.create_user_role(%{role: :student, grade: "10"})

      {:ok, sched} =
        Assessments.create_test_schedule(%{
          name: "Peer",
          test_date: Date.add(Date.utc_today(), 14),
          scope: %{"chapter_ids" => []},
          user_role_id: peer.id,
          course_id: ctx.course.id
        })

      snapshot!(peer, sched, score, days_ago)
    end

    snapshot!(ctx.me, ctx.schedule, 70.0, 3)

    history = Assessments.readiness_percentile_history(ctx.me.id, ctx.schedule.id, 4)

    assert length(history) >= 1

    Enum.each(history, fn row ->
      assert row.percentile >= 0 and row.percentile <= 100
      assert row.total >= 2
      assert row.rank >= 1
    end)
  end
end
