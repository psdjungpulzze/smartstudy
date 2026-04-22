defmodule FunSheepWeb.LoginLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /auth/login" do
    test "renders the role selector with student/teacher/parent chips", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/login")

      assert html =~ "Student"
      assert html =~ "Teacher"
      assert html =~ "Parent"
      # Role selector is present
      assert html =~ "Sign in as"
      # Sign-up link is present for public login
      assert html =~ "Create an account"
    end
  end

  describe "GET /admin/login (hidden admin entry)" do
    test "renders the login form WITHOUT role chips or sign-up CTA", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/login")

      # Same core form…
      assert html =~ "Welcome back!"
      assert html =~ "Password"

      # …but the role selector is hidden.
      refute html =~ "Sign in as"
      refute html =~ "Create an account"
    end
  end
end
