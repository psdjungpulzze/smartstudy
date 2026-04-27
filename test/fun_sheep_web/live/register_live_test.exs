defmodule FunSheepWeb.RegisterLiveTest do
  # async: false because we modify global Req default options to intercept HTTP calls
  # in RegisterLive (which doesn't have the per-module req_opts hook that LoginLive has)
  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @valid_params %{
    "email" => "newuser@example.com",
    "username" => "coolsheep",
    "password" => "password123",
    "password_confirmation" => "password123"
  }

  # Inject Req.Test plug globally so RegisterLive's Req.post is intercepted.
  # This approach is needed because RegisterLive does not have the extra_req_opts()
  # hook that LoginLive uses.
  setup do
    prev_options = Req.default_options()

    Req.default_options(plug: {Req.Test, FunSheepWeb.RegisterLive})

    on_exit(fn ->
      # Restore prior global Req options (typically [])
      :ok = Application.put_env(:req, :default_options, prev_options)
    end)

    :ok
  end

  describe "GET /auth/register — initial render" do
    test "renders the registration form", %{conn: conn} do
      Req.Test.stub(FunSheepWeb.RegisterLive, fn _conn ->
        raise "RegisterLive should not make HTTP calls on mount"
      end)

      {:ok, _view, html} = live(conn, "/auth/register")

      assert html =~ "Create your account"
      assert html =~ "Create an account"
    end

    test "renders the role selector with student, teacher, and parent options", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/register")

      assert html =~ "Student"
      assert html =~ "Teacher"
      assert html =~ "Parent"
    end

    test "renders form fields for email, username, password, and confirm password", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/register")

      assert html =~ "Email"
      assert html =~ "Username"
      assert html =~ "Password"
      assert html =~ "Confirm password"
    end

    test "renders Google SSO button", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/register")

      assert html =~ "Continue with Google"
      assert html =~ "/auth/login/redirect"
    end

    test "renders page title as Create an account", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      assert page_title(view) =~ "Create an account"
    end

    test "renders FunSheep branding", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/register")

      assert html =~ "Join the Flock!"
      assert html =~ "Secured by Interactor"
    end

    test "renders link to sign in page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/register")

      assert html =~ "Already have an account?"
      assert html =~ "Sign in"
    end

    test "student role is selected by default (shows checkmark)", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/register")

      assert html =~ "✓"
    end

    test "create account button is present", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/register")

      assert html =~ "Create account"
    end

    test "no errors shown on initial render", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/register")

      refute html =~ "⚠️"
    end

    test "success state is NOT shown on initial mount", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/register")

      refute html =~ "Check your email!"
      refute html =~ "Go to sign in"
    end

    test "registration form has phx-submit and phx-change attributes", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/register")

      assert html =~ ~s(phx-submit="register")
      assert html =~ ~s(phx-change="validate")
    end

    test "I'm registering as label is shown", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/register")

      assert html =~ "registering as"
    end
  end

  describe "GET /auth/register — role param pre-selection" do
    test "?role=student pre-selects student (default, shows checkmark)", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/register?role=student")

      assert html =~ "Student"
      assert html =~ "✓"
    end

    test "?role=teacher pre-selects teacher", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/register?role=teacher")

      assert html =~ "Teacher"
    end

    test "?role=parent pre-selects parent", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/register?role=parent")

      assert html =~ "Parent"
    end

    test "invalid ?role param falls back to student (shows checkmark)", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/register?role=superadmin")

      assert html =~ "Student"
      assert html =~ "✓"
    end

    test "empty ?role param falls back to student", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/register?role=")

      assert html =~ "Student"
    end
  end

  describe "already-authenticated redirect" do
    test "user with dev_user session is redirected to /dashboard", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{
          dev_user: %{
            "id" => "user_123",
            "role" => "student",
            "email" => "student@example.com",
            "display_name" => "Test Student"
          }
        })

      assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, "/auth/register")
    end

    test "user with current_user session is redirected to /dashboard", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{
          current_user: %{
            "id" => "user_456",
            "role" => "student"
          }
        })

      assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, "/auth/register")
    end
  end

  describe "select_role event" do
    test "switching to teacher role updates the UI", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html = render_click(view, "select_role", %{"role" => "teacher"})

      assert html =~ "Teacher"
    end

    test "switching to parent role updates the UI", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html = render_click(view, "select_role", %{"role" => "parent"})

      assert html =~ "Parent"
    end

    test "switching back to student from teacher shows student selected with checkmark", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/auth/register")

      render_click(view, "select_role", %{"role" => "teacher"})
      html = render_click(view, "select_role", %{"role" => "student"})

      assert html =~ "✓"
    end

    test "invalid role is a no-op — does not crash or change role", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html_after = render_click(view, "select_role", %{"role" => "hacker"})

      # Student still selected (default)
      assert html_after =~ "✓"
    end

    test "student -> teacher -> parent cycle works without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      render_click(view, "select_role", %{"role" => "teacher"})
      html = render_click(view, "select_role", %{"role" => "parent"})

      assert html =~ "Parent"
    end

    test "selecting same role (student) twice is a no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      render_click(view, "select_role", %{"role" => "student"})
      html = render_click(view, "select_role", %{"role" => "student"})

      assert html =~ "✓"
    end
  end

  describe "validate event" do
    test "validate updates form values in the rendered output", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html =
        view
        |> form("form[phx-submit='register']", %{
          "registration" => @valid_params
        })
        |> render_change()

      assert html =~ "newuser@example.com"
      assert html =~ "coolsheep"
    end

    test "validate with missing email shows email error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html =
        view
        |> form("form[phx-submit='register']", %{
          "registration" => Map.put(@valid_params, "email", "")
        })
        |> render_change()

      assert html =~ "Email is required"
    end

    test "validate with missing username shows username error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html =
        view
        |> form("form[phx-submit='register']", %{
          "registration" => Map.put(@valid_params, "username", "")
        })
        |> render_change()

      assert html =~ "Username is required"
    end

    test "validate with short password shows password error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html =
        view
        |> form("form[phx-submit='register']", %{
          "registration" => Map.put(@valid_params, "password", "short")
        })
        |> render_change()

      assert html =~ "Password must be at least 8 characters"
    end

    test "validate with mismatched passwords shows confirmation error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html =
        view
        |> form("form[phx-submit='register']", %{
          "registration" =>
            @valid_params
            |> Map.put("password", "password123")
            |> Map.put("password_confirmation", "differentpass")
        })
        |> render_change()

      assert html =~ "Passwords don&#39;t match" or html =~ "Passwords don't match"
    end

    test "validate with all valid fields shows no inline errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html =
        view
        |> form("form[phx-submit='register']", %{"registration" => @valid_params})
        |> render_change()

      refute html =~ "is required"
      refute html =~ "at least 8"
    end

    test "validate with all empty fields shows all validation errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html =
        view
        |> form("form[phx-submit='register']", %{
          "registration" => %{
            "email" => "",
            "username" => "",
            "password" => "",
            "password_confirmation" => ""
          }
        })
        |> render_change()

      assert html =~ "Email is required"
      assert html =~ "Username is required"
      assert html =~ "Password must be at least 8 characters"
    end

    test "validate exactly 8 character password does not show password error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html =
        view
        |> form("form[phx-submit='register']", %{
          "registration" =>
            @valid_params
            |> Map.put("password", "12345678")
            |> Map.put("password_confirmation", "12345678")
        })
        |> render_change()

      refute html =~ "Password must be at least 8 characters"
    end

    test "validate with 7 character password shows password error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html =
        view
        |> form("form[phx-submit='register']", %{
          "registration" => Map.put(@valid_params, "password", "1234567")
        })
        |> render_change()

      assert html =~ "Password must be at least 8 characters"
    end
  end

  describe "register event — client-side validation failures (no HTTP call)" do
    test "submit with empty email shows email error and stays on form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html =
        view
        |> form("form[phx-submit='register']", %{
          "registration" => Map.put(@valid_params, "email", "")
        })
        |> render_submit()

      assert html =~ "Email is required"
      refute html =~ "Check your email!"
    end

    test "submit with empty username shows username error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html =
        view
        |> form("form[phx-submit='register']", %{
          "registration" => Map.put(@valid_params, "username", "")
        })
        |> render_submit()

      assert html =~ "Username is required"
    end

    test "submit with password too short shows password error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html =
        view
        |> form("form[phx-submit='register']", %{
          "registration" =>
            @valid_params
            |> Map.put("password", "short")
            |> Map.put("password_confirmation", "short")
        })
        |> render_submit()

      assert html =~ "Password must be at least 8 characters"
    end

    test "submit with mismatched passwords shows confirmation error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html =
        view
        |> form("form[phx-submit='register']", %{
          "registration" =>
            @valid_params
            |> Map.put("password_confirmation", "nomatch")
        })
        |> render_submit()

      assert html =~ "Passwords don&#39;t match" or html =~ "Passwords don't match"
    end

    test "submit with all fields empty shows all validation errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html =
        view
        |> form("form[phx-submit='register']", %{
          "registration" => %{
            "email" => "",
            "username" => "",
            "password" => "",
            "password_confirmation" => ""
          }
        })
        |> render_submit()

      assert html =~ "Email is required"
      assert html =~ "Username is required"
      assert html =~ "Password must be at least 8 characters"
    end

    test "whitespace-only email is treated as empty", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html =
        view
        |> form("form[phx-submit='register']", %{
          "registration" => Map.put(@valid_params, "email", "   ")
        })
        |> render_submit()

      assert html =~ "Email is required"
    end

    test "whitespace-only username is treated as empty", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/register")

      html =
        view
        |> form("form[phx-submit='register']", %{
          "registration" => Map.put(@valid_params, "username", "   ")
        })
        |> render_submit()

      assert html =~ "Username is required"
    end
  end

  describe "register event — successful registration (Req.Test stub)" do
    test "successful registration shows the success state", %{conn: conn} do
      Req.Test.stub(FunSheepWeb.RegisterLive, fn conn ->
        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(%{
          "message" => "Registration successful! Check your email to verify your account."
        })
      end)

      {:ok, view, _html} = live(conn, "/auth/register")
      Req.Test.allow(FunSheepWeb.RegisterLive, self(), view.pid)

      html =
        view
        |> form("form[phx-submit='register']", %{"registration" => @valid_params})
        |> render_submit()

      assert html =~ "Check your email!"
      assert html =~ "Registration successful! Check your email to verify your account."
      assert html =~ "Go to sign in"
    end

    test "success state shows link back to login with selected role", %{conn: conn} do
      Req.Test.stub(FunSheepWeb.RegisterLive, fn conn ->
        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(%{"message" => "Please verify your email."})
      end)

      {:ok, view, _html} = live(conn, "/auth/register")
      Req.Test.allow(FunSheepWeb.RegisterLive, self(), view.pid)

      html =
        view
        |> form("form[phx-submit='register']", %{"registration" => @valid_params})
        |> render_submit()

      assert html =~ "/auth/login?role=student"
      assert html =~ "Go to sign in"
    end

    test "success state uses the message from the server response", %{conn: conn} do
      Req.Test.stub(FunSheepWeb.RegisterLive, fn conn ->
        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(%{"message" => "Custom server message here!"})
      end)

      {:ok, view, _html} = live(conn, "/auth/register")
      Req.Test.allow(FunSheepWeb.RegisterLive, self(), view.pid)

      html =
        view
        |> form("form[phx-submit='register']", %{"registration" => @valid_params})
        |> render_submit()

      assert html =~ "Custom server message here!"
    end

    test "success with no message field uses the default fallback", %{conn: conn} do
      Req.Test.stub(FunSheepWeb.RegisterLive, fn conn ->
        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(%{})
      end)

      {:ok, view, _html} = live(conn, "/auth/register")
      Req.Test.allow(FunSheepWeb.RegisterLive, self(), view.pid)

      html =
        view
        |> form("form[phx-submit='register']", %{"registration" => @valid_params})
        |> render_submit()

      assert html =~ "Check your email!"
      assert html =~ "Registration successful! Check your email to verify your account."
    end

    test "teacher role registration shows login link with teacher role", %{conn: conn} do
      Req.Test.stub(FunSheepWeb.RegisterLive, fn conn ->
        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(%{"message" => "Done"})
      end)

      {:ok, view, _html} = live(conn, "/auth/register")
      Req.Test.allow(FunSheepWeb.RegisterLive, self(), view.pid)

      render_click(view, "select_role", %{"role" => "teacher"})

      html =
        view
        |> form("form[phx-submit='register']", %{"registration" => @valid_params})
        |> render_submit()

      assert html =~ "/auth/login?role=teacher"
    end

    test "parent role registration shows login link with parent role", %{conn: conn} do
      Req.Test.stub(FunSheepWeb.RegisterLive, fn conn ->
        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(%{"message" => "Done"})
      end)

      {:ok, view, _html} = live(conn, "/auth/register")
      Req.Test.allow(FunSheepWeb.RegisterLive, self(), view.pid)

      render_click(view, "select_role", %{"role" => "parent"})

      html =
        view
        |> form("form[phx-submit='register']", %{"registration" => @valid_params})
        |> render_submit()

      assert html =~ "/auth/login?role=parent"
    end
  end

  describe "register event — server errors (Req.Test stub)" do
    test "422 with validation errors shows the errors as a base error", %{conn: conn} do
      Req.Test.stub(FunSheepWeb.RegisterLive, fn conn ->
        conn
        |> Plug.Conn.put_status(422)
        |> Req.Test.json(%{
          "errors" => %{
            "email" => ["has already been taken"]
          }
        })
      end)

      {:ok, view, _html} = live(conn, "/auth/register")
      Req.Test.allow(FunSheepWeb.RegisterLive, self(), view.pid)

      html =
        view
        |> form("form[phx-submit='register']", %{"registration" => @valid_params})
        |> render_submit()

      assert html =~ "⚠️"
      assert html =~ "has already been taken"
    end

    test "422 with multiple error messages joins them", %{conn: conn} do
      Req.Test.stub(FunSheepWeb.RegisterLive, fn conn ->
        conn
        |> Plug.Conn.put_status(422)
        |> Req.Test.json(%{
          "errors" => %{
            "username" => ["is too short", "must be unique"]
          }
        })
      end)

      {:ok, view, _html} = live(conn, "/auth/register")
      Req.Test.allow(FunSheepWeb.RegisterLive, self(), view.pid)

      html =
        view
        |> form("form[phx-submit='register']", %{"registration" => @valid_params})
        |> render_submit()

      assert html =~ "⚠️"
      assert html =~ "is too short"
    end

    test "500 with error field shows the error message", %{conn: conn} do
      Req.Test.stub(FunSheepWeb.RegisterLive, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{"error" => "Internal server error"})
      end)

      {:ok, view, _html} = live(conn, "/auth/register")
      Req.Test.allow(FunSheepWeb.RegisterLive, self(), view.pid)

      html =
        view
        |> form("form[phx-submit='register']", %{"registration" => @valid_params})
        |> render_submit()

      assert html =~ "⚠️"
      assert html =~ "Internal server error"
    end

    test "403 with error field shows the error message", %{conn: conn} do
      Req.Test.stub(FunSheepWeb.RegisterLive, fn conn ->
        conn
        |> Plug.Conn.put_status(403)
        |> Req.Test.json(%{"error" => "Registration not allowed"})
      end)

      {:ok, view, _html} = live(conn, "/auth/register")
      Req.Test.allow(FunSheepWeb.RegisterLive, self(), view.pid)

      html =
        view
        |> form("form[phx-submit='register']", %{"registration" => @valid_params})
        |> render_submit()

      assert html =~ "⚠️"
      assert html =~ "Registration not allowed"
    end

    test "unexpected 503 without error field shows registration failed message", %{conn: conn} do
      Req.Test.stub(FunSheepWeb.RegisterLive, fn conn ->
        conn
        |> Plug.Conn.put_status(503)
        |> Req.Test.json(%{})
      end)

      {:ok, view, _html} = live(conn, "/auth/register")
      Req.Test.allow(FunSheepWeb.RegisterLive, self(), view.pid)

      html =
        view
        |> form("form[phx-submit='register']", %{"registration" => @valid_params})
        |> render_submit()

      assert html =~ "⚠️"
      assert html =~ "503" or html =~ "failed" or html =~ "Please try again"
    end

    test "server error does NOT show the success state", %{conn: conn} do
      Req.Test.stub(FunSheepWeb.RegisterLive, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{"error" => "Server exploded"})
      end)

      {:ok, view, _html} = live(conn, "/auth/register")
      Req.Test.allow(FunSheepWeb.RegisterLive, self(), view.pid)

      html =
        view
        |> form("form[phx-submit='register']", %{"registration" => @valid_params})
        |> render_submit()

      refute html =~ "Check your email!"
      refute html =~ "Go to sign in"
    end

    test "connection refused shows service unavailable message", %{conn: conn} do
      Req.Test.stub(FunSheepWeb.RegisterLive, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      {:ok, view, _html} = live(conn, "/auth/register")
      Req.Test.allow(FunSheepWeb.RegisterLive, self(), view.pid)

      html =
        view
        |> form("form[phx-submit='register']", %{"registration" => @valid_params})
        |> render_submit()

      assert html =~ "⚠️"
      assert html =~ "unavailable" or html =~ "try again"
    end

    test "generic transport error shows connection error message", %{conn: conn} do
      Req.Test.stub(FunSheepWeb.RegisterLive, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      {:ok, view, _html} = live(conn, "/auth/register")
      Req.Test.allow(FunSheepWeb.RegisterLive, self(), view.pid)

      html =
        view
        |> form("form[phx-submit='register']", %{"registration" => @valid_params})
        |> render_submit()

      assert html =~ "⚠️"
      assert html =~ "Connection error" or html =~ "try again"
    end
  end

  describe "validate + register flow interaction" do
    test "validate then register with valid data succeeds", %{conn: conn} do
      Req.Test.stub(FunSheepWeb.RegisterLive, fn conn ->
        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(%{"message" => "Please check your email."})
      end)

      {:ok, view, _html} = live(conn, "/auth/register")
      Req.Test.allow(FunSheepWeb.RegisterLive, self(), view.pid)

      # First validate
      view
      |> form("form[phx-submit='register']", %{"registration" => @valid_params})
      |> render_change()

      # Then submit
      html =
        view
        |> form("form[phx-submit='register']", %{"registration" => @valid_params})
        |> render_submit()

      assert html =~ "Check your email!"
    end

    test "validate with errors then fix and submit succeeds", %{conn: conn} do
      Req.Test.stub(FunSheepWeb.RegisterLive, fn conn ->
        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(%{"message" => "Success"})
      end)

      {:ok, view, _html} = live(conn, "/auth/register")
      Req.Test.allow(FunSheepWeb.RegisterLive, self(), view.pid)

      # Validate with bad email first
      view
      |> form("form[phx-submit='register']", %{
        "registration" => Map.put(@valid_params, "email", "")
      })
      |> render_change()

      # Then submit with corrected data
      html =
        view
        |> form("form[phx-submit='register']", %{"registration" => @valid_params})
        |> render_submit()

      assert html =~ "Check your email!"
    end
  end
end
