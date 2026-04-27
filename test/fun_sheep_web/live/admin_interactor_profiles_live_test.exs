defmodule FunSheepWeb.AdminInteractorProfilesLiveTest do
  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts

  defp create_admin do
    {:ok, admin} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: :admin,
        email: "admin_profiles_#{:rand.uniform(999_999)}@test.com",
        display_name: "Test Admin"
      })

    admin
  end

  defp create_student(email \\ nil) do
    email = email || "student_#{:rand.uniform(999_999)}@example.com"

    {:ok, student} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: :student,
        email: email,
        display_name: "Stu Dent"
      })

    student
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

  describe "/admin/interactor/profiles — basic rendering" do
    test "renders empty state", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      assert html =~ "Interactor profiles"
      assert html =~ "Search user"
      assert html =~ "Pick a user to view their Interactor profile."
    end

    test "page title is set", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")
      assert html =~ "Interactor profiles"
    end
  end

  describe "search handle_event" do
    test "search with >= 2 chars surfaces matching users", %{conn: conn} do
      _student = create_student("findable@example.com")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"search" => "findable"})

      assert html =~ "findable@example.com"
    end

    test "search with < 2 chars returns empty list (no results rendered)", %{conn: conn} do
      _student = create_student("shortmatch@example.com")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"search" => "s"})

      # No user list items rendered for a single character
      refute html =~ "shortmatch@example.com"
    end

    test "search with empty string returns empty list", %{conn: conn} do
      _student = create_student("emptymatch@example.com")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"search" => ""})

      refute html =~ "emptymatch@example.com"
    end
  end

  describe "select_user handle_event" do
    test "select_user loads the profile editor + effective preview", %{conn: conn} do
      student = create_student("pick@example.com")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      view
      |> element("form[phx-change='search']")
      |> render_change(%{"search" => "pick"})

      view
      |> element("li[phx-click='select_user'][phx-value-id='#{student.id}']")
      |> render_click()

      page = render(view)
      assert page =~ "User profile (raw)"
      assert page =~ "Effective profile (merged)"
      assert page =~ student.email
    end

    test "selecting user shows Interactor user id", %{conn: conn} do
      student = create_student("interactorid@example.com")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      view
      |> element("form[phx-change='search']")
      |> render_change(%{"search" => "interactorid"})

      view
      |> element("li[phx-click='select_user'][phx-value-id='#{student.id}']")
      |> render_click()

      page = render(view)
      assert page =~ student.interactor_user_id
    end

    test "selecting user hides the empty-state prompt", %{conn: conn} do
      student = create_student("hides@example.com")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      view
      |> element("form[phx-change='search']")
      |> render_change(%{"search" => "hides"})

      view
      |> element("li[phx-click='select_user'][phx-value-id='#{student.id}']")
      |> render_click()

      page = render(view)
      refute page =~ "Pick a user to view their Interactor profile."
    end

    test "after selecting user, refresh button is visible", %{conn: conn} do
      student = create_student("refresh_visible@example.com")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      view
      |> element("form[phx-change='search']")
      |> render_change(%{"search" => "refresh_visible"})

      view
      |> element("li[phx-click='select_user'][phx-value-id='#{student.id}']")
      |> render_click()

      page = render(view)
      assert page =~ "Refresh"
    end
  end

  describe "save_profile handle_event" do
    test "save_profile writes audit log", %{conn: conn} do
      student = create_student("save@example.com")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      view
      |> element("form[phx-change='search']")
      |> render_change(%{"search" => "save"})

      view
      |> element("li[phx-click='select_user'][phx-value-id='#{student.id}']")
      |> render_click()

      view
      |> form("form[phx-submit='save_profile']", %{
        "profile" => %{
          "grade" => "5",
          "hobbies" => "soccer, coding",
          "learning_preference" => "visual",
          "custom_instructions" => "Prefers shorter explanations."
        }
      })
      |> render_submit()

      logs = FunSheep.Admin.list_audit_logs(limit: 5)

      assert Enum.any?(
               logs,
               &(&1.action == "admin.profile.update" and &1.target_id == student.id)
             )
    end

    test "save_profile shows success flash", %{conn: conn} do
      student = create_student("flashsave@example.com")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      view
      |> element("form[phx-change='search']")
      |> render_change(%{"search" => "flashsave"})

      view
      |> element("li[phx-click='select_user'][phx-value-id='#{student.id}']")
      |> render_click()

      html =
        view
        |> form("form[phx-submit='save_profile']", %{
          "profile" => %{
            "grade" => "6",
            "hobbies" => "reading",
            "learning_preference" => "auditory",
            "custom_instructions" => ""
          }
        })
        |> render_submit()

      assert html =~ "Profile saved."
    end

    test "save_profile with no user selected shows error flash", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      # Directly send the save_profile event without selecting a user first
      html = render_hook(view, "save_profile", %{"profile" => %{"grade" => "5"}})

      assert html =~ "Pick a user first."
    end

    test "save_profile with nil hobbies and missing optional fields", %{conn: conn} do
      student = create_student("nullhobbies@example.com")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      view
      |> element("form[phx-change='search']")
      |> render_change(%{"search" => "nullhobbies"})

      view
      |> element("li[phx-click='select_user'][phx-value-id='#{student.id}']")
      |> render_click()

      # Submit with empty/nil hobbies — exercises split_list nil and "" branches
      html =
        view
        |> form("form[phx-submit='save_profile']", %{
          "profile" => %{
            "grade" => "",
            "hobbies" => "",
            "learning_preference" => "",
            "custom_instructions" => ""
          }
        })
        |> render_submit()

      assert html =~ "Profile saved."
    end
  end

  describe "refresh handle_event" do
    test "refresh with no user selected is a no-op (stays on empty state)", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      html = render_hook(view, "refresh", %{})

      # Empty state message should still be present
      assert html =~ "Pick a user to view their Interactor profile."
    end

    test "refresh with user selected reloads the profile", %{conn: conn} do
      student = create_student("refreshuser@example.com")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      view
      |> element("form[phx-change='search']")
      |> render_change(%{"search" => "refreshuser"})

      view
      |> element("li[phx-click='select_user'][phx-value-id='#{student.id}']")
      |> render_click()

      # Click refresh button
      view
      |> element("button[phx-click='refresh']")
      |> render_click()

      page = render(view)
      assert page =~ student.email
      assert page =~ "User profile (raw)"
    end
  end

  describe "effective profile preview" do
    test "shows (no data) when Interactor returns empty data (mock mode)", %{conn: conn} do
      # In mock mode Interactor returns %{"data" => []} — effective preview shows (empty) or (no data)
      student = create_student("effectivemock@example.com")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/interactor/profiles")

      view
      |> element("form[phx-change='search']")
      |> render_change(%{"search" => "effectivemock"})

      view
      |> element("li[phx-click='select_user'][phx-value-id='#{student.id}']")
      |> render_click()

      page = render(view)
      # Mock returns [] which hits the "(empty)" branch in format_effective
      assert page =~ "(empty)" or page =~ "(no data)"
    end
  end
end
