defmodule StudySmartWeb.DevLoginLiveTest do
  use StudySmartWeb.ConnCase, async: true

  # Dev routes are only compiled when dev_routes config is true.
  # In test env, these routes are not available, so we test the
  # DevLoginLive module's render output directly.

  describe "render/1" do
    test "renders 4 role cards" do
      # Build assigns that mount/3 would produce
      assigns = %{
        __changed__: %{},
        page_title: "Dev Login",
        flash: %{},
        live_action: :index
      }

      html = Phoenix.LiveViewTest.rendered_to_string(StudySmartWeb.DevLoginLive.render(assigns))

      assert html =~ "Student"
      assert html =~ "Parent"
      assert html =~ "Teacher"
      assert html =~ "Admin"
      assert html =~ "Fun Sheep"
    end

    test "each role card has a form posting to /dev/auth" do
      assigns = %{
        __changed__: %{},
        page_title: "Dev Login",
        flash: %{},
        live_action: :index
      }

      html = Phoenix.LiveViewTest.rendered_to_string(StudySmartWeb.DevLoginLive.render(assigns))

      # There should be 4 forms with action /dev/auth
      assert length(Regex.scan(~r|action="/dev/auth"|, html)) == 4

      # Each form should have a hidden role input
      assert html =~ ~s(value="student")
      assert html =~ ~s(value="parent")
      assert html =~ ~s(value="teacher")
      assert html =~ ~s(value="admin")
    end
  end

  describe "DevAuthController" do
    test "create/2 sets session and redirects for student role", %{conn: conn} do
      conn = post(conn, "/dev/auth", %{"role" => "student"})

      assert redirected_to(conn) == "/dashboard"
      assert get_session(conn, :dev_user_id)
      assert get_session(conn, :dev_user)["role"] == "student"
    end

    test "create/2 redirects parent to /parent", %{conn: conn} do
      conn = post(conn, "/dev/auth", %{"role" => "parent"})
      assert redirected_to(conn) == "/parent"
    end

    test "create/2 redirects admin to /admin", %{conn: conn} do
      conn = post(conn, "/dev/auth", %{"role" => "admin"})
      assert redirected_to(conn) == "/admin"
    end
  end
end
