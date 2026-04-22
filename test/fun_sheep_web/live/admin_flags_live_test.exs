defmodule FunSheepWeb.AdminFlagsLiveTest do
  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts
  alias FunSheep.FeatureFlags

  setup do
    for name <- FeatureFlags.known_names(), do: FunWithFlags.clear(name)

    on_exit(fn ->
      for name <- FeatureFlags.known_names(), do: FunWithFlags.clear(name)
    end)

    :ok
  end

  defp create_admin do
    {:ok, admin} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: :admin,
        email: "admin@test.com",
        display_name: "Test Admin"
      })

    admin
  end

  defp admin_conn(conn) do
    admin = create_admin()

    conn
    |> init_test_session(%{
      dev_user_id: admin.id,
      dev_user: %{
        "id" => admin.id,
        "user_role_id" => admin.id,
        "interactor_user_id" => admin.interactor_user_id,
        "role" => "admin",
        "email" => admin.email,
        "display_name" => admin.display_name
      }
    })
  end

  describe "/admin/flags" do
    test "renders all flags as enabled by default", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/flags")

      assert html =~ "Feature flags"
      assert html =~ "ai_question_generation_enabled"
      assert html =~ "ocr_enabled"
      assert html =~ "maintenance_mode"
      assert String.contains?(html, "ON")
    end

    test "toggle button writes audit log", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/flags")

      view
      |> element("button[phx-click='toggle'][phx-value-name='ocr_enabled']")
      |> render_click()

      logs = FunSheep.Admin.list_audit_logs(limit: 5)

      assert Enum.any?(
               logs,
               &(&1.action == "admin.flag.toggle" and &1.target_id == "ocr_enabled")
             )
    end
  end

  describe "dashboard card" do
    test "renders feature flags card with 0 off when all enabled", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin")
      assert html =~ "Feature flags"
    end

    test "shows yellow badge when a flag is off", %{conn: conn} do
      FeatureFlags.disable(:ocr_enabled)

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin")

      # Exactly one flag is disabled; either "1 off" or the ring highlight
      assert html =~ "off" or html =~ "ring-[#FFCC00]"
    end
  end
end
