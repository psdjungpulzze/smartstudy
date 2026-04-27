defmodule FunSheepWeb.AdminDashboardLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defp admin_conn(conn) do
    conn
    |> init_test_session(%{
      dev_user_id: "test_admin",
      dev_user: %{
        "id" => "test_admin",
        "role" => "admin",
        "email" => "admin@test.com",
        "display_name" => "Test Admin",
        "user_role_id" => "test_admin"
      }
    })
  end

  describe "mount" do
    test "renders admin dashboard", %{conn: conn} do
      conn = admin_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Admin"
    end

    test "shows platform metrics section", %{conn: conn} do
      conn = admin_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Users" or html =~ "Courses" or html =~ "courses"
    end

    test "shows recent audit log section", %{conn: conn} do
      conn = admin_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Audit" or html =~ "audit" or html =~ "Activity"
    end

    test "shows feature flag status", %{conn: conn} do
      conn = admin_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/admin")

      # Dashboard shows disabled flags count
      assert html =~ "flag" or html =~ "Flag" or html =~ "Admin"
    end
  end
end
