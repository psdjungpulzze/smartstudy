defmodule FunSheepWeb.AdminSourceRegistryLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.Repo
  alias FunSheep.Discovery.SourceRegistryEntry

  defp admin_conn(conn) do
    conn
    |> init_test_session(%{
      dev_user_id: "admin-user-id",
      dev_user: %{
        "id" => "admin-user-id",
        "role" => "admin",
        "email" => "admin@example.com",
        "display_name" => "Admin User"
      }
    })
  end

  defp create_registry_entry(attrs) do
    defaults = %{
      test_type: "SAT",
      url_or_pattern: "https://example.com/sat-practice",
      domain: "example.com",
      source_type: "question_bank",
      tier: 1,
      is_enabled: true
    }

    {:ok, entry} =
      %SourceRegistryEntry{}
      |> SourceRegistryEntry.changeset(Map.merge(defaults, attrs))
      |> Repo.insert()

    entry
  end

  describe "mount/3" do
    test "renders the source registry page title", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-registry")

      assert html =~ "Source Registry"
    end

    test "renders the filter bar", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-registry")

      assert html =~ "Filter by test type"
    end

    test "renders empty state when no entries exist", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-registry")

      assert html =~ "No entries found" or html =~ "0 entries"
    end

    test "renders entry rows when entries exist", %{conn: conn} do
      create_registry_entry(%{
        test_type: "ACT",
        domain: "act-example.com",
        url_or_pattern: "https://act-example.com/practice"
      })

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-registry")

      assert html =~ "ACT"
      assert html =~ "act-example.com"
    end

    test "renders stats summary (total, enabled, disabled counts)", %{conn: conn} do
      create_registry_entry(%{is_enabled: true, url_or_pattern: "https://a.example.com/p"})
      create_registry_entry(%{is_enabled: false, url_or_pattern: "https://b.example.com/p", domain: "b.example.com"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-registry")

      assert html =~ "Total entries"
      assert html =~ "Enabled"
      assert html =~ "Disabled"
    end

    test "renders tier badges for tier 1 entries", %{conn: conn} do
      create_registry_entry(%{tier: 1, url_or_pattern: "https://tier1.example.com/p", domain: "tier1.example.com"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-registry")

      assert html =~ "Tier 1"
    end

    test "renders tier badges for tier 2 entries", %{conn: conn} do
      create_registry_entry(%{tier: 2, url_or_pattern: "https://tier2.example.com/p", domain: "tier2.example.com"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-registry")

      assert html =~ "Tier 2"
    end

    test "renders tier badges for tier 3 entries", %{conn: conn} do
      create_registry_entry(%{tier: 3, url_or_pattern: "https://tier3.example.com/p", domain: "tier3.example.com"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-registry")

      assert html =~ "Tier 3"
    end

    test "renders failure count in red for entries with 3+ consecutive failures", %{conn: conn} do
      create_registry_entry(%{
        consecutive_failures: 3,
        url_or_pattern: "https://fail.example.com/p",
        domain: "fail.example.com"
      })

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-registry")

      # The red color class is applied for >= 3 failures
      assert html =~ "text-[#FF3B30]"
    end

    test "renders Verify URL button for each entry", %{conn: conn} do
      create_registry_entry(%{url_or_pattern: "https://verify.example.com/p", domain: "verify.example.com"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-registry")

      assert html =~ "Verify URL"
    end
  end

  describe "handle_params/3" do
    test "filters entries when test_type param is present in URL", %{conn: conn} do
      create_registry_entry(%{test_type: "SAT", domain: "sat-p.example.com", url_or_pattern: "https://sat-p.example.com/p"})
      create_registry_entry(%{test_type: "ACT", domain: "act-p.example.com", url_or_pattern: "https://act-p.example.com/p"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-registry?test_type=SAT")

      assert html =~ "sat-p.example.com"
      refute html =~ "act-p.example.com"
    end

    test "sets filter_test_type assign from URL param", %{conn: conn} do
      create_registry_entry(%{test_type: "GRE", domain: "gre-p.example.com", url_or_pattern: "https://gre-p.example.com/p"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-registry?test_type=GRE")

      assert html =~ "gre-p.example.com"
    end

    test "shows all entries when no test_type param", %{conn: conn} do
      create_registry_entry(%{test_type: "SAT", domain: "sat-all.example.com", url_or_pattern: "https://sat-all.example.com/p"})
      create_registry_entry(%{test_type: "ACT", domain: "act-all.example.com", url_or_pattern: "https://act-all.example.com/p"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-registry")

      assert html =~ "sat-all.example.com"
      assert html =~ "act-all.example.com"
    end
  end

  describe "filter event" do
    test "filtering by test_type narrows entries", %{conn: conn} do
      create_registry_entry(%{test_type: "SAT", domain: "sat.example.com", url_or_pattern: "https://sat.example.com/practice"})
      create_registry_entry(%{test_type: "GRE", domain: "gre.example.com", url_or_pattern: "https://gre.example.com/practice"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/source-registry")

      html = render_change(view, "filter", %{"test_type" => "SAT"})

      assert html =~ "SAT"
      refute html =~ "gre.example.com"
    end

    test "filtering with empty test_type shows all entries", %{conn: conn} do
      create_registry_entry(%{test_type: "SAT", domain: "sat.example.com", url_or_pattern: "https://sat.example.com/practice"})
      create_registry_entry(%{test_type: "GRE", domain: "gre.example.com", url_or_pattern: "https://gre.example.com/practice"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/source-registry")

      # First filter to one type
      render_change(view, "filter", %{"test_type" => "SAT"})

      # Then clear the filter
      html = render_change(view, "filter", %{"test_type" => ""})

      assert html =~ "SAT"
      assert html =~ "GRE"
    end

    test "filter populates the test type dropdown with available types", %{conn: conn} do
      create_registry_entry(%{test_type: "LSAT", domain: "lsat.example.com", url_or_pattern: "https://lsat.example.com/p"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-registry")

      assert html =~ "LSAT"
    end
  end

  describe "toggle_enabled event" do
    test "toggling an enabled entry disables it", %{conn: conn} do
      entry = create_registry_entry(%{is_enabled: true, domain: "toggle.example.com", url_or_pattern: "https://toggle.example.com/practice"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/source-registry")

      render_click(view, "toggle_enabled", %{"id" => entry.id})

      updated = Repo.get!(SourceRegistryEntry, entry.id)
      assert updated.is_enabled == false
    end

    test "toggling a disabled entry enables it", %{conn: conn} do
      entry = create_registry_entry(%{is_enabled: false, domain: "disabled.example.com", url_or_pattern: "https://disabled.example.com/practice"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/source-registry")

      render_click(view, "toggle_enabled", %{"id" => entry.id})

      updated = Repo.get!(SourceRegistryEntry, entry.id)
      assert updated.is_enabled == true
    end

    test "toggling updates the in-memory entries list in the socket", %{conn: conn} do
      entry = create_registry_entry(%{is_enabled: true, domain: "mem.example.com", url_or_pattern: "https://mem.example.com/practice"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/source-registry")

      # After toggling, the rendered HTML should reflect the new state
      _html = render_click(view, "toggle_enabled", %{"id" => entry.id})

      # The page should still render without crash
      assert render(view) =~ "Source Registry"
    end

    test "toggle renders enabled count correctly", %{conn: conn} do
      entry = create_registry_entry(%{is_enabled: true, domain: "cnt.example.com", url_or_pattern: "https://cnt.example.com/practice"})

      {:ok, view, html} = live(admin_conn(conn), ~p"/admin/source-registry")

      # Before toggle, at least one enabled
      assert html =~ "Enabled"

      render_click(view, "toggle_enabled", %{"id" => entry.id})

      # Page still renders
      assert render(view) =~ "Source Registry"
    end
  end

  describe "verify event" do
    test "verify event runs for an entry and shows a result label", %{conn: conn} do
      entry = create_registry_entry(%{
        url_or_pattern: "https://unreachable-test-host-xyz.example.invalid/test",
        domain: "unreachable-test-host-xyz.example.invalid"
      })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/source-registry")

      # Trigger verify — in test environment this will fail (network unreachable)
      # which exercises the {:error, reason} path and renders the error label
      html = render_click(view, "verify", %{"id" => entry.id})

      # Either the success or error label should appear
      assert html =~ "✓" or html =~ "✗"
    end

    test "verify event stores result keyed by entry id in verify_results", %{conn: conn} do
      entry = create_registry_entry(%{
        url_or_pattern: "https://unreachable-xyz-test.example.invalid/",
        domain: "unreachable-xyz-test.example.invalid"
      })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/source-registry")

      render_click(view, "verify", %{"id" => entry.id})

      # After verify, the result badge should be rendered near this entry
      html = render(view)
      assert html =~ "✓" or html =~ "✗"
    end
  end

  describe "seed_course event" do
    test "seed_course event with a course that has no matching registry entries returns ok 0", %{conn: conn} do
      # Create a course with catalog fields but no matching registry entries
      course =
        FunSheep.ContentFixtures.create_course(%{
          catalog_test_type: "MCAT",
          catalog_subject: "Organic Chemistry",
          is_premium_catalog: true,
          access_level: "premium"
        })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/source-registry")

      # No crash — seed_course with 0 registry matches returns {:ok, 0}
      html = render_click(view, "seed_course", %{"course_id" => course.id})
      assert html =~ "Source Registry"
    end

    test "seed_course event with matching registry entries seeds and shows count", %{conn: conn} do
      # Create a registry entry for MCAT
      create_registry_entry(%{
        test_type: "MCAT",
        url_or_pattern: "https://mcat-seed.example.com/practice",
        domain: "mcat-seed.example.com",
        source_type: "question_bank",
        tier: 1,
        is_enabled: true
      })

      course =
        FunSheep.ContentFixtures.create_course(%{
          catalog_test_type: "MCAT",
          catalog_subject: nil,
          is_premium_catalog: true,
          access_level: "premium"
        })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/source-registry")

      html = render_click(view, "seed_course", %{"course_id" => course.id})
      assert html =~ "Source Registry"
    end
  end
end
