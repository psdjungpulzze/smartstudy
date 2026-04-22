defmodule FunSheepWeb.AdminUserDetailLiveTest do
  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts

  defp create_user(attrs \\ %{}) do
    {:ok, user} =
      Accounts.create_user_role(
        Map.merge(
          %{
            interactor_user_id: Ecto.UUID.generate(),
            role: :student,
            email: "student-#{System.unique_integer([:positive])}@x.com",
            display_name: "Student X"
          },
          attrs
        )
      )

    user
  end

  defp admin_conn(conn) do
    admin =
      create_user(%{
        role: :admin,
        email: "admin-#{System.unique_integer([:positive])}@x.com",
        display_name: "Admin"
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

  describe "/admin/users/:id" do
    test "renders header, sections, and empty-state placeholders", %{conn: conn} do
      target = create_user()

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/users/#{target.id}")

      assert html =~ target.email
      assert html =~ "Activity timeline"
      assert html =~ "Audit trail"
      assert html =~ "Courses owned"
      assert html =~ "AI usage"
      assert html =~ "Subscription"
      assert html =~ "Interactor profile"
      assert html =~ "Credentials"
      assert html =~ "Active"
    end

    test "redirects to /admin/users when user not found", %{conn: conn} do
      missing_id = Ecto.UUID.generate()

      assert {:error, {:live_redirect, %{to: "/admin/users"}}} =
               live(admin_conn(conn), ~p"/admin/users/#{missing_id}")
    end

    test "records admin.user.view audit log on mount", %{conn: conn} do
      target = create_user(%{email: "target@example.com"})

      {:ok, _view, _html} = live(admin_conn(conn), ~p"/admin/users/#{target.id}")

      logs = FunSheep.Admin.list_audit_logs(limit: 5)

      assert Enum.any?(logs, fn l ->
               l.action == "admin.user.view" and l.target_id == target.id
             end)
    end

    test "suspend button triggers the admin action and flashes", %{conn: conn} do
      target = create_user()
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/users/#{target.id}")

      html =
        view
        |> element("button[phx-click='suspend']")
        |> render_click()

      assert html =~ "User suspended."

      # DB state updated
      refreshed = FunSheep.Accounts.get_user_role!(target.id)
      assert refreshed.suspended_at != nil
    end
  end

  describe "/admin/users row navigation" do
    test "email cell links to the detail page", %{conn: conn} do
      target = create_user(%{email: "clickme@example.com"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/users")

      assert html =~ "clickme@example.com"
      assert html =~ "/admin/users/#{target.id}"
    end
  end

  describe "promote/demote" do
    test "promote flashes info on a non-admin target", %{conn: conn} do
      target = create_user(%{role: :student})
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/users/#{target.id}")

      html =
        view
        |> element("button[phx-click='promote']")
        |> render_click()

      assert html =~ "Promoted to admin"
    end

    test "demote navigates back to /admin/users after removing admin role", %{conn: conn} do
      target =
        create_user(%{
          role: :admin,
          email: "admin-target-#{System.unique_integer([:positive])}@x.com"
        })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/users/#{target.id}")

      view
      |> element("button[phx-click='demote']")
      |> render_click()

      assert_redirected(view, ~p"/admin/users")
    end
  end

  describe "activity timeline rendering" do
    test "shows a course-created event when the user owns courses", %{conn: conn} do
      target = create_user()

      {:ok, _} =
        FunSheep.Courses.create_course(%{
          name: "Physics 101",
          subject: "Physics",
          grade: "11",
          created_by_id: target.id
        })

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/users/#{target.id}")

      assert html =~ "Physics 101"
      assert html =~ "Physics"
    end
  end
end
