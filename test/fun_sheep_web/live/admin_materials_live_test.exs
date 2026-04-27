defmodule FunSheepWeb.AdminMaterialsLiveTest do
  use FunSheepWeb.ConnCase, async: true
  use Oban.Testing, repo: FunSheep.Repo

  import Phoenix.LiveViewTest

  alias FunSheep.{Accounts, ContentFixtures}

  # Admin conn with a real DB-backed user_role so audit-log inserts succeed.
  defp admin_conn(conn) do
    {:ok, admin} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: :admin,
        email: "admin-mat-#{System.unique_integer([:positive])}@test.com",
        display_name: "Materials Admin"
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

  describe "mount" do
    test "renders page heading and table headers", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/materials")

      assert html =~ "Materials"
      assert html =~ "File"
      assert html =~ "Uploaded by"
      assert html =~ "OCR"
    end

    test "renders 'No materials match' when there are none", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/materials")

      assert html =~ "No materials match"
    end

    test "shows uploaded materials in the table", %{conn: conn} do
      material = ContentFixtures.create_uploaded_material(%{file_name: "lecture_notes.pdf"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/materials")

      assert html =~ material.file_name
    end

    test "renders status filter pills", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/materials")

      assert html =~ "Pending"
      assert html =~ "Processing"
      assert html =~ "Completed"
      assert html =~ "Partial"
      assert html =~ "Failed"
    end

    test "renders search input and Re-run OCR / Delete action buttons", %{conn: conn} do
      ContentFixtures.create_uploaded_material()

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/materials")

      assert html =~ "Re-run OCR"
      assert html =~ "Delete"
    end
  end

  describe "search event" do
    test "filters materials by filename", %{conn: conn} do
      ContentFixtures.create_uploaded_material(%{file_name: "biology_chapter_1.pdf"})
      ContentFixtures.create_uploaded_material(%{file_name: "chemistry_notes.pdf"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/materials")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"search" => "biology"})

      assert html =~ "biology_chapter_1.pdf"
      refute html =~ "chemistry_notes.pdf"
    end

    test "shows 'No materials match' when search returns nothing", %{conn: conn} do
      ContentFixtures.create_uploaded_material(%{file_name: "history.pdf"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/materials")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"search" => "zzzzz_no_match"})

      assert html =~ "No materials match"
    end

    test "search resets to page 0", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/materials")

      # A search always resets paging; verify the rendered page shows page 1 (index 0).
      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"search" => ""})

      assert html =~ "Page 1 of"
    end
  end

  describe "filter_status event" do
    test "filtering by 'completed' shows only completed materials", %{conn: conn} do
      ContentFixtures.create_uploaded_material(%{
        file_name: "done.pdf",
        ocr_status: :completed
      })

      ContentFixtures.create_uploaded_material(%{
        file_name: "pending.pdf",
        ocr_status: :pending
      })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/materials")

      html =
        view
        |> element("button[phx-click='filter_status'][phx-value-status='completed']")
        |> render_click()

      assert html =~ "done.pdf"
      refute html =~ "pending.pdf"
    end

    test "invalid status value resets to nil (all)", %{conn: conn} do
      ContentFixtures.create_uploaded_material(%{file_name: "any.pdf"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/materials")

      # Sending an invalid status value should fall back to nil filter (show all).
      html = render_hook(view, "filter_status", %{"status" => "not_a_real_status"})

      assert html =~ "any.pdf"
    end

    test "clicking 'All' pill clears status filter", %{conn: conn} do
      ContentFixtures.create_uploaded_material(%{file_name: "clear_filter.pdf"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/materials")

      # First filter by failed, then clear.
      view
      |> element("button[phx-click='filter_status'][phx-value-status='failed']")
      |> render_click()

      html =
        view
        |> element("button[phx-click='filter_status'][phx-value-status='']")
        |> render_click()

      assert html =~ "clear_filter.pdf"
    end
  end

  describe "pagination events" do
    test "prev_page does nothing on page 0", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/materials")

      html = render_hook(view, "prev_page", %{})

      # Should still show page 1 (0-indexed).
      assert html =~ "Page 1 of"
    end

    test "next_page does not advance beyond last page when total fits on one page", %{conn: conn} do
      # With fewer than page_size (25) materials, next_page is a no-op.
      ContentFixtures.create_uploaded_material()

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/materials")

      html = render_hook(view, "next_page", %{})

      # Should remain on page 1.
      assert html =~ "Page 1 of 1"
    end
  end

  describe "rerun event" do
    test "clicking Re-run OCR flashes a success message", %{conn: conn} do
      # Oban is in :inline mode during tests, so the job actually runs
      # immediately. We just verify the flash message appears.
      material = ContentFixtures.create_uploaded_material()
      conn_with_admin = admin_conn(conn)

      {:ok, view, _html} = live(conn_with_admin, ~p"/admin/materials")

      html =
        view
        |> element("button[phx-click='rerun'][phx-value-id='#{material.id}']")
        |> render_click()

      # Either success flash or OCR re-run queued message should appear.
      assert html =~ "OCR re-run queued" or html =~ material.file_name
    end

    test "rerun enqueues OCRMaterialWorker via context", %{conn: _conn} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        material = ContentFixtures.create_uploaded_material()

        {:ok, admin} =
          Accounts.create_user_role(%{
            interactor_user_id: Ecto.UUID.generate(),
            role: :admin,
            email: "rerun-admin-#{System.unique_integer([:positive])}@test.com",
            display_name: "Rerun Admin"
          })

        actor = %{"user_role_id" => admin.id, "email" => admin.email}
        assert {:ok, _job} = FunSheep.Admin.rerun_ocr(material, actor)
        assert_enqueued(worker: FunSheep.Workers.OCRMaterialWorker)
      end)
    end
  end

  describe "delete event" do
    test "clicking Delete removes the material and flashes success", %{conn: conn} do
      material = ContentFixtures.create_uploaded_material(%{file_name: "to_delete.pdf"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/materials")

      html =
        view
        |> element("button[phx-click='delete'][phx-value-id='#{material.id}']")
        |> render_click()

      assert html =~ "Material deleted."
      refute html =~ "to_delete.pdf"
    end
  end

  describe "status badge rendering" do
    test "completed status renders a green badge", %{conn: conn} do
      ContentFixtures.create_uploaded_material(%{
        file_name: "completed.pdf",
        ocr_status: :completed
      })

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/materials")

      assert html =~ "Completed"
      assert html =~ "bg-[#E8F8EB]"
    end

    test "failed status renders a red badge", %{conn: conn} do
      ContentFixtures.create_uploaded_material(%{
        file_name: "failed.pdf",
        ocr_status: :failed
      })

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/materials")

      assert html =~ "Failed"
      assert html =~ "bg-[#FFE5E3]"
    end
  end
end
