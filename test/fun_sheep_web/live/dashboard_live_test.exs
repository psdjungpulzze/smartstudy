defmodule FunSheepWeb.DashboardLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.Courses

  defp auth_conn(conn) do
    conn
    |> init_test_session(%{
      dev_user_id: "test_student",
      dev_user: %{
        "id" => "test_student",
        "role" => "student",
        "email" => "test@test.com",
        "display_name" => "Test Student"
      }
    })
  end

  describe "student home" do
    test "renders home page", %{conn: conn} do
      conn = auth_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Test Student"
      assert html =~ "My Courses"
    end

    test "shows courses section with links", %{conn: conn} do
      conn = auth_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Browse"
      assert html =~ "Add"
    end

    test "shows no courses message when empty", %{conn: conn} do
      conn = auth_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "No courses yet"
    end

    test "shows course cards when courses exist", %{conn: conn} do
      {:ok, user_role} =
        FunSheep.Accounts.create_user_role(%{
          interactor_user_id: "test_interactor_id",
          role: :student,
          email: "test@test.com",
          display_name: "Test Student"
        })

      {:ok, _course} =
        Courses.create_course(%{
          name: "My Math Course",
          subject: "Math",
          grade: "10",
          created_by_id: user_role.id
        })

      conn =
        conn
        |> init_test_session(%{
          dev_user_id: user_role.id,
          dev_user: %{
            "id" => user_role.id,
            "role" => "student",
            "email" => "test@test.com",
            "display_name" => "Test Student"
          }
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "My Math Course"
      assert html =~ "Math"
      assert html =~ "Grade 10"
    end

    test "shows coming up section", %{conn: conn} do
      conn = auth_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Coming Up"
      assert html =~ "all clear"
    end
  end
end
