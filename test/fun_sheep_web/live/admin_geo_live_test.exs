defmodule FunSheepWeb.AdminGeoLiveTest do
  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts
  alias FunSheep.Geo

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

  describe "/admin/geo" do
    test "renders empty-state counts when no geo data exists", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/geo")

      assert html =~ "Geo"
      assert html =~ "Countries"
      assert html =~ "Schools"
      assert html =~ "No schools match."
    end

    test "search narrows schools", %{conn: conn} do
      {:ok, country} = Geo.create_country(%{name: "Testland", code: "TT"})

      {:ok, _school} =
        Geo.create_school(%{
          name: "Searchable High",
          source: "test",
          source_id: "s1",
          country_id: country.id,
          type: "public",
          level: "secondary",
          student_count: 1000
        })

      {:ok, _school2} =
        Geo.create_school(%{
          name: "Other Academy",
          source: "test",
          source_id: "s2",
          country_id: country.id,
          type: "public",
          level: "secondary",
          student_count: 500
        })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/geo")

      html =
        view
        |> form("form[phx-change='search']")
        |> render_change(%{"query" => "Searchable", "country_id" => ""})

      assert html =~ "Searchable High"
      refute html =~ "Other Academy"
    end
  end
end
