defmodule FunSheep.Assessments.ReadinessTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Assessments
  alias FunSheep.ContentFixtures

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter} =
      FunSheep.Courses.create_chapter(%{
        name: "Chapter 1",
        position: 1,
        course_id: course.id
      })

    # Create a section so ReadinessCalculator can resolve chapter_ids via
    # Courses.list_sections_by_chapters/1.
    {:ok, _section} =
      FunSheep.Courses.create_section(%{name: "Section 1", position: 1, chapter_id: chapter.id})

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
        FunSheep.Questions.create_question(%{
          validation_status: :passed,
          content: "Q1",
          answer: "A",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          chapter_id: ch.id
        })

      FunSheep.Questions.create_question_attempt(%{
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
    test "returns a live-computed struct (no DB write required)", ctx do
      %{user_role: ur, schedule: schedule} = ctx

      latest = Assessments.latest_readiness(ur.id, schedule.id)

      assert latest != nil
      assert latest.user_role_id == ur.id
      assert latest.test_schedule_id == schedule.id
      # No attempts yet → 0%.
      assert latest.aggregate_score == 0.0

      # No persisted snapshot was created.
      assert Assessments.list_readiness_history(ur.id, schedule.id) == []
    end

    test "reflects recorded attempts immediately", ctx do
      %{user_role: ur, course: course, chapter: ch, schedule: schedule} = ctx

      {:ok, q} =
        FunSheep.Questions.create_question(%{
          validation_status: :passed,
          content: "Q1",
          answer: "A",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          chapter_id: ch.id
        })

      FunSheep.Questions.create_question_attempt(%{
        user_role_id: ur.id,
        question_id: q.id,
        answer_given: "A",
        is_correct: true
      })

      latest = Assessments.latest_readiness(ur.id, schedule.id)
      assert latest.aggregate_score == 100.0

      # A wrong attempt drags the score down.
      FunSheep.Questions.create_question_attempt(%{
        user_role_id: ur.id,
        question_id: q.id,
        answer_given: "B",
        is_correct: false
      })

      latest = Assessments.latest_readiness(ur.id, schedule.id)
      assert latest.aggregate_score == 50.0
    end

    test "returns nil when the schedule doesn't exist", %{user_role: ur} do
      assert Assessments.latest_readiness(ur.id, Ecto.UUID.generate()) == nil
    end
  end

  describe "attempts_count_for_schedule/2" do
    test "counts attempts against questions in the schedule's scope", ctx do
      %{user_role: ur, course: course, chapter: ch, schedule: schedule} = ctx

      assert Assessments.attempts_count_for_schedule(ur.id, schedule) == 0

      {:ok, q} =
        FunSheep.Questions.create_question(%{
          validation_status: :passed,
          content: "Q1",
          answer: "A",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id,
          chapter_id: ch.id
        })

      for _ <- 1..3 do
        FunSheep.Questions.create_question_attempt(%{
          user_role_id: ur.id,
          question_id: q.id,
          answer_given: "A",
          is_correct: true
        })
      end

      assert Assessments.attempts_count_for_schedule(ur.id, schedule) == 3
    end

    test "returns 0 for schedules with an empty scope", %{user_role: ur, course: course} do
      {:ok, schedule} =
        Assessments.create_test_schedule(%{
          name: "Empty",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => []},
          user_role_id: ur.id,
          course_id: course.id
        })

      assert Assessments.attempts_count_for_schedule(ur.id, schedule) == 0
    end
  end
end
