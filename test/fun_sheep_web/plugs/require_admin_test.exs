defmodule FunSheepWeb.Plugs.RequireAdminTest do
  use FunSheepWeb.ConnCase, async: true

  alias FunSheepWeb.Plugs.RequireAdmin

  describe "call/2" do
    test "passes the conn through when current_role is admin", %{conn: conn} do
      conn = Plug.Conn.assign(conn, :current_role, "admin")
      assert RequireAdmin.call(conn, []) == conn
    end

    test "raises NotFoundError when current_role is not admin", %{conn: conn} do
      conn = Plug.Conn.assign(conn, :current_role, "student")

      assert_raise FunSheepWeb.NotFoundError, fn ->
        RequireAdmin.call(conn, [])
      end
    end

    test "raises NotFoundError when current_role is missing entirely", %{conn: conn} do
      assert_raise FunSheepWeb.NotFoundError, fn ->
        RequireAdmin.call(conn, [])
      end
    end
  end
end
