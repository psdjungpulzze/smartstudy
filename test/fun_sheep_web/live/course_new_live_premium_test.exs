defmodule FunSheepWeb.CourseNewLivePremiumTest do
  use FunSheepWeb.ConnCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  import Mox
  import Phoenix.LiveViewTest

  alias FunSheep.AI.ClientMock
  alias FunSheep.Accounts
  alias FunSheep.Courses

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    stub(ClientMock, :call, fn _sys, _usr, _opts -> {:error, :not_configured_in_test} end)
    :ok
  end

  defp user_role_conn(conn, attrs \\ %{}) do
    defaults = %{
      interactor_user_id: "cn_premium_#{System.unique_integer([:positive])}",
      role: :student,
      email: "cn_premium_#{System.unique_integer([:positive])}@test.com",
      display_name: "Premium Test User"
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

  describe "premium catalog options" do
    test "premium catalog section is hidden for non-standardized courses", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "My Custom Class", "subject" => "History"})

      html = render(view)
      refute html =~ "Catalog &amp; Test Options"
      refute html =~ "Publish as premium catalog"
    end

    test "premium catalog section appears for recognized SAT course", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "SAT Math", "subject" => "Mathematics"})

      html = render(view)
      assert html =~ "Catalog &amp; Test Options"
      assert html =~ "Publish as premium catalog"
      assert html =~ "Auto-create upcoming test dates"
    end

    test "toggling premium catalog shows access level and price fields", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "SAT Math", "subject" => "Mathematics"})

      # Toggle premium on
      render_click(view, "toggle_premium_catalog", %{})
      html = render(view)

      assert html =~ "Access level"
      assert html =~ "One-time price"
    end

    test "toggling auto_create_tests changes its state", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/courses/new")

      view
      |> element("#course-form")
      |> render_change(%{"course_name" => "SAT Math", "subject" => "Mathematics"})

      # Default off
      html_before = render(view)
      assert html_before =~ ~s(aria-checked="false")

      # Toggle auto_create_tests
      render_click(view, "toggle_auto_create_tests", %{})
      html_after = render(view)
      assert html_after =~ ~s(aria-checked="true")
    end

    test "creates course with auto_create_tests when SAT and toggle on", %{conn: conn} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {conn, _user_role} = user_role_conn(conn)
        {:ok, view, _html} = live(conn, ~p"/courses/new")

        view
        |> element("#course-form")
        |> render_change(%{"course_name" => "SAT Math", "subject" => "Mathematics"})

        render_click(view, "toggle_grade", %{"grade" => "11"})
        render_click(view, "no_textbook", %{})
        render_click(view, "toggle_auto_create_tests", %{})

        assert {:error, {:live_redirect, _}} =
                 view |> element("#course-form") |> render_submit()

        course = Courses.list_courses() |> Enum.find(&(&1.name == "SAT Math"))
        assert course != nil
        assert course.auto_create_tests == true
        assert course.catalog_test_type == "sat"
      end)
    end
  end
end
