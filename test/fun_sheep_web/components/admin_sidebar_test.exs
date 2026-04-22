defmodule FunSheepWeb.Components.AdminSidebarTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import FunSheepWeb.Components.AdminSidebar

  describe "admin_sidebar/1" do
    test "renders every section heading and Overview link" do
      html = render_component(&admin_sidebar/1, %{current_path: "/admin"})

      assert html =~ "Content"
      assert html =~ "Operations"
      assert html =~ "Interactor"
      assert html =~ "Settings"

      assert html =~ "Overview"
      assert html =~ "Users"
      assert html =~ "AI usage"
      assert html =~ "Feature flags"
      assert html =~ "Agents"
    end

    test "highlights the active link" do
      html = render_component(&admin_sidebar/1, %{current_path: "/admin/usage/ai"})
      # Active class uses the light-green background + green text
      assert html =~ "bg-[#E8F8EB]"
      assert html =~ "AI usage"
    end

    test "renders /admin/jobs as an external link (not navigate)" do
      html = render_component(&admin_sidebar/1, %{current_path: "/admin"})
      # External: plain <a href>, not data-phx-link="redirect"
      assert html =~ ~s(href="/admin/jobs")
    end
  end
end
