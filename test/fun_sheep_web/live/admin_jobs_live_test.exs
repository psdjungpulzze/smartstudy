defmodule FunSheepWeb.AdminJobsLiveTest do
  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts
  alias FunSheep.Repo

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

  defp insert_failed_job do
    %Oban.Job{
      state: "discarded",
      queue: "ai",
      worker: "FunSheep.Workers.CourseDiscoveryWorker",
      args: %{"course_id" => Ecto.UUID.generate()},
      errors: [%{"attempt" => 1, "error" => "Interactor unavailable"}],
      max_attempts: 3,
      attempt: 3,
      inserted_at: DateTime.utc_now(),
      attempted_at: DateTime.utc_now(),
      discarded_at: DateTime.utc_now()
    }
    |> Repo.insert!()
  end

  describe "/admin/jobs/failures" do
    test "renders empty state without crashing", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/jobs/failures")

      assert html =~ "Job failures"
      assert html =~ "Failed last 24h"
      assert html =~ "Top workers"
      assert html =~ "By category"
      assert html =~ "No failed jobs match these filters."
    end

    test "shows failed jobs with enriched context", %{conn: conn} do
      _job = insert_failed_job()

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/jobs/failures")

      assert html =~ "CourseDiscoveryWorker"
      assert html =~ "course:"
      assert html =~ "Interactor"
    end

    test "category filter narrows results", %{conn: conn} do
      _job = insert_failed_job()

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/jobs/failures")

      view
      |> form("form[phx-change='filter_category']", %{"category" => "interactor_unavailable"})
      |> render_change()

      # Still shows the job because it matches the category
      html = render(view)
      assert html =~ "CourseDiscoveryWorker"
    end
  end

  describe "dashboard card" do
    test "renders job failures card", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin")

      assert html =~ "Job failures"
      assert html =~ "FunSheep-domain drill-down"
    end

    test "shows red badge when failures > 0", %{conn: conn} do
      _job = insert_failed_job()

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin")

      # The count should appear in a red-styled badge
      assert html =~ "Job failures"
      assert html =~ "ring-[#FF3B30]" or html =~ "bg-[#FFE5E3]"
    end
  end
end
