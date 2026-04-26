defmodule FunSheepWeb.CourseNewLiveTest do
  # async: false because Oban inline mode runs workers in the LiveView process
  # (not the test process), so with_testing_mode(:manual) doesn't stop them.
  # Shared ClientMock global state requires serialized access.
  use FunSheepWeb.ConnCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  import Mox
  import Phoenix.LiveViewTest

  alias FunSheep.AI.ClientMock
  alias FunSheep.Accounts
  alias FunSheep.Courses
  alias FunSheep.ContentFixtures

  # Catch-all stub: workers' AI calls fail gracefully instead of crashing with
  # Mox.UnexpectedCallError, matching prior behaviour where Agents calls returned
  # {:error, :assistant_not_found}.
  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    stub(ClientMock, :call, fn _sys, _usr, _opts -> {:error, :not_configured_in_test} end)
    :ok
  end

  defp user_role_conn(conn, attrs \\ %{}) do
    defaults = %{
      interactor_user_id: "cn_test_#{System.unique_integer([:positive])}",
      role: :student,
      email: "cn_#{System.unique_integer([:positive])}@test.com",
      display_name: "Course New Test Student"
    }

    {:ok, user_role} = Accounts.create_user_role(Map.merge(defaults, attrs))

    conn =
      init_test_session(conn, %{
        dev_user_id: user_role.id,
        dev_user: %{
          "id" => user_role.id,
          "role" => "student",
          "email" => user_role.email,
          "display_name" => user_role.display_name
        }
      })

    {conn, user_role}
  end

  describe "school_id propagation" do
    test "created course inherits school_id from the user's profile", %{conn: conn} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        school = ContentFixtures.create_school()
        {conn, _user_role} = user_role_conn(conn, %{school_id: school.id})
        {:ok, view, _html} = live(conn, ~p"/courses/new")

        view
        |> element("#course-form")
        |> render_change(%{"course_name" => "AP Chemistry", "subject" => "Chemistry"})

        render_click(view, "toggle_grade", %{"grade" => "11"})
        render_click(view, "no_textbook", %{})

        assert {:error, {:live_redirect, _}} =
                 view |> element("#course-form") |> render_submit()

        course = Courses.list_courses() |> Enum.find(&(&1.name == "AP Chemistry"))
        assert course != nil
        assert course.school_id == school.id
      end)
    end
  end

  describe "default flow (no query param)" do
    test "renders 'New Course' heading and default subcopy", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses/new")

      assert html =~ "New Course"
      assert html =~ "Define your course and textbook"
      assert html =~ "Course Name"
      assert html =~ "Create Course"
    end
  end

  describe "?flow=test — test-first flow" do
    test "renders test-framed heading, subcopy, form label, and submit button", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses/new?flow=test")

      # Heading and subcopy swap to the test-first framing.
      assert html =~ "Add a Test"
      assert html =~ "Tests live inside a class"
      assert html =~ "schedule the test next"

      # Form noun aligns to "class" in test-first mode.
      assert html =~ "Class Name"
      refute html =~ ">Course Name *"

      # Submit button points the user forward to scheduling.
      assert html =~ "Continue to test"
      refute html =~ "Create Course"
    end

    test "after save, redirects to the test-schedule new page for the created course", %{
      conn: conn
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {conn, _user_role} = user_role_conn(conn)
        {:ok, view, _html} = live(conn, ~p"/courses/new?flow=test")

        # Fill subject + grade so the textbook picker becomes visible.
        view
        |> element("#course-form")
        |> render_change(%{"course_name" => "AP Biology", "subject" => "Biology"})

        render_click(view, "toggle_grade", %{"grade" => "11"})

        # Skip textbook so validation passes without hitting the OpenLibrary API.
        render_click(view, "no_textbook", %{})

        assert {:error, {:live_redirect, %{to: redirect_to}}} =
                 view
                 |> element("#course-form")
                 |> render_submit()

        assert redirect_to =~ ~r"^/courses/[^/]+/tests/new$"
      end)
    end
  end
end
