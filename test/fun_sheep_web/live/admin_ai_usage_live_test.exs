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

  describe "drawer + top calls + errors" do
    test "clicking a top-calls row opens the drawer", %{conn: conn} do
      {:ok, call} =
        AIUsage.log_call(%{
          provider: "openai",
          model: "gpt-4o",
          source: "test_worker",
          assistant_name: "validator",
          prompt_tokens: 100,
          completion_tokens: 50,
          duration_ms: 200,
          status: "ok"
        })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/usage/ai")

      view
      |> element("tr[phx-click='open_drawer'][phx-value-id='#{call.id}']")
      |> render_click()

      html = render(view)
      assert html =~ "Call detail"
      assert html =~ "Inserted at"
      assert html =~ "Metadata"
    end

    test "close_drawer hides the panel", %{conn: conn} do
      {:ok, call} =
        AIUsage.log_call(%{
          provider: "openai",
          model: "gpt-4o",
          source: "w",
          prompt_tokens: 10,
          completion_tokens: 5,
          status: "ok"
        })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/usage/ai")

      view
      |> element("tr[phx-click='open_drawer'][phx-value-id='#{call.id}']")
      |> render_click()

      view |> element("button[phx-click='close_drawer']") |> render_click()

      refute render(view) =~ "Call detail"
    end

    test "recent errors section lists error calls", %{conn: conn} do
      {:ok, _} =
        AIUsage.log_call(%{
          provider: "openai",
          model: "gpt-4o-mini",
          source: "w",
          prompt_tokens: 5,
          completion_tokens: 0,
          status: "error",
          error: "assistant_not_found: foobar"
        })

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/usage/ai")
      assert html =~ "assistant_not_found"
    end
  end

  describe "custom window" do
    test "set_custom_window routes to ?window=custom", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/usage/ai")

      view
      |> form("form[phx-submit='set_custom_window']", %{
        "since" => "2026-04-20T00:00",
        "until" => "2026-04-22T12:00"
      })
      |> render_submit()

      assert_patched(
        view,
        ~p"/admin/usage/ai?since=2026-04-20T00%3A00&until=2026-04-22T12%3A00&window=custom"
      )
    end

    test "custom window params preload into the page", %{conn: conn} do
      {:ok, _view, html} =
        live(
          admin_conn(conn),
          ~p"/admin/usage/ai?window=custom&since=2026-04-20T00:00&until=2026-04-22T12:00"
        )

      assert html =~ "AI usage"
      # The custom button is active
      assert html =~ "Custom"
    end
  end

  describe "provider filter" do
    test "toggling provider updates URL param", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/usage/ai")

      view
      |> element(
        "button[phx-click='toggle_filter'][phx-value-group='provider'][phx-value-v='openai']"
      )
      |> render_click()

      assert_patched(view, ~p"/admin/usage/ai?provider=openai&window=24h")
    end
  end
end
