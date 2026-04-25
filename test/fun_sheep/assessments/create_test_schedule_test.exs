defmodule FunSheep.Assessments.CreateTestScheduleTest do
  @moduledoc """
  `Assessments.create_test_schedule/1` must enqueue generation for every
  chapter in scope that doesn't already have enough visible questions. This
  is what stops assessments from entering the world pre-broken — before
  this hook, a schedule could be created pointing at chapters with zero
  questions and the student would only discover the gap on first visit.
  """

  use FunSheep.DataCase, async: true

  use Oban.Testing, repo: FunSheep.Repo

  alias FunSheep.Assessments
  alias FunSheep.{Courses, ContentFixtures, Questions}
  alias FunSheep.Workers.AIQuestionGenerationWorker

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})
    %{user_role: user_role, course: course}
  end

  defp passed_question(course, chapter, section, idx) do
    passed_question_with_difficulty(course, chapter, section, idx, :medium)
  end

  defp passed_question_with_difficulty(course, chapter, section, idx, difficulty) do
    {:ok, _} =
      Questions.create_question(%{
        validation_status: :passed,
        content: "Q#{idx}-#{difficulty}",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: difficulty,
        options: %{"A" => "a", "B" => "b"},
        course_id: course.id,
        chapter_id: chapter.id,
        section_id: section.id,
        classification_status: :ai_classified
      })
  end

  test "enqueues AIQuestionGenerationWorker for every chapter below threshold", %{
    user_role: user_role,
    course: course
  } do
    {:ok, ch1} = Courses.create_chapter(%{name: "Ch1", position: 1, course_id: course.id})
    {:ok, ch2} = Courses.create_chapter(%{name: "Ch2", position: 2, course_id: course.id})

    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, _schedule} =
        Assessments.create_test_schedule(%{
          name: "Finals",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [ch1.id, ch2.id]},
          user_role_id: user_role.id,
          course_id: course.id
        })

      assert_enqueued(
        worker: AIQuestionGenerationWorker,
        args: %{"course_id" => course.id, "chapter_id" => ch1.id, "mode" => "from_material"}
      )

      assert_enqueued(
        worker: AIQuestionGenerationWorker,
        args: %{"course_id" => course.id, "chapter_id" => ch2.id, "mode" => "from_material"}
      )
    end)
  end

  test "does NOT enqueue for chapters that already have enough passed+classified questions", %{
    user_role: user_role,
    course: course
  } do
    {:ok, ch1} = Courses.create_chapter(%{name: "Ch1", position: 1, course_id: course.id})
    {:ok, sec1} = Courses.create_section(%{name: "Skill", position: 1, chapter_id: ch1.id})

    # Provide questions at every difficulty level so ch1 passes both the total
    # gate AND the per-difficulty gate (no backfill enqueue needed).
    for {diff, base} <- [{:easy, 0}, {:medium, 3}, {:hard, 6}],
        i <- 1..3,
        do: passed_question_with_difficulty(course, ch1, sec1, base + i, diff)

    {:ok, ch2} = Courses.create_chapter(%{name: "Ch2", position: 2, course_id: course.id})

    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, _schedule} =
        Assessments.create_test_schedule(%{
          name: "Finals",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [ch1.id, ch2.id]},
          user_role_id: user_role.id,
          course_id: course.id
        })

      # Only ch2 (empty) should enqueue; ch1 is already ready.
      refute_enqueued(
        worker: AIQuestionGenerationWorker,
        args: %{"course_id" => course.id, "chapter_id" => ch1.id}
      )

      assert_enqueued(
        worker: AIQuestionGenerationWorker,
        args: %{"course_id" => course.id, "chapter_id" => ch2.id, "mode" => "from_material"}
      )
    end)
  end

  test "noop when every in-scope chapter is already ready", %{
    user_role: user_role,
    course: course
  } do
    {:ok, chapter} = Courses.create_chapter(%{name: "Ch1", position: 1, course_id: course.id})
    {:ok, section} = Courses.create_section(%{name: "Skill", position: 1, chapter_id: chapter.id})

    # Provide questions at all three difficulty levels so neither the total gate
    # nor the per-difficulty gate triggers any enqueue.
    for {diff, base} <- [{:easy, 0}, {:medium, 3}, {:hard, 6}],
        i <- 1..3,
        do: passed_question_with_difficulty(course, chapter, section, base + i, diff)

    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, _schedule} =
        Assessments.create_test_schedule(%{
          name: "Finals",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: user_role.id,
          course_id: course.id
        })

      refute_enqueued(worker: AIQuestionGenerationWorker)
    end)
  end

  test "still returns an error on invalid attrs without enqueuing anything", %{
    user_role: user_role,
    course: course
  } do
    {:ok, chapter} = Courses.create_chapter(%{name: "Ch1", position: 1, course_id: course.id})

    Oban.Testing.with_testing_mode(:manual, fn ->
      # Missing required :name
      assert {:error, %Ecto.Changeset{}} =
               Assessments.create_test_schedule(%{
                 test_date: Date.add(Date.utc_today(), 7),
                 scope: %{"chapter_ids" => [chapter.id]},
                 user_role_id: user_role.id,
                 course_id: course.id
               })

      refute_enqueued(worker: AIQuestionGenerationWorker)
    end)
  end
end
