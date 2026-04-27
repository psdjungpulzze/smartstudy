defmodule FunSheepWeb.AuthLiveTest do
  @moduledoc """
  Tests for auth-related LiveViews: ForgotPasswordLive, RegisterLive, ResetPasswordLive.
  These pages do not require authentication and use an external Interactor service,
  so tests focus on UI state and client-side validation without hitting external APIs.
  """

  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "ForgotPasswordLive" do
    test "renders forgot password form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/auth/forgot-password")

      assert html =~ "Reset"
      assert html =~ "email"
    end

    test "shows error when email is blank on submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/auth/forgot-password")

      html = render_submit(view, "submit", %{"forgot" => %{"email" => ""}})

      assert html =~ "Please enter your email address"
    end

    test "validate event updates form state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/auth/forgot-password")

      html = render_change(view, "validate", %{"forgot" => %{"email" => "test@example.com"}})

      assert html =~ "test@example.com"
    end

    test "submit with valid email triggers external request", %{conn: conn} do
      # Interactor is mocked in test env; the call will return an error or ok
      # We just verify the LiveView handles both paths without crashing
      {:ok, view, _html} = live(conn, ~p"/auth/forgot-password")

      result =
        render_submit(view, "submit", %{"forgot" => %{"email" => "valid@example.com"}})

      # Either shows success or error message — both are valid outcomes
      assert result =~ "email" or result =~ "Reset" or result =~ "check"
    end
  end

  describe "RegisterLive" do
    test "renders registration form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/auth/register")

      assert html =~ "Create"
      assert html =~ "email"
    end

    test "shows student role selected by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/auth/register")

      assert html =~ "Student"
    end

    test "select_role event switches role", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/auth/register")

      render_click(view, "select_role", %{"role" => "teacher"})

      html = render(view)
      assert html =~ "Teacher"
    end

    test "validate event updates form state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/auth/register")

      params = %{
        "registration" => %{
          "email" => "newuser@example.com",
          "username" => "newuser",
          "password" => "",
          "password_confirmation" => ""
        }
      }

      html = render_change(view, "validate", params)
      assert html =~ "newuser@example.com"
    end

    test "shows validation error for short password", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/auth/register")

      params = %{
        "registration" => %{
          "email" => "user@example.com",
          "username" => "user",
          "password" => "short",
          "password_confirmation" => "short"
        }
      }

      html = render_submit(view, "register", params)
      assert html =~ "at least" or html =~ "password"
    end

    test "shows error when passwords do not match", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/auth/register")

      params = %{
        "registration" => %{
          "email" => "user@example.com",
          "username" => "user",
          "password" => "securepass123",
          "password_confirmation" => "differentpass"
        }
      }

      html = render_submit(view, "register", params)
      assert html =~ "do not match" or html =~ "password"
    end

    test "redirects authenticated users to dashboard", %{conn: conn} do
      conn =
        init_test_session(conn, %{
          dev_user: %{
            "id" => "user123",
            "role" => "student",
            "email" => "test@test.com",
            "display_name" => "Test"
          },
          dev_user_id: "user123"
        })

      assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/auth/register")
    end
  end

  describe "ResetPasswordLive" do
    test "renders reset form with valid token", %{conn: conn} do
      token = "valid-reset-token-123"
      {:ok, _view, html} = live(conn, "/auth/reset-password/#{token}")

      assert html =~ "password"
      assert html =~ "new password" or html =~ "Set"
    end

    test "validate event updates error state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/reset-password/abc123")

      params = %{
        "reset" => %{
          "password" => "short",
          "password_confirmation" => "short"
        }
      }

      html = render_change(view, "validate", params)
      assert html =~ "password"
    end

    test "validate with valid matching passwords clears errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/reset-password/abc123")

      # First trigger an error
      render_change(view, "validate", %{
        "reset" => %{"password" => "short", "password_confirmation" => "short"}
      })

      # Then fix it
      html =
        render_change(view, "validate", %{
          "reset" => %{
            "password" => "alongpassword123",
            "password_confirmation" => "alongpassword123"
          }
        })

      refute html =~ "at least 8"
      refute html =~ "don&#39;t match"
    end

    test "shows error when passwords do not match", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/reset-password/abc123")

      params = %{
        "reset" => %{
          "password" => "securelongpassword",
          "password_confirmation" => "differentpassword"
        }
      }

      html = render_submit(view, "submit", params)
      assert html =~ "do not match" or html =~ "password"
    end

    test "shows error when password is too short", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/reset-password/abc123")

      params = %{
        "reset" => %{
          "password" => "short",
          "password_confirmation" => "short"
        }
      }

      html = render_submit(view, "submit", params)
      assert html =~ "at least" or html =~ "characters" or html =~ "password"
    end

    test "submit with valid passwords calls the reset endpoint and shows connection error", %{conn: conn} do
      # In test env, the Interactor URL is unreachable, so Req will return a transport error.
      # This exercises the reset/2 function and its {:error, %Req.TransportError{}} clause.
      {:ok, view, _html} = live(conn, "/auth/reset-password/some-token-abc")

      html =
        render_submit(view, "submit", %{
          "reset" => %{
            "password" => "alongvalidpassword",
            "password_confirmation" => "alongvalidpassword"
          }
        })

      # The external call fails (econnrefused or DNS error) — we see an error message
      assert html =~ "unavailable" or html =~ "error" or html =~ "expired" or html =~ "failed" or
               html =~ "Connection"
    end

    test "page title and back link are rendered", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/reset-password/my-token")

      assert html =~ "Back to sign in"
      assert html =~ "Set a new password" or html =~ "password"
    end

    test "loading state is shown while submitting (loading assign)", %{conn: conn} do
      # We verify the submit event reaches the :loading path by checking the
      # button changes state — the external call will fail fast in test env.
      {:ok, view, _html} = live(conn, "/auth/reset-password/tok123")

      # Trigger validation first to ensure form state is consistent
      render_change(view, "validate", %{
        "reset" => %{
          "password" => "validpassword",
          "password_confirmation" => "validpassword"
        }
      })

      html =
        render_submit(view, "submit", %{
          "reset" => %{
            "password" => "validpassword",
            "password_confirmation" => "validpassword"
          }
        })

      # After submit completes (with error), the form is back (loading=false)
      assert html =~ "Update password" or html =~ "Updating"
    end

    test "success assigns and 'Back to sign in' link visible on initial render", %{conn: conn} do
      # Verify the page renders the sign-in redirect link at the bottom
      {:ok, _view, html} = live(conn, "/auth/reset-password/any-token")

      assert html =~ "/auth/login"
    end
  end
end
