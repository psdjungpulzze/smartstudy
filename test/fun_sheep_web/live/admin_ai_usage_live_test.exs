defmodule FunSheepWeb.AdminAIUsageLiveTest do
  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts
  alias FunSheep.AIUsage

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

  describe "/admin/usage/ai" do
    test "renders empty-state without crashing", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/usage/ai")

      assert html =~ "AI usage"
      assert html =~ "Total calls"
      assert html =~ "Total tokens"
      assert html =~ "Est. cost"
      assert html =~ "Error rate"
      # All summary cards present
      assert html =~ "Latency p50 / p95"
      # Group tables render with empty state copy
      assert html =~ "By assistant"
      assert html =~ "By source"
      assert html =~ "By model"
      assert html =~ "Recent errors"
      assert html =~ "Top 25 most expensive calls"
    end

    test "summary cards reflect logged calls", %{conn: conn} do
      {:ok, _} =
        AIUsage.log_call(%{
          provider: "openai",
          model: "gpt-4o",
          source: "test_worker",
          assistant_name: "validator",
          prompt_tokens: 1_000_000,
          completion_tokens: 500_000,
          duration_ms: 500,
          status: "ok"
        })

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/usage/ai")

      assert html =~ "1,500,000"
      # 1M input @ 250 cents/1M + 500k output @ 1000 cents/1M = 750 cents = $7.50
      assert html =~ "$7.50"
      assert html =~ "validator"
      assert html =~ "test_worker"
      assert html =~ "gpt-4o"
    end

    test "window pill click updates filter via URL patch", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/usage/ai")

      view
      |> element("button[phx-click='set_window'][phx-value-window='7d']")
      |> render_click()

      assert_patched(view, ~p"/admin/usage/ai?window=7d")
    end

    test "status filter toggles adds value to URL", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/usage/ai")

      view
      |> element(
        "button[phx-click='toggle_filter'][phx-value-group='status'][phx-value-v='error']"
      )
      |> render_click()

      assert_patched(view, ~p"/admin/usage/ai?status=error&window=24h")
    end

    test "clear_filter drops the value from URL", %{conn: conn} do
      {:ok, view, _html} =
        live(admin_conn(conn), ~p"/admin/usage/ai?window=24h&status=error")

      view
      |> element("button[phx-click='clear_filter'][phx-value-group='status']")
      |> render_click()

      assert_patched(view, ~p"/admin/usage/ai?window=24h")
    end

    test "URL params preload filters", %{conn: conn} do
      {:ok, _view, html} =
        live(admin_conn(conn), ~p"/admin/usage/ai?window=7d&status=ok&provider=openai")

      # Time window picker shows 7d as active
      assert html =~ "bg-[#4CD964] text-white border-[#4CD964]"
    end

    test "page view writes an audit log row", %{conn: conn} do
      assert {:ok, _view, _html} = live(admin_conn(conn), ~p"/admin/usage/ai")

      logs = FunSheep.Admin.list_audit_logs(limit: 5)
      assert Enum.any?(logs, &(&1.action == "admin.usage.ai.view"))
    end
  end

  describe "/admin dashboard card" do
    test "renders the AI usage card with $X.XX and call count", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin")

      assert html =~ "AI usage (24h)"
      # Currency formatting for zero-cost empty state
      assert html =~ "—" or html =~ "$0.00"
    end
  end
end
