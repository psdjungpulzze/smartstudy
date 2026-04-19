defmodule FunSheepWeb.StudyGuideLiveTest do
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
        name: "Biology Basics",
        position: 1,
        course_id: course.id
      })

    {:ok, schedule} =
      FunSheep.Assessments.create_test_schedule(%{
        name: "Bio Final",
        test_date: Date.add(Date.utc_today(), 10),
        scope: %{"chapter_ids" => [chapter.id]},
        user_role_id: user_role.id,
        course_id: course.id
      })

    # Generate a study guide
    {:ok, guide} =
      FunSheep.Learning.StudyGuideGenerator.generate(user_role.id, schedule.id)

    %{user_role: user_role, course: course, chapter: chapter, schedule: schedule, guide: guide}
  end

  describe "study guide page" do
    test "renders study guide", %{conn: conn, user_role: ur, schedule: schedule, guide: guide} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      assert html =~ "Study Guide: Bio Final"
      assert html =~ "Test Course"
    end

    test "shows sections with priority badges", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      guide: guide
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      assert html =~ "Biology Basics"
      assert html =~ "Critical"
    end

    test "shows aggregate score", %{conn: conn, user_role: ur, schedule: schedule, guide: guide} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{schedule.course_id}/study-guides/#{guide.id}")

      assert html =~ "readiness"
    end
  end

  describe "study guides list" do
    test "renders list page", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/study-guides")

      assert html =~ "Study Guides"
    end

    test "shows generated guides", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/study-guides")

      assert html =~ "Study Guide: Bio Final"
    end

    test "shows generate new section", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/study-guides")

      assert html =~ "Generate New Guide"
      assert html =~ "Select a test schedule"
    end
  end
end
