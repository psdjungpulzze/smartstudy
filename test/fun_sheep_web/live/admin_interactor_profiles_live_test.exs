defmodule FunSheepWeb.AdminInteractorProfilesLiveTest do
  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts

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

  defp create_student(email \\ "student@example.com") do
    {:ok, student} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: :student,
        email: email,
        display_name: "Stu Dent"
      })

    student
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

  describe "/admin/interactor/profiles" do
    test "renders empty state", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      assert html =~ "Interactor profiles"
      assert html =~ "Search user"
      assert html =~ "Pick a user to view their Interactor profile."
    end

    test "search surfaces matching users", %{conn: conn} do
      _student = create_student("findable@example.com")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"search" => "findable"})

      assert html =~ "findable@example.com"
    end

    test "select_user loads the profile editor + effective preview", %{conn: conn} do
      student = create_student("pick@example.com")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"search" => "pick"})

      assert html =~ "pick@example.com"

      view
      |> element("li[phx-click='select_user'][phx-value-id='#{student.id}']")
      |> render_click()

      page = render(view)
      assert page =~ "User profile (raw)"
      assert page =~ "Effective profile (merged)"
      assert page =~ student.email
    end

    test "save_profile writes audit log", %{conn: conn} do
      student = create_student("save@example.com")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      view
      |> element("form[phx-change='search']")
      |> render_change(%{"search" => "save"})

      view
      |> element("li[phx-click='select_user'][phx-value-id='#{student.id}']")
      |> render_click()

      view
      |> form("form[phx-submit='save_profile']", %{
        "profile" => %{
          "grade" => "5",
          "hobbies" => "soccer, coding",
          "learning_preference" => "visual",
          "custom_instructions" => "Prefers shorter explanations."
        }
      })
      |> render_submit()

      logs = FunSheep.Admin.list_audit_logs(limit: 5)

      assert Enum.any?(
               logs,
               &(&1.action == "admin.profile.update" and &1.target_id == student.id)
             )
    end
  end
end
