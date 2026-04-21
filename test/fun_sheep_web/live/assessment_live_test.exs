defmodule FunSheepWeb.AssessmentLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.ContentFixtures

  defp auth_conn(conn, user_role) do
    conn
    |> init_test_session(%{
      dev_user_id: user_role.interactor_user_id,
      dev_user: %{
        "id" => user_role.interactor_user_id,
        "role" => "student",
        "email" => user_role.email,
        "display_name" => user_role.display_name,
        "user_role_id" => user_role.id
      }
    })
  end

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter} =
      FunSheep.Courses.create_chapter(%{
        name: "Chapter 1",
        position: 1,
        course_id: course.id
      })

    {:ok, _q1} =
      FunSheep.Questions.create_question(%{
        validation_status: :passed,
        content: "What is the powerhouse of the cell?",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{"A" => "Mitochondria", "B" => "Nucleus", "C" => "Ribosome", "D" => "Golgi"},
        course_id: course.id,
        chapter_id: chapter.id
      })

    {:ok, _q2} =
      FunSheep.Questions.create_question(%{
        validation_status: :passed,
        content: "DNA stands for?",
        answer: "B",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{
          "A" => "Deoxyribonucleic Acid Test",
          "B" => "Deoxyribonucleic Acid",
          "C" => "Ribonucleic Acid",
          "D" => "None"
        },
        course_id: course.id,
        chapter_id: chapter.id
      })

    {:ok, _q3} =
      FunSheep.Questions.create_question(%{
        validation_status: :passed,
        content: "Cells divide via?",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{
          "A" => "Mitosis",
          "B" => "Osmosis",
          "C" => "Diffusion",
          "D" => "Photosynthesis"
        },
        course_id: course.id,
        chapter_id: chapter.id
      })

    {:ok, schedule} =
      FunSheep.Assessments.create_test_schedule(%{
        name: "Bio Quiz",
        test_date: Date.add(Date.utc_today(), 7),
        scope: %{"chapter_ids" => [chapter.id]},
        user_role_id: user_role.id,
        course_id: course.id
      })

    %{user_role: user_role, course: course, chapter: chapter, schedule: schedule}
  end

  describe "assessment flow" do
    test "starts and shows a question", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/assess")

      assert html =~ "Bio Quiz"
      assert html =~ "Question 1"
      # Should show one of the question contents
      assert html =~ "powerhouse" or html =~ "DNA" or html =~ "Cells divide"
    end

    test "shows feedback after answering", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/assess")

      # Select an answer
      render_click(view, "select_answer", %{"answer" => "A"})

      # Submit the answer
      html = render_click(view, "submit_answer")

      # Should show feedback (either correct or incorrect)
      assert html =~ "Correct" or html =~ "Incorrect"
      assert html =~ "Next Question"
    end

    test "advances to next question after feedback", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/assess")

      # Answer first question
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")

      # Click next
      html = render_click(view, "next_question")

      # Should show question 2
      assert html =~ "Question 2"
    end

    test "renders summary without crashing when no questions match scope", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      # Schedule scoped to a chapter that has no questions — exercises the
      # `{:complete, state}` branch that previously crashed with
      # `KeyError: :course_id` in render_summary/1.
      {:ok, empty_chapter} =
        FunSheep.Courses.create_chapter(%{
          name: "Empty Chapter",
          position: 99,
          course_id: course.id
        })

      {:ok, empty_schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Empty Scope",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [empty_chapter.id]},
          user_role_id: ur.id,
          course_id: course.id
        })

      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{empty_schedule.course_id}/tests/#{empty_schedule.id}/assess")

      assert html =~ "Assessment Complete"
      assert html =~ ~s|href="/courses/#{course.id}/tests"|
    end
  end
end
