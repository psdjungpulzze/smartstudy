defmodule FunSheepWeb.AdminAuditLogLiveTest do
  @moduledoc """
  Tests for AdminAuditLogLive — the read-only admin audit log feed.
  Covers mount, pagination (prev_page / next_page), and row rendering.
  """

  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts
  alias FunSheep.Admin

  defp create_admin do
    {:ok, admin} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: :admin,
        email: "auditadmin#{System.unique_integer([:positive])}@test.com",
        display_name: "Audit Admin"
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

  defp insert_audit_log(attrs \\ %{}) do
    defaults = %{
      actor_label: "admin:test@example.com",
      action: "user.suspend",
      target_type: "UserRole",
      target_id: Ecto.UUID.generate(),
      metadata: %{"reason" => "spam"}
    }

    {:ok, log} = Admin.record(Map.merge(defaults, attrs))
    log
  end

  describe "mount" do
    test "renders audit log page title and total count", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/audit-log")

      assert html =~ "Audit log"
      assert html =~ "entries"
    end

    test "renders empty state when no entries exist", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/audit-log")

      assert html =~ "No entries yet."
    end

    test "renders table rows when audit logs exist", %{conn: conn} do
      insert_audit_log(%{action: "user.suspend", actor_label: "admin:test@example.com"})
      insert_audit_log(%{action: "course.delete", actor_label: "admin:other@example.com"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/audit-log")

      assert html =~ "user.suspend"
      assert html =~ "course.delete"
      assert html =~ "admin:test@example.com"
      assert html =~ "admin:other@example.com"
    end

    test "renders target_type and target_id when present", %{conn: conn} do
      target_id = Ecto.UUID.generate()

      insert_audit_log(%{
        action: "user.suspend",
        target_type: "UserRole",
        target_id: target_id
      })

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/audit-log")

      assert html =~ "UserRole"
      assert html =~ target_id
    end

    test "renders metadata as JSON when metadata is non-empty", %{conn: conn} do
      insert_audit_log(%{
        action: "user.ban",
        metadata: %{"reason" => "violation"}
      })

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/audit-log")

      assert html =~ "violation"
    end

    test "renders em-dash placeholder when target_id is nil", %{conn: conn} do
      insert_audit_log(%{action: "platform.reset", target_id: nil, target_type: nil})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/audit-log")

      assert html =~ "—"
    end

    test "shows page 1 of 1 on initial load", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/audit-log")

      assert html =~ "Page 1 of 1"
    end
  end

  describe "pagination — prev_page event" do
    test "prev_page on page 0 stays on page 0 (no negative pages)", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/audit-log")

      html = render_click(view, "prev_page")

      # Still on page 1 (0-indexed page 0)
      assert html =~ "Page 1"
    end
  end

  describe "pagination — next_page event" do
    test "next_page does nothing when already on last page", %{conn: conn} do
      # With fewer than 50 entries, total < page_size, so next_page is a no-op
      insert_audit_log(%{action: "test.action"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/audit-log")

      html = render_click(view, "next_page")

      # Still shows page 1
      assert html =~ "Page 1"
    end
  end

  describe "access control" do
    test "non-admin user hitting /admin/audit-log sees a 404", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{
          dev_user_id: "student-id",
          dev_user: %{
            "id" => "student-id",
            "user_role_id" => "student-id",
            "role" => "student",
            "email" => "student@test.com",
            "display_name" => "Student"
          }
        })

      assert_raise FunSheepWeb.NotFoundError, fn ->
        live(conn, ~p"/admin/audit-log")
      end
    end
  end
end
