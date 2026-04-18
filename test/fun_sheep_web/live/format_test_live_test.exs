defmodule FunSheepWeb.FormatTestLiveTest do
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

    # Create some questions
    for i <- 1..3 do
      FunSheep.Questions.create_question(%{
        content: "Question #{i}",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{"A" => "Yes", "B" => "No", "C" => "Maybe", "D" => "None"},
        course_id: course.id,
        chapter_id: chapter.id
      })
    end

    # Create template and link to schedule
    {:ok, template} =
      FunSheep.Assessments.create_test_format_template(%{
        name: "Test Format",
        structure: %{
          "sections" => [
            %{
              "name" => "MC Section",
              "question_type" => "multiple_choice",
              "count" => 3,
              "points_per_question" => 2,
              "chapter_ids" => [chapter.id]
            }
          ],
          "time_limit_minutes" => 10
        }
      })

    {:ok, schedule} =
      FunSheep.Assessments.create_test_schedule(%{
        name: "Format Quiz",
        test_date: Date.add(Date.utc_today(), 7),
        scope: %{"chapter_ids" => [chapter.id]},
        user_role_id: user_role.id,
        course_id: course.id,
        format_template_id: template.id
      })

    %{user_role: user_role, course: course, chapter: chapter, schedule: schedule}
  end

  describe "format test page" do
    test "renders with questions", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/tests/#{schedule.id}/format-test")

      assert html =~ "Format Quiz"
      assert html =~ "Format Practice Test"
      assert html =~ "MC Section"
      assert html =~ "Question 1 of"
    end

    test "shows timer when time limit is set", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/tests/#{schedule.id}/format-test")

      # Timer should show 10:00 initially
      assert html =~ "10:00" or html =~ "09:5"
    end
  end

  describe "format test without template" do
    test "shows no template message", %{
      conn: conn,
      user_role: ur,
      course: course,
      chapter: chapter
    } do
      # Create a schedule without a template
      {:ok, schedule_no_template} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "No Template",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: ur.id,
          course_id: course.id
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/tests/#{schedule_no_template.id}/format-test")

      assert html =~ "No format template defined"
      assert html =~ "Define Test Format"
    end
  end
end
