defmodule FunSheepWeb.AdminPagesTest do
  use FunSheepWeb.ConnCase, async: true

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

  describe "/admin (dashboard)" do
    test "renders real metric cards", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin")

      assert html =~ "Admin"
      assert html =~ "Total users"
      assert html =~ "Courses"
      assert html =~ "Question review"
      assert html =~ "Recent admin activity"
    end
  end

  describe "/admin/users" do
    test "renders user table with filter pills", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/users")

      assert html =~ "Users"
      assert html =~ "Search by email"
      assert html =~ "Student"
      assert html =~ "Teacher"
      assert html =~ "Admin"
    end

    test "shows Free lessons button for free-plan students and saves bonus", %{conn: conn} do
      {:ok, student} =
        Accounts.create_user_role(%{
          interactor_user_id: Ecto.UUID.generate(),
          role: :student,
          email: "free_student@test.com",
          display_name: "Free Student"
        })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/users")

      assert has_element?(
               view,
               "button[phx-click='open_subscription'][phx-value-id='#{student.id}']"
             )

      view
      |> element("button[phx-click='open_subscription'][phx-value-id='#{student.id}']")
      |> render_click()

      assert has_element?(view, "form[phx-submit='save_subscription']")
      assert render(view) =~ "free_student@test.com"
      assert render(view) =~ "50 base + 0 bonus"

      view
      |> form("form[phx-submit='save_subscription']", bonus: "30")
      |> render_submit()

      assert FunSheep.Billing.lifetime_usage(student.id).limit == 80
      assert render(view) =~ "Subscription updated for free_student@test.com"
    end

    test "Free lessons button is hidden for non-students", %{conn: conn} do
      {:ok, parent} =
        Accounts.create_user_role(%{
          interactor_user_id: Ecto.UUID.generate(),
          role: :parent,
          email: "p@test.com",
          display_name: "Parent"
        })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/users")

      refute has_element?(
               view,
               "button[phx-click='open_subscription'][phx-value-id='#{parent.id}']"
             )
    end

    test "Subscription button shows for paid-plan students (bonus field hidden within modal)", %{
      conn: conn
    } do
      {:ok, student} =
        Accounts.create_user_role(%{
          interactor_user_id: Ecto.UUID.generate(),
          role: :student,
          email: "paid@test.com",
          display_name: "Paid Student"
        })

      {:ok, sub} = FunSheep.Billing.get_or_create_subscription(student.id)
      {:ok, _} = FunSheep.Billing.update_subscription(sub, %{plan: "monthly"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/users")

      # The Subscription button shows for all students; the bonus field is hidden inside the modal for paid plans.
      assert has_element?(
               view,
               "button[phx-click='open_subscription'][phx-value-id='#{student.id}']"
             )
    end

    test "rejects non-integer bonus input", %{conn: conn} do
      {:ok, student} =
        Accounts.create_user_role(%{
          interactor_user_id: Ecto.UUID.generate(),
          role: :student,
          email: "validate@test.com",
          display_name: "Validate"
        })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/users")

      view
      |> element("button[phx-click='open_subscription'][phx-value-id='#{student.id}']")
      |> render_click()

      view
      |> form("form[phx-submit='save_subscription']", bonus: "abc")
      |> render_submit()

      assert render(view) =~ "Bonus must be a non-negative whole number."
      assert FunSheep.Billing.lifetime_usage(student.id).limit == 50
    end
  end

  describe "/admin/courses" do
    test "renders course table", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses")

      assert html =~ "Courses"
      assert html =~ "Search by name or subject"
    end
  end

  describe "/admin/audit-log" do
    test "renders audit log with empty-state message", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/audit-log")

      assert html =~ "Audit log"
      assert html =~ "No entries yet."
    end
  end

  describe "/admin/materials" do
    test "renders materials table", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/materials")

      assert html =~ "Materials"
      assert html =~ "Search by filename"
      assert html =~ "Pending"
      assert html =~ "Completed"
    end
  end

  describe "/admin/settings/mfa" do
    test "renders the MFA settings page", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/settings/mfa")

      assert html =~ "Two-factor authentication"
    end
  end

  describe "access control" do
    test "non-admin user hitting /admin sees a 404 response (no leak)", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{
          dev_user_id: "some-student",
          dev_user: %{
            "id" => "some-student",
            "user_role_id" => "some-student",
            "role" => "student",
            "email" => "student@test.com",
            "display_name" => "Student"
          }
        })

      # The :require_admin on_mount hook raises NotFoundError for non-admins.
      # Phoenix LiveViewTest surfaces this as an exception from `live/2`.
      assert_raise FunSheepWeb.NotFoundError, fn ->
        live(conn, ~p"/admin")
      end
    end
  end
end
