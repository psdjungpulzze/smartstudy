defmodule FunSheep.Assessments.EngineNoQuestionsTest do
  @moduledoc """
  Regression: when a schedule's chapters have no questions yet, the
  engine must NOT pretend the assessment is complete. It must return a
  distinct `:no_questions_available` terminal status so the UI can fail
  honestly (per the "no fake content" rule) instead of writing a 0-of-0
  "complete" result that advances the study path.
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.Assessments.Engine
  alias FunSheep.{Courses, ContentFixtures}

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter} =
      Courses.create_chapter(%{name: "Ch 1", position: 1, course_id: course.id})

    {:ok, _section} =
      Courses.create_section(%{name: "Sec 1", position: 1, chapter_id: chapter.id})

    {:ok, schedule} =
      FunSheep.Assessments.create_test_schedule(%{
        name: "Finals",
        test_date: Date.add(Date.utc_today(), 7),
        scope: %{"chapter_ids" => [chapter.id]},
        user_role_id: user_role.id,
        course_id: course.id
      })

    %{schedule: schedule}
  end

  test "chapters with zero questions return :no_questions_available, not :complete", %{
    schedule: schedule
  } do
    state = Engine.start_assessment(schedule)

    assert {:no_questions_available, final_state} = Engine.next_question(state)
    assert final_state.status == :no_questions_available
    assert final_state.topic_attempts == %{}
  end

  test "a schedule with no chapters at all also returns :no_questions_available" do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, schedule} =
      FunSheep.Assessments.create_test_schedule(%{
        name: "Empty",
        test_date: Date.add(Date.utc_today(), 7),
        scope: %{"chapter_ids" => []},
        user_role_id: user_role.id,
        course_id: course.id
      })

    state = Engine.start_assessment(schedule)
    assert {:no_questions_available, _} = Engine.next_question(state)
  end
end
