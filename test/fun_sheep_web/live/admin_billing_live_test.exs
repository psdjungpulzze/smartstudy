defmodule FunSheepWeb.AdminBillingLiveTest do
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

  describe "/admin/billing" do
    test "renders the five summary cards + sections even with empty billing data",
         %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/billing")

      assert html =~ "Billing"
      assert html =~ "Active"
      assert html =~ "Trialing"
      assert html =~ "Past due"
      assert html =~ "Cancelled"
      assert html =~ "Plans"
      assert html =~ "Subscriptions"
      assert html =~ "Recent invoices"
    end

    test "refresh button re-pulls the data", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/billing")

      html =
        view
        |> element("button[phx-click='refresh']")
        |> render_click()

      assert html =~ "Last refreshed"
    end
  end
end
