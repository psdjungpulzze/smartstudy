defmodule StudySmartWeb.TestFormatLiveTest do
  use StudySmartWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StudySmart.ContentFixtures

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
      StudySmart.Courses.create_chapter(%{
        name: "Chapter 1",
        position: 1,
        course_id: course.id
      })

    {:ok, schedule} =
      StudySmart.Assessments.create_test_schedule(%{
        name: "Midterm",
        test_date: Date.add(Date.utc_today(), 7),
        scope: %{"chapter_ids" => [chapter.id]},
        user_role_id: user_role.id,
        course_id: course.id
      })

    %{user_role: user_role, course: course, chapter: chapter, schedule: schedule}
  end

  describe "format page" do
    test "renders the format page", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/tests/#{schedule.id}/format")

      assert html =~ "Test Format"
      assert html =~ "Midterm"
      assert html =~ "Define Test Sections"
    end

    test "can add a section", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/tests/#{schedule.id}/format")

      # Fill in section form
      render_change(view, "update_section_form", %{
        "name" => "MC Section",
        "question_type" => "multiple_choice",
        "count" => "5",
        "points_per_question" => "2"
      })

      # Add the section
      html = render_submit(view, "add_section")

      assert html =~ "MC Section"
      assert html =~ "Multiple Choice"
      assert html =~ "5 questions"
    end
  end
end
