defmodule FunSheepWeb.CatalogLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.ContentFixtures

  defp auth_conn(conn, user_role) do
    conn
    |> init_test_session(%{
      dev_user_id: user_role.interactor_user_id,
      dev_user: %{
        "id" => user_role.interactor_user_id,
        "role" => "student",
        "email" => user_role.email,
        "display_name" => user_role.display_name,
        "user_role_id" => user_role.id
      }
    })
  end

  defp create_premium_course(attrs \\ %{}) do
    defaults = %{
      name: "SAT Math Course #{System.unique_integer([:positive])}",
      subject: "Mathematics",
      grade: "11",
      access_level: "standard",
      is_premium_catalog: true,
      catalog_test_type: "sat",
      catalog_subject: "mathematics",
      published_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    ContentFixtures.create_course(Map.merge(defaults, attrs))
  end

  describe "mount" do
    test "renders the catalog page with hero section", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user_role)

      {:ok, _lv, html} = live(conn, ~p"/catalog")

      assert html =~ "Prep for the tests that matter most"
      assert html =~ "College Admission"
      assert html =~ "AP Courses"
      assert html =~ "International"
      assert html =~ "Professional"
    end

    test "shows empty state when no catalog courses exist", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user_role)

      {:ok, _lv, html} = live(conn, ~p"/catalog")

      assert html =~ "No courses in this category yet"
    end

    test "shows published premium catalog courses", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      _course = create_premium_course(%{name: "SAT Math Practice"})
      conn = auth_conn(conn, user_role)

      {:ok, _lv, html} = live(conn, ~p"/catalog")

      assert html =~ "SAT Math Practice"
    end

    test "does not show unpublished catalog courses", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()

      _unpublished =
        ContentFixtures.create_course(%{
          name: "Unpublished Premium Course",
          subject: "Math",
          grade: "11",
          is_premium_catalog: true,
          catalog_test_type: "sat",
          published_at: nil
        })

      conn = auth_conn(conn, user_role)

      {:ok, _lv, html} = live(conn, ~p"/catalog")

      refute html =~ "Unpublished Premium Course"
    end
  end

  describe "lock state display" do
    test "shows 'Unlock' for locked courses (free user, standard course)", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      _course = create_premium_course(%{access_level: "standard", name: "Locked SAT Course"})
      conn = auth_conn(conn, user_role)

      {:ok, _lv, html} = live(conn, ~p"/catalog")

      # Free users cannot access standard-tier courses
      assert html =~ "Unlock"
    end

    test "shows 'Start Practicing' for public courses (free user)", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()

      _course =
        create_premium_course(%{
          access_level: "public",
          name: "Free SAT Preview",
          catalog_test_type: "sat"
        })

      conn = auth_conn(conn, user_role)

      {:ok, _lv, html} = live(conn, ~p"/catalog")

      assert html =~ "Start Practicing"
    end

    test "shows 'Start Practicing' for preview courses (free user)", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()

      _course =
        create_premium_course(%{
          access_level: "preview",
          name: "Preview SAT Course",
          catalog_test_type: "sat"
        })

      conn = auth_conn(conn, user_role)

      {:ok, _lv, html} = live(conn, ~p"/catalog")

      assert html =~ "Start Practicing"
    end
  end

  describe "category filtering" do
    setup do
      _sat_course = create_premium_course(%{name: "SAT Verbal", catalog_test_type: "sat"})
      _ap_course = create_premium_course(%{name: "AP Calculus BC", catalog_test_type: "ap"})
      _ib_course = create_premium_course(%{name: "IB Biology HL", catalog_test_type: "ib"})
      :ok
    end

    test "shows all courses when 'All' is selected", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user_role)

      {:ok, _lv, html} = live(conn, ~p"/catalog")

      assert html =~ "SAT Verbal"
      assert html =~ "AP Calculus BC"
      assert html =~ "IB Biology HL"
    end

    test "filters by AP category via URL param", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user_role)

      {:ok, _lv, html} = live(conn, ~p"/catalog?category=ap")

      assert html =~ "AP Calculus BC"
      refute html =~ "SAT Verbal"
      refute html =~ "IB Biology HL"
    end

    test "select_category event filters courses", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user_role)

      {:ok, lv, _html} = live(conn, ~p"/catalog")

      # Switch to AP Courses
      html =
        lv
        |> element("button", "AP Courses")
        |> render_click()

      assert html =~ "AP Calculus BC"
      refute html =~ "SAT Verbal"
    end

    test "College Admission category shows SAT, ACT, CLT courses", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      _act = create_premium_course(%{name: "ACT Science", catalog_test_type: "act"})
      conn = auth_conn(conn, user_role)

      {:ok, lv, _html} = live(conn, ~p"/catalog")

      html =
        lv
        |> element("button", "College Admission")
        |> render_click()

      assert html =~ "SAT Verbal"
      assert html =~ "ACT Science"
      refute html =~ "AP Calculus BC"
    end

    test "unknown category param falls back to all courses", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user_role)

      {:ok, _lv, html} = live(conn, ~p"/catalog?category=nonexistent")

      assert html =~ "SAT Verbal"
      assert html =~ "AP Calculus BC"
    end
  end

  describe "upgrade modal" do
    test "clicking Unlock opens upgrade modal for locked course", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      _course = create_premium_course(%{access_level: "standard", name: "Locked Premium Course"})
      conn = auth_conn(conn, user_role)

      {:ok, lv, _html} = live(conn, ~p"/catalog")

      html =
        lv
        |> element("button", "Unlock")
        |> render_click()

      assert html =~ "FunSheep Premium"
      assert html =~ "Locked Premium Course"
    end

    test "close_upgrade_modal event hides the modal", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      _course = create_premium_course(%{access_level: "standard", name: "Another Premium Course"})
      conn = auth_conn(conn, user_role)

      {:ok, lv, _html} = live(conn, ~p"/catalog")

      # Open the modal
      lv |> element("button", "Unlock") |> render_click()

      # Close it via the parent LiveView event
      html = render_hook(lv, "close_upgrade_modal", %{})

      refute html =~ "FunSheep Premium"
    end
  end

  describe "course cards" do
    test "displays test type badge for catalog courses", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      _course = create_premium_course(%{catalog_test_type: "act", name: "ACT Course"})
      conn = auth_conn(conn, user_role)

      {:ok, _lv, html} = live(conn, ~p"/catalog")

      assert html =~ "ACT"
    end

    test "displays subject badge when catalog_subject is set", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()

      _course =
        create_premium_course(%{
          catalog_subject: "english_language",
          name: "SAT English"
        })

      conn = auth_conn(conn, user_role)

      {:ok, _lv, html} = live(conn, ~p"/catalog")

      assert html =~ "English Language"
    end
  end
end
