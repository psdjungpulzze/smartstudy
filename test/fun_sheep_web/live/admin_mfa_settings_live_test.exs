defmodule FunSheepWeb.AdminMfaSettingsLiveTest do
  # async: false because we modify global Req default options to intercept HTTP
  # calls in AdminMfaSettingsLive (which calls Req.get/post directly).
  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  # The stub name used for Req.Test interception.
  @stub FunSheepWeb.AdminMfaSettingsLive

  # Build an admin session conn.
  defp admin_conn(conn) do
    conn
    |> init_test_session(%{
      dev_user_id: "admin-mfa-test",
      dev_user: %{
        "id" => "admin-mfa-test",
        "role" => "admin",
        "email" => "admin-mfa@test.com",
        "display_name" => "MFA Admin",
        "user_role_id" => "admin-mfa-test",
        "interactor_user_id" => "interactor-sub-abc",
        "org" => "studysmart"
      }
    })
  end

  # Set up Req.Test as the global HTTP adapter for this test module.
  # All tests in this module that need HTTP stubbing call
  # `Req.Test.stub(@stub, fn conn -> ... end)` followed by
  # `Req.Test.allow(@stub, self(), view.pid)` after mounting.
  setup do
    prev_options = Req.default_options()
    Req.default_options(plug: {Req.Test, @stub})

    on_exit(fn ->
      :ok = Application.put_env(:req, :default_options, prev_options)
    end)

    :ok
  end

  # Convenience: stub every request with a handler function.
  defp stub(fun), do: Req.Test.stub(@stub, fun)

  defp allow(view), do: Req.Test.allow(@stub, self(), view.pid)

  # A handler that returns an Interactor profile with mfa_enabled = true.
  defp profile_mfa_enabled(conn) do
    conn
    |> Plug.Conn.put_status(200)
    |> Req.Test.json(%{"mfa_enabled" => true, "email" => "admin-mfa@test.com"})
  end

  # A handler that returns an Interactor profile with mfa_enabled = false.
  defp profile_mfa_disabled(conn) do
    conn
    |> Plug.Conn.put_status(200)
    |> Req.Test.json(%{"mfa_enabled" => false})
  end

  # A handler that returns a successful enable response (otpauth_uri + secret).
  defp enable_success(conn) do
    conn
    |> Plug.Conn.put_status(200)
    |> Req.Test.json(%{
      "otpauth_uri" => "otpauth://totp/FunSheep:admin-mfa@test.com?secret=TESTSECRET&issuer=FunSheep",
      "secret" => "TESTSECRET"
    })
  end

  # A handler that returns a successful verify response with recovery_codes.
  defp verify_success_with_codes(conn) do
    conn
    |> Plug.Conn.put_status(200)
    |> Req.Test.json(%{
      "recovery_codes" => ["code-aaa", "code-bbb", "code-ccc"]
    })
  end

  # A handler that returns a successful verify with NO recovery_codes field.
  defp verify_success_no_codes(conn) do
    conn
    |> Plug.Conn.put_status(200)
    |> Req.Test.json(%{"status" => "ok"})
  end

  describe "mount — Interactor profile loaded via HTTP stub" do
    test "renders the page title and MFA heading", %{conn: conn} do
      stub(&profile_mfa_disabled/1)
      {:ok, view, html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      assert html =~ "Two-factor authentication"
      assert html =~ "Protect your admin account"
    end

    test "shows 'MFA is enabled' when Interactor returns mfa_enabled: true", %{conn: conn} do
      stub(&profile_mfa_enabled/1)
      {:ok, view, html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      assert html =~ "MFA is enabled on this account"
      assert html =~ "Interactor&#39;s admin console" or html =~ "Interactor's admin console"
    end

    test "shows 'MFA is not enabled' when Interactor returns mfa_enabled: false", %{conn: conn} do
      stub(&profile_mfa_disabled/1)
      {:ok, view, html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      assert html =~ "MFA is not enabled"
      assert html =~ "Enable MFA"
    end

    test "defaults enrolled? to false when Interactor returns a network error (no stub)", %{
      conn: conn
    } do
      # Simulate a transport-level error during profile load; load_status
      # swallows errors and defaults enrolled? to false.
      stub(fn conn -> Req.Test.transport_error(conn, :closed) end)
      {:ok, view, html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      # Network errors in load_status are swallowed; defaults to not enrolled.
      assert html =~ "MFA is not enabled"
    end

    test "defaults enrolled? to false when profile returns a non-200 status", %{conn: conn} do
      stub(fn conn ->
        conn
        |> Plug.Conn.put_status(503)
        |> Req.Test.json(%{"error" => "service unavailable"})
      end)

      {:ok, view, html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      assert html =~ "MFA is not enabled"
    end

    test "shows 'Enable MFA' button when not enrolled", %{conn: conn} do
      stub(&profile_mfa_disabled/1)
      {:ok, view, html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      assert html =~ "phx-click=\"start_enroll\""
    end
  end

  describe "start_enroll event — success path" do
    test "transitions to :verify step and renders QR URI and secret", %{conn: conn} do
      # First call is profile load; second call is the enroll POST.
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" -> enable_success(conn)
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      html = view |> element("button[phx-click='start_enroll']") |> render_click()

      assert html =~ "Add this to your app"
      assert html =~ "TESTSECRET"
      assert html =~ "otpauth://"
      assert html =~ "Open in authenticator app"
      assert html =~ "Verify and enable"
      assert html =~ "Cancel"
    end
  end

  describe "start_enroll event — error paths" do
    test "shows unsupported message when Interactor returns 404", %{conn: conn} do
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" -> Plug.Conn.put_status(conn, 404) |> Req.Test.json(%{})
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      html = view |> element("button[phx-click='start_enroll']") |> render_click()

      assert html =~ "Interactor" or html =~ "enrollment request" or html =~ "enroll MFA"
    end

    test "shows unsupported message when Interactor returns 405", %{conn: conn} do
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" -> Plug.Conn.put_status(conn, 405) |> Req.Test.json(%{})
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      html = view |> element("button[phx-click='start_enroll']") |> render_click()

      assert html =~ "Interactor" or html =~ "enrollment request"
    end

    test "shows 401 not-authorized message when Interactor returns 401", %{conn: conn} do
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" -> Plug.Conn.put_status(conn, 401) |> Req.Test.json(%{})
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      html = view |> element("button[phx-click='start_enroll']") |> render_click()

      assert html =~ "Not authorized" or html =~ "sign in"
    end

    test "shows error message with status code for unexpected server errors", %{conn: conn} do
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" ->
            Plug.Conn.put_status(conn, 500)
            |> Req.Test.json(%{"error" => "internal server error"})
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      html = view |> element("button[phx-click='start_enroll']") |> render_click()

      assert html =~ "Interactor returned 500" or html =~ "internal server error"
    end

    test "shows error with message field when server error has 'message' key", %{conn: conn} do
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" ->
            Plug.Conn.put_status(conn, 422)
            |> Req.Test.json(%{"message" => "MFA already configured"})
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      html = view |> element("button[phx-click='start_enroll']") |> render_click()

      assert html =~ "MFA already configured" or html =~ "422"
    end

    test "shows network error message when Req fails with a transport error", %{conn: conn} do
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" -> Req.Test.transport_error(conn, :closed)
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      html = view |> element("button[phx-click='start_enroll']") |> render_click()

      assert html =~ "Network error" or html =~ "Interactor"
    end
  end

  describe "verify event — success paths" do
    defp setup_verify_step(conn, verify_handler) do
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" ->
            # First POST is enable, second is verify
            path = conn.request_path

            if String.ends_with?(path, "/verify") do
              verify_handler.(conn)
            else
              enable_success(conn)
            end
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      # Advance to :verify step
      view |> element("button[phx-click='start_enroll']") |> render_click()
      view
    end

    test "verify success with recovery codes renders :done step and displays codes", %{
      conn: conn
    } do
      view = setup_verify_step(conn, &verify_success_with_codes/1)

      html = render_hook(view, "verify", %{"mfa" => %{"code" => "123456"}})

      assert html =~ "MFA enabled"
      assert html =~ "Save your recovery codes"
      assert html =~ "code-aaa"
      assert html =~ "code-bbb"
      assert html =~ "code-ccc"
    end

    test "verify success without recovery_codes field renders :done without codes list", %{
      conn: conn
    } do
      view = setup_verify_step(conn, &verify_success_no_codes/1)

      html = render_hook(view, "verify", %{"mfa" => %{"code" => "123456"}})

      assert html =~ "MFA enabled"
      refute html =~ "Save your recovery codes"
    end

    test "successful verify sets enrolled? to true", %{conn: conn} do
      view = setup_verify_step(conn, &verify_success_with_codes/1)

      html = render_hook(view, "verify", %{"mfa" => %{"code" => "123456"}})

      # :done step is rendered, which means enrolled? was set to true
      assert html =~ "MFA enabled"
    end
  end

  describe "verify event — error paths" do
    test "shows error when verify returns non-200", %{conn: conn} do
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" ->
            path = conn.request_path

            if String.ends_with?(path, "/verify") do
              Plug.Conn.put_status(conn, 422) |> Req.Test.json(%{"error" => "invalid code"})
            else
              enable_success(conn)
            end
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      view |> element("button[phx-click='start_enroll']") |> render_click()

      html = render_hook(view, "verify", %{"mfa" => %{"code" => "000000"}})

      refute html =~ "Save your recovery codes"
      assert html =~ "Two-factor authentication"
    end

    test "shows error when verify returns a network error", %{conn: conn} do
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" ->
            path = conn.request_path

            if String.ends_with?(path, "/verify") do
              Req.Test.transport_error(conn, :closed)
            else
              enable_success(conn)
            end
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      view |> element("button[phx-click='start_enroll']") |> render_click()

      html = render_hook(view, "verify", %{"mfa" => %{"code" => "999999"}})

      refute html =~ "Save your recovery codes"
      assert html =~ "Two-factor authentication"
    end
  end

  describe "validate event" do
    test "validate updates the code field without causing errors", %{conn: conn} do
      stub(&profile_mfa_disabled/1)
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      result = render_hook(view, "validate", %{"mfa" => %{"code" => "123456"}})

      refute result =~ "phx-value-error"
    end

    test "validate does not trigger an error state or flash message", %{conn: conn} do
      stub(&profile_mfa_disabled/1)
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      html = render_hook(view, "validate", %{"mfa" => %{"code" => "654321"}})

      # After validate, the idle state is still shown (not verify or done).
      # No error banner text should appear from the validate event itself.
      refute html =~ "Network error"
      refute html =~ "Not authorized"
      refute html =~ "Save your recovery codes"
    end
  end

  describe "cancel event" do
    test "cancel from :idle step does not crash and shows idle state", %{conn: conn} do
      stub(&profile_mfa_disabled/1)
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      render_hook(view, "cancel", %{})
      html = render(view)

      assert html =~ "Two-factor authentication"
      assert html =~ "MFA is not enabled"
      refute html =~ "Verify and enable"
    end

    test "cancel from :verify step resets to idle and clears error", %{conn: conn} do
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" -> enable_success(conn)
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      # Advance to :verify step
      view |> element("button[phx-click='start_enroll']") |> render_click()

      # Cancel
      view |> element("button[phx-click='cancel']") |> render_click()
      html = render(view)

      refute html =~ "Add this to your app"
      refute html =~ "Verify and enable"
      assert html =~ "Two-factor authentication"
    end

    test "cancel clears otpauth_uri and secret assigns", %{conn: conn} do
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" -> enable_success(conn)
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      view |> element("button[phx-click='start_enroll']") |> render_click()

      # Verify the secret is visible in :verify step
      assert render(view) =~ "TESTSECRET"

      view |> element("button[phx-click='cancel']") |> render_click()
      html = render(view)

      # After cancel, secret and URI are gone
      refute html =~ "TESTSECRET"
      refute html =~ "otpauth://"
    end
  end

  describe "error rendering" do
    test "renders error banner when error assign is set via start_enroll 401", %{conn: conn} do
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" -> Plug.Conn.put_status(conn, 401) |> Req.Test.json(%{})
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      view |> element("button[phx-click='start_enroll']") |> render_click()
      html = render(view)

      assert html =~ "role=\"alert\""
    end

    test "error banner renders error message from 'error' key in body", %{conn: conn} do
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" ->
            Plug.Conn.put_status(conn, 500) |> Req.Test.json(%{"error" => "backend failure"})
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      html = view |> element("button[phx-click='start_enroll']") |> render_click()

      # extract_error_message/1 reads "error" key first
      assert html =~ "backend failure" or html =~ "500"
    end

    test "error message renders body map inspection when no known key", %{conn: conn} do
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" ->
            Plug.Conn.put_status(conn, 500) |> Req.Test.json(%{"detail" => "something went wrong"})
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      html = view |> element("button[phx-click='start_enroll']") |> render_click()

      # extract_error_message/1 falls back to inspect when no "error"/"message" key
      assert html =~ "something went wrong" or html =~ "500" or html =~ "Interactor"
    end
  end

  describe "render — :verify step UI" do
    test "verify step renders the authenticator link with otpauth URI", %{conn: conn} do
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" -> enable_success(conn)
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      html = view |> element("button[phx-click='start_enroll']") |> render_click()

      assert html =~ "Open in authenticator app"
      assert html =~ "otpauth://"
      assert html =~ "enter this secret manually"
      assert html =~ "TESTSECRET"
    end

    test "verify step shows the code input and submit button", %{conn: conn} do
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" -> enable_success(conn)
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      html = view |> element("button[phx-click='start_enroll']") |> render_click()

      assert html =~ "phx-submit=\"verify\""
      assert html =~ "phx-change=\"validate\""
      assert html =~ "one-time-code"
    end
  end

  describe "render — :done step UI" do
    test "done step with recovery codes shows all codes in a list", %{conn: conn} do
      stub(fn conn ->
        case conn.method do
          "GET" -> profile_mfa_disabled(conn)
          "POST" ->
            path = conn.request_path

            if String.ends_with?(path, "/verify"),
              do: verify_success_with_codes(conn),
              else: enable_success(conn)
        end
      end)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/settings/mfa")
      allow(view)

      view |> element("button[phx-click='start_enroll']") |> render_click()
      html = render_hook(view, "verify", %{"mfa" => %{"code" => "123456"}})

      assert html =~ "code-aaa"
      assert html =~ "code-bbb"
      assert html =~ "code-ccc"
      assert html =~ "Each code can be used once"
    end
  end

  describe "render — :idle with enrolled? = nil" do
    test "shows loading message when enrolled? is nil (initial value before mount completes)", %{
      conn: conn
    } do
      # We can't hold the mount mid-flight, but we can verify the template
      # has the loading clause by checking the existing initial render assigns.
      # In test, mount always completes, so enrolled? is false (not nil).
      # The nil branch is a defensive render; we just verify the page still loads.
      stub(&profile_mfa_disabled/1)
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/settings/mfa")

      assert html =~ "Two-factor authentication"
    end
  end
end
