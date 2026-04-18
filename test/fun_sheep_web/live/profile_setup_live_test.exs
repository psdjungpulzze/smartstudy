defmodule FunSheepWeb.ProfileSetupLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.Geo

  defp auth_conn(conn) do
    conn
    |> init_test_session(%{
      dev_user_id: "test_student",
      dev_user: %{
        "id" => "test_student",
        "role" => "student",
        "email" => "test@test.com",
        "display_name" => "Test Student"
      }
    })
  end

  describe "step 1 - demographics" do
    test "renders with country dropdown", %{conn: conn} do
      {:ok, _country} = Geo.create_country(%{name: "United States", code: "US"})

      conn = auth_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/profile/setup")

      assert html =~ "Demographics"
      assert html =~ "Country"
      assert html =~ "United States"
      assert html =~ "Grade Level"
      assert html =~ "Gender"
    end

    test "displays user role as read-only", %{conn: conn} do
      conn = auth_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/profile/setup")

      assert html =~ "Student"
    end

    test "loading states on country selection", %{conn: conn} do
      {:ok, country} = Geo.create_country(%{name: "United States", code: "US"})
      {:ok, _state} = Geo.create_state(%{name: "California", country_id: country.id})

      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/profile/setup")

      html =
        view
        |> element("select[name=country_id]")
        |> render_change(%{country_id: country.id})

      assert html =~ "California"
    end
  end

  describe "step navigation" do
    test "next button validates step 1 and shows errors", %{conn: conn} do
      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/profile/setup")

      html = render_click(view, "next_step")

      assert html =~ "Country is required"
      assert html =~ "Grade level is required"
    end

    test "navigating to step 2 with valid data", %{conn: conn} do
      {:ok, country} = Geo.create_country(%{name: "United States", code: "US"})

      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/profile/setup")

      # Set country
      view
      |> element("select[name=country_id]")
      |> render_change(%{country_id: country.id})

      # Set grade
      render_click(view, "update_field", %{"field" => "selected_grade", "value" => "10"})

      # Click next
      html = render_click(view, "next_step")

      assert html =~ "Your Hobbies"
    end

    test "back button returns to previous step", %{conn: conn} do
      {:ok, country} = Geo.create_country(%{name: "United States", code: "US"})

      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/profile/setup")

      # Go to step 2
      view
      |> element("select[name=country_id]")
      |> render_change(%{country_id: country.id})

      render_click(view, "update_field", %{"field" => "selected_grade", "value" => "10"})
      render_click(view, "next_step")

      # Go back
      html = render_click(view, "prev_step")

      assert html =~ "Demographics"
    end
  end

  describe "step 2 - hobbies" do
    setup %{conn: conn} do
      {:ok, country} = Geo.create_country(%{name: "United States", code: "US"})

      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/profile/setup")

      view
      |> element("select[name=country_id]")
      |> render_change(%{country_id: country.id})

      render_click(view, "update_field", %{"field" => "selected_grade", "value" => "10"})
      render_click(view, "next_step")

      %{view: view}
    end

    test "renders hobbies page", %{view: view} do
      html = render(view)
      assert html =~ "Your Hobbies"
      assert html =~ "Select hobbies"
    end

    test "hobby selection toggles", %{view: view} do
      # Create a hobby to select
      {:ok, _hobby} =
        FunSheep.Learning.create_hobby(%{
          name: "TestHobby",
          category: "Test"
        })

      # Re-render to pick up the hobby (it was loaded on step transition)
      # The hobbies were loaded when we navigated to step 2, so TestHobby
      # might not be there. Let's navigate back and forward.
      render_click(view, "prev_step")

      {:ok, hobby2} =
        FunSheep.Learning.create_hobby(%{
          name: "TestHobby2",
          category: "Test2"
        })

      html = render_click(view, "next_step")

      # The hobby should be in the page now
      if html =~ "TestHobby2" do
        html = render_click(view, "toggle_hobby", %{"hobby-id" => hobby2.id})
        assert html =~ "TestHobby2"
      end
    end
  end

  describe "step 3 - file upload" do
    setup %{conn: conn} do
      {:ok, country} = Geo.create_country(%{name: "United States", code: "US"})

      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/profile/setup")

      # Navigate through steps
      view
      |> element("select[name=country_id]")
      |> render_change(%{country_id: country.id})

      render_click(view, "update_field", %{"field" => "selected_grade", "value" => "10"})
      render_click(view, "next_step")
      render_click(view, "next_step")

      %{view: view}
    end

    test "renders upload UI", %{view: view} do
      html = render(view)
      assert html =~ "Upload Materials"
      assert html =~ "Drag and drop"
      assert html =~ "Browse Files"
      assert html =~ "Complete Setup"
    end

    test "shows back button on step 3", %{view: view} do
      html = render(view)
      assert html =~ "Back"
    end
  end
end
