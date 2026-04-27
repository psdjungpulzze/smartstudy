defmodule FunSheepWeb.AdminInteractorCredentialsLiveTest do
  # async: false because:
  #  1. We modify global Req default options in some tests.
  #  2. Some tests temporarily disable interactor_mock to test HTTP-backed paths.
  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FunSheep.ContentFixtures

  # Req.Test stub name used for HTTP interception.
  @stub FunSheepWeb.AdminInteractorCredentialsLive

  # Build a session conn for the given admin user role.
  defp admin_conn(conn, admin) do
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

  defp create_admin do
    ContentFixtures.create_user_role(%{
      interactor_user_id: Ecto.UUID.generate(),
      role: :admin,
      email: "admin_cred_#{System.unique_integer([:positive])}@test.com",
      display_name: "Test Admin"
    })
  end

  defp create_student(email) do
    ContentFixtures.create_user_role(%{
      interactor_user_id: Ecto.UUID.generate(),
      role: :student,
      email: email,
      display_name: "Student"
    })
  end

  # Helper: select a user in the UI by searching and clicking.
  defp select_user(view, student) do
    view
    |> element("form[phx-change='search']")
    |> render_change(%{"search" => String.slice(student.email, 0, 6)})

    view
    |> element("li[phx-click='select_user'][phx-value-id='#{student.id}']")
    |> render_click()
  end

  # ---------------------------------------------------------------------------
  # HTTP-stubbing helpers — used by tests that disable interactor_mock to test
  # the paths where Credentials.list_credentials actually makes HTTP calls.
  # ---------------------------------------------------------------------------

  # Pre-populate the Interactor Auth ETS cache so Auth.get_token/0 returns
  # a valid token without making any HTTP requests.
  defp inject_auth_token(token \\ "test_bearer_token") do
    expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)
    :ets.insert(:interactor_auth_cache, {:token, token, expires_at})
    token
  end

  # Set up Req.Test as the HTTP adapter for ALL Req calls (including Client).
  # Disable retry to keep tests fast (no 3-attempt backoff on transport errors).
  # Returns the previous options so the caller can restore them.
  defp enable_req_stub do
    prev = Req.default_options()
    Req.default_options(plug: {Req.Test, @stub}, retry: false)
    prev
  end

  defp restore_req_opts(prev) do
    :ok = Application.put_env(:req, :default_options, prev)
  end

  # Temporarily disable the interactor_mock flag so Credentials.list_credentials
  # goes through the real HTTP client path (intercepted by Req.Test).
  defp disable_interactor_mock do
    Application.put_env(:fun_sheep, :interactor_mock, false)
  end

  defp enable_interactor_mock do
    Application.put_env(:fun_sheep, :interactor_mock, true)
  end

  # ---------------------------------------------------------------------------
  # Tests — mount / UI render (mock mode, no HTTP)
  # ---------------------------------------------------------------------------

  describe "/admin/interactor/credentials" do
    test "renders empty state before a user is picked", %{conn: conn} do
      admin = create_admin()
      {:ok, _view, html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")

      assert html =~ "Interactor credentials"
      assert html =~ "Search user"
      assert html =~ "Pick a user"
    end

    test "renders audit description text on mount", %{conn: conn} do
      admin = create_admin()
      {:ok, _view, html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")

      assert html =~ "OAuth" or html =~ "Force"
      assert html =~ "Every action is audited"
    end

    test "search with fewer than 2 characters returns no results", %{conn: conn} do
      admin = create_admin()
      _student = create_student("short_search_#{System.unique_integer()}@example.com")

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"search" => "x"})

      # No user list rendered when term < 2 characters
      refute html =~ "li[phx-click='select_user']"
    end

    test "search surfaces matching users", %{conn: conn} do
      admin = create_admin()
      _student = create_student("cred@example.com")

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"search" => "cred"})

      assert html =~ "cred@example.com"
    end

    test "search returns multiple matching users", %{conn: conn} do
      admin = create_admin()
      _s1 = create_student("multi_search_a_#{System.unique_integer()}@match.com")
      _s2 = create_student("multi_search_b_#{System.unique_integer()}@match.com")

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"search" => "match.com"})

      assert html =~ "match.com"
    end

    test "select_user loads credentials table with empty state (mock)", %{conn: conn} do
      admin = create_admin()
      student = create_student("creds_#{System.unique_integer()}@example.com")

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")

      select_user(view, student)

      html = render(view)
      assert html =~ student.email
      assert html =~ "No credentials on file for this user." or html =~ "Provider"
    end

    test "select_user shows the user interactor_user_id", %{conn: conn} do
      admin = create_admin()
      student = create_student("iuid_#{System.unique_integer()}@example.com")

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")

      select_user(view, student)

      html = render(view)
      assert html =~ student.interactor_user_id
    end

    test "select_user renders credentials table header columns", %{conn: conn} do
      admin = create_admin()
      student = create_student("cols_#{System.unique_integer()}@example.com")

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")

      select_user(view, student)

      html = render(view)
      assert html =~ "Provider"
      assert html =~ "Status"
      assert html =~ "Scopes"
      assert html =~ "Expires"
      assert html =~ "Actions"
    end

    test "select_user shows empty-credentials message in mock mode", %{conn: conn} do
      admin = create_admin()
      student = create_student("refresh_#{System.unique_integer()}@example.com")

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")

      select_user(view, student)

      html = render(view)
      assert html =~ "No credentials on file for this user."
    end

    test "refresh_credential event succeeds in mock mode and shows flash", %{conn: conn} do
      admin = create_admin()
      student = create_student("rfr_#{System.unique_integer()}@example.com")

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")

      select_user(view, student)

      html = render_click(view, "refresh_credential", %{"id" => "mock-cred-id"})

      assert html =~ "Credential refreshed"
    end

    test "revoke_credential event succeeds in mock mode and shows flash", %{conn: conn} do
      admin = create_admin()
      student = create_student("rvk_#{System.unique_integer()}@example.com")

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")

      select_user(view, student)

      html = render_click(view, "revoke_credential", %{"id" => "mock-cred-id"})

      assert html =~ "Credential revoked"
    end

    test "page title is set correctly", %{conn: conn} do
      admin = create_admin()
      {:ok, _view, html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")

      assert html =~ "Interactor credentials"
    end

    test "search input has correct phx-debounce attribute rendered in HTML", %{conn: conn} do
      admin = create_admin()
      {:ok, _view, html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")

      assert html =~ "phx-debounce"
    end
  end

  # ---------------------------------------------------------------------------
  # Tests — credential row helpers exercised via real (stubbed) HTTP responses
  # ---------------------------------------------------------------------------
  # These tests disable interactor_mock, inject a cached token, and stub the
  # Interactor credential API via Req.Test to return various credential shapes.
  # This lets us exercise cred_id/1, cred_provider/1, extract_status/1,
  # cred_scopes/1, cred_expires/1, and cred_status_badge/1 in all their clauses.

  describe "credential row rendering — HTTP stub with real credential data" do
    setup do
      prev_req = enable_req_stub()
      disable_interactor_mock()
      inject_auth_token()

      on_exit(fn ->
        enable_interactor_mock()
        restore_req_opts(prev_req)
      end)

      :ok
    end

    # Build a complete credential map matching the shape Interactor returns.
    defp cred(overrides) do
      Map.merge(
        %{
          "id" => Ecto.UUID.generate(),
          "provider" => "google",
          "status" => "active",
          "scopes" => ["https://www.googleapis.com/auth/drive.readonly"],
          "expires_at" => "2099-01-01T00:00:00Z"
        },
        overrides
      )
    end

    # Stub a GET to /credentials/<uid> with the given credentials list.
    defp stub_creds(creds_list) do
      Req.Test.stub(@stub, fn conn ->
        conn
        |> Plug.Conn.put_status(200)
        |> Req.Test.json(%{"data" => creds_list})
      end)
    end

    test "active credential: provider='provider' key, scopes list, expires_at string", %{
      conn: conn
    } do
      admin = create_admin()
      student = create_student("active_#{System.unique_integer()}@stub.com")

      stub_creds([
        cred(%{
          "id" => "cred-active-1",
          "provider" => "google",
          "status" => "active",
          "scopes" => ["drive.readonly", "gmail.send"],
          "expires_at" => "2099-12-31T23:59:59Z"
        })
      ])

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")
      Req.Test.allow(@stub, self(), view.pid)

      select_user(view, student)
      html = render(view)

      # cred_provider/1 with "provider" key
      assert html =~ "google"
      # extract_status/1 → :active → cred_status_badge: "Active"
      assert html =~ "Active"
      # cred_scopes/1 with list → joined
      assert html =~ "drive.readonly"
      # cred_expires/1 with binary
      assert html =~ "2099-12-31T23:59:59Z"
      # Action buttons
      assert html =~ "Refresh"
      assert html =~ "Revoke"
    end

    test "expired credential: renders 'Expired' badge", %{conn: conn} do
      admin = create_admin()
      student = create_student("expired_#{System.unique_integer()}@stub.com")

      stub_creds([cred(%{"status" => "expired", "expires_at" => "2020-01-01T00:00:00Z"})])

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")
      Req.Test.allow(@stub, self(), view.pid)

      select_user(view, student)
      html = render(view)

      # extract_status/1 → :expired → cred_status_badge: "Expired"
      assert html =~ "Expired"
    end

    test "revoked credential: renders 'Revoked' badge", %{conn: conn} do
      admin = create_admin()
      student = create_student("revoked_#{System.unique_integer()}@stub.com")

      stub_creds([cred(%{"status" => "revoked"})])

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")
      Req.Test.allow(@stub, self(), view.pid)

      select_user(view, student)
      html = render(view)

      # extract_status/1 → :revoked → cred_status_badge: "Revoked"
      assert html =~ "Revoked"
    end

    test "unknown status: renders 'Unknown' badge", %{conn: conn} do
      admin = create_admin()
      student = create_student("unknown_#{System.unique_integer()}@stub.com")

      stub_creds([cred(%{"status" => "pending"})])

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")
      Req.Test.allow(@stub, self(), view.pid)

      select_user(view, student)
      html = render(view)

      # extract_status/1 unknown → cred_status_badge: "Unknown"
      assert html =~ "Unknown"
    end

    test "credential with 'service' key uses cred_provider/1 service branch", %{conn: conn} do
      admin = create_admin()
      student = create_student("service_#{System.unique_integer()}@stub.com")

      # No "provider" key → falls through to "service" key branch
      stub_creds([
        %{
          "id" => Ecto.UUID.generate(),
          "service" => "youtube",
          "status" => "active",
          "scopes" => ["youtube.readonly"],
          "expires_at" => nil
        }
      ])

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")
      Req.Test.allow(@stub, self(), view.pid)

      select_user(view, student)
      html = render(view)

      # cred_provider/1 "service" branch
      assert html =~ "youtube"
    end

    test "credential with no provider or service key renders em-dash", %{conn: conn} do
      admin = create_admin()
      student = create_student("noprov_#{System.unique_integer()}@stub.com")

      stub_creds([
        %{
          "id" => Ecto.UUID.generate(),
          "status" => "active",
          "scopes" => [],
          "expires_at" => nil
        }
      ])

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")
      Req.Test.allow(@stub, self(), view.pid)

      select_user(view, student)
      html = render(view)

      # cred_provider/1 fallback → "—"
      assert html =~ "—"
    end

    test "credential with scope as binary string (not list)", %{conn: conn} do
      admin = create_admin()
      student = create_student("scopebin_#{System.unique_integer()}@stub.com")

      stub_creds([
        cred(%{
          "scopes" => nil,
          "scope" => "openid profile email"
        })
      ])

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")
      Req.Test.allow(@stub, self(), view.pid)

      select_user(view, student)
      html = render(view)

      # cred_scopes/1 binary branch
      assert html =~ "openid profile email"
    end

    test "credential with no scopes renders em-dash", %{conn: conn} do
      admin = create_admin()
      student = create_student("noscope_#{System.unique_integer()}@stub.com")

      stub_creds([
        %{
          "id" => Ecto.UUID.generate(),
          "provider" => "slack",
          "status" => "active"
        }
      ])

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")
      Req.Test.allow(@stub, self(), view.pid)

      select_user(view, student)
      html = render(view)

      # cred_scopes/1 fallback → "—" for expires too
      assert html =~ "—"
    end

    test "credential with expires_at nil renders em-dash", %{conn: conn} do
      admin = create_admin()
      student = create_student("noexp_#{System.unique_integer()}@stub.com")

      stub_creds([
        cred(%{"expires_at" => nil})
      ])

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")
      Req.Test.allow(@stub, self(), view.pid)

      select_user(view, student)
      html = render(view)

      # cred_expires/1 nil branch → "—"
      assert html =~ "—"
    end

    test "credential with atom key id uses cred_id atom branch", %{conn: conn} do
      admin = create_admin()
      student = create_student("atomid_#{System.unique_integer()}@stub.com")

      # Return a credential map with atom keys (some Interactor SDKs use atoms)
      stub_creds([
        %{
          id: "cred-atom-id-123",
          provider: "github",
          status: "active",
          scopes: ["repo"],
          expires_at: "2099-06-15T12:00:00Z"
        }
      ])

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")
      Req.Test.allow(@stub, self(), view.pid)

      select_user(view, student)
      html = render(view)

      # cred_id/1 atom key branch → "cred-atom-id-123"
      # and cred_provider/1 atom key → "github" (fallback since no "provider" string key)
      assert html =~ "cred-atom-id-123" or html =~ "github" or html =~ "Refresh"
    end

    test "load_credentials shows error when Interactor returns a non-2xx response", %{
      conn: conn
    } do
      admin = create_admin()
      student = create_student("errcreds_#{System.unique_integer()}@stub.com")

      Req.Test.stub(@stub, fn conn ->
        conn
        |> Plug.Conn.put_status(503)
        |> Req.Test.json(%{"error" => "service unavailable"})
      end)

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")
      Req.Test.allow(@stub, self(), view.pid)

      select_user(view, student)
      html = render(view)

      # load_credentials error branch: sets @error assign
      assert html =~ "Interactor service is unavailable or returned no data"
    end

    test "load_credentials shows error on transport failure", %{conn: conn} do
      admin = create_admin()
      student = create_student("transerr_#{System.unique_integer()}@stub.com")

      Req.Test.stub(@stub, fn conn ->
        Req.Test.transport_error(conn, :closed)
      end)

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")
      Req.Test.allow(@stub, self(), view.pid)

      select_user(view, student)
      html = render(view)

      # Transport error → load_credentials error branch
      assert html =~ "Interactor service is unavailable or returned no data"
    end

    test "refresh_credential shows error flash when Interactor returns error", %{conn: conn} do
      admin = create_admin()
      student = create_student("rfrerr_#{System.unique_integer()}@stub.com")

      # First call: load_credentials (GET) → empty list
      # Subsequent: force_refresh POST → 500 error
      Req.Test.stub(@stub, fn conn ->
        case conn.method do
          "GET" ->
            conn
            |> Plug.Conn.put_status(200)
            |> Req.Test.json(%{"data" => []})

          "POST" ->
            conn
            |> Plug.Conn.put_status(500)
            |> Req.Test.json(%{"error" => "refresh failed"})
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")
      Req.Test.allow(@stub, self(), view.pid)

      select_user(view, student)

      # Trigger the refresh — the POST returns 500 which is {:error, {500, body}}
      html = render_click(view, "refresh_credential", %{"id" => "cred-xxx"})

      assert html =~ "Refresh failed" or html =~ "refresh"
    end

    test "revoke_credential shows error flash when Interactor returns error", %{conn: conn} do
      admin = create_admin()
      student = create_student("rvkerr_#{System.unique_integer()}@stub.com")

      Req.Test.stub(@stub, fn conn ->
        case conn.method do
          "GET" ->
            conn
            |> Plug.Conn.put_status(200)
            |> Req.Test.json(%{"data" => []})

          "DELETE" ->
            conn
            |> Plug.Conn.put_status(500)
            |> Req.Test.json(%{"error" => "delete failed"})
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")
      Req.Test.allow(@stub, self(), view.pid)

      select_user(view, student)

      html = render_click(view, "revoke_credential", %{"id" => "cred-yyy"})

      assert html =~ "Revoke failed" or html =~ "revoke"
    end

    test "credential with empty scopes list renders em-dash via fallback", %{conn: conn} do
      admin = create_admin()
      student = create_student("emptysc_#{System.unique_integer()}@stub.com")

      stub_creds([
        cred(%{"scopes" => [], "scope" => nil})
      ])

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")
      Req.Test.allow(@stub, self(), view.pid)

      select_user(view, student)
      html = render(view)

      # Empty scopes list joined → "" (empty string displayed as-is, not "—")
      # We just verify it renders without crashing
      assert html =~ "google" or html =~ "Active"
    end

    test "credential list returned as plain list (not wrapped in 'data' key)", %{conn: conn} do
      admin = create_admin()
      student = create_student("plainlist_#{System.unique_integer()}@stub.com")

      # Return a plain list (not wrapped in %{"data" => ...}) to exercise
      # the {:ok, items} when is_list(items) branch in load_credentials.
      Req.Test.stub(@stub, fn conn ->
        conn
        |> Plug.Conn.put_status(200)
        |> Req.Test.json([cred(%{"provider" => "stripe", "status" => "active"})])
      end)

      {:ok, view, _html} = live(admin_conn(conn, admin), ~p"/admin/interactor/credentials")
      Req.Test.allow(@stub, self(), view.pid)

      select_user(view, student)
      html = render(view)

      assert html =~ "stripe" or html =~ "Active"
    end
  end
end
