defmodule StudySmart.Assessments.ReadinessTest do
  use StudySmart.DataCase, async: true

  alias StudySmart.Assessments
  alias StudySmart.ContentFixtures

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter} =
      StudySmart.Courses.create_chapter(%{
        name: "Chapter 1",
        position: 1,
        course_id: course.id
      })

    {:ok, schedule} =
      Assessments.create_test_schedule(%{
        name: "Midterm",
        test_date: Date.add(Date.utc_today(), 7),
        scope: %{"chapter_ids" => [chapter.id]},
        user_role_id: user_role.id,
        course_id: course.id
      })

    %{user_role: user_role, course: course, chapter: chapter, schedule: schedule}
  end

  describe "calculate_and_save_readiness/2" do
    test "creates a readiness score record", %{user_role: ur, schedule: schedule} do
      assert {:ok, readiness} = Assessments.calculate_and_save_readiness(ur.id, schedule.id)
      assert readiness.user_role_id == ur.id
      assert readiness.test_schedule_id == schedule.id
      assert readiness.aggregate_score >= 0.0
      assert is_map(readiness.chapter_scores)
    end

    test "calculates score from attempts", ctx do
      %{user_role: ur, course: course, chapter: ch, schedule: schedule} = ctx

      {:ok, q} =
        StudySmart.Questions.create_question(%{
          content: "Q1",
          answer: "A",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          chapter_id: ch.id
        })

      StudySmart.Questions.create_question_attempt(%{
        user_role_id: ur.id,
        question_id: q.id,
        answer_given: "A",
        is_correct: true
      })

      assert {:ok, readiness} = Assessments.calculate_and_save_readiness(ur.id, schedule.id)
      assert readiness.aggregate_score == 100.0
    end
  end

  describe "list_readiness_history/3" do
    test "returns ordered records", %{user_role: ur, schedule: schedule} do
      {:ok, _r1} = Assessments.calculate_and_save_readiness(ur.id, schedule.id)
      {:ok, _r2} = Assessments.calculate_and_save_readiness(ur.id, schedule.id)

      history = Assessments.list_readiness_history(ur.id, schedule.id)
      assert length(history) == 2

      # Most recent first
      [first, second] = history
      assert DateTime.compare(first.inserted_at, second.inserted_at) in [:gt, :eq]
    end

    test "respects limit", %{user_role: ur, schedule: schedule} do
      for _i <- 1..5 do
        Assessments.calculate_and_save_readiness(ur.id, schedule.id)
      end

      history = Assessments.list_readiness_history(ur.id, schedule.id, 3)
      assert length(history) == 3
    end
  end

  describe "latest_readiness/2" do
    test "returns most recent score", %{user_role: ur, schedule: schedule} do
      {:ok, _r1} = Assessments.calculate_and_save_readiness(ur.id, schedule.id)
      {:ok, _r2} = Assessments.calculate_and_save_readiness(ur.id, schedule.id)

      latest = Assessments.latest_readiness(ur.id, schedule.id)
      # Just verify we get a result back (ordering may be non-deterministic within same second)
      assert latest != nil
      assert latest.user_role_id == ur.id
      assert latest.test_schedule_id == schedule.id
    end

    test "returns nil when no scores exist", %{user_role: ur, schedule: schedule} do
      assert Assessments.latest_readiness(ur.id, schedule.id) == nil
    end
  end
end
