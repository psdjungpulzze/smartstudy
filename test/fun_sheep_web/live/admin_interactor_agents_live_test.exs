defmodule FunSheepWeb.AdminInteractorAgentsLiveTest do
  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts

  defp admin_conn(conn) do
    {:ok, admin} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: :admin,
        email: "admin@test.com",
        display_name: "Test Admin"
      })

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

  describe "/admin/interactor/agents" do
    test "renders the registry table shell + column headers", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/interactor/agents")

      assert html =~ "Interactor agents"
      assert html =~ "Intended model"
      assert html =~ "Live model"
      # Table body rendered with at least the "Force re-provision" button
      assert html =~ "Force re-provision"
    end

    test "force reprovision flashes success + writes audit", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/agents")

      # Use the first reprovision button that exists in the rendered page.
      html = render(view)

      mod_match = Regex.run(~r/phx-value-module="([^"]+)"/, html)

      assert mod_match,
             "expected at least one reprovision button, got: #{String.slice(html, 0, 200)}"

      [_, mod] = mod_match

      view
      |> element("button[phx-click='reprovision'][phx-value-module='#{mod}']")
      |> render_click()

      assert render(view) =~ "re-provisioned"

      logs = FunSheep.Admin.list_audit_logs(limit: 5)
      assert Enum.any?(logs, &(&1.action == "admin.agent.reprovision"))
    end

    test "refresh reloads the page", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/agents")

      html = view |> element("button[phx-click='refresh']") |> render_click()
      assert html =~ "Interactor agents"
    end
  end
end
