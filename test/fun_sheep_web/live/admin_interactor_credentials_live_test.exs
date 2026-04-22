defmodule FunSheepWeb.AdminInteractorCredentialsLiveTest do
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

  defp create_student(email) do
    {:ok, s} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: :student,
        email: email,
        display_name: "Student"
      })

    s
  end

  describe "/admin/interactor/credentials" do
    test "renders empty state before a user is picked", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/interactor/credentials")

      assert html =~ "Interactor credentials"
      assert html =~ "Search user"
      assert html =~ "Pick a user"
    end

    test "search surfaces matching users", %{conn: conn} do
      _student = create_student("cred@example.com")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/credentials")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"search" => "cred"})

      assert html =~ "cred@example.com"
    end

    test "select_user loads credentials table with empty state", %{conn: conn} do
      student = create_student("creds@example.com")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/credentials")

      view
      |> element("form[phx-change='search']")
      |> render_change(%{"search" => "creds"})

      view
      |> element("li[phx-click='select_user'][phx-value-id='#{student.id}']")
      |> render_click()

      html = render(view)
      assert html =~ student.email
      assert html =~ "No credentials on file for this user." or html =~ "Provider"
    end
  end
end
