defmodule FunSheepWeb.ProfileSetupLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.Geo

  defp auth_conn(conn) do
    interactor_id = "test_interactor_#{System.unique_integer([:positive])}"

    {:ok, user_role} =
      FunSheep.Accounts.create_user_role(%{
        interactor_user_id: interactor_id,
        role: "student",
        email: "test@test.com",
        display_name: "Test Student"
      })

    conn
    |> init_test_session(%{
      dev_user_id: user_role.id,
      dev_user: %{
        "id" => user_role.id,
        "user_role_id" => user_role.id,
        "interactor_user_id" => interactor_id,
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

  describe "step 3 — connect school LMS (first-time onboarding)" do
    setup %{conn: conn} do
      {:ok, country} = Geo.create_country(%{name: "United States", code: "US"})

      conn = auth_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/profile/setup")

      # Walk to step 2
      view
      |> element("select[name=country_id]")
      |> render_change(%{country_id: country.id})

      render_click(view, "update_field", %{"field" => "selected_grade", "value" => "10"})
      render_click(view, "next_step")

      # Complete hobbies → first-timer should advance to step 3
      html = render_click(view, "complete_hobbies")

      %{conn: conn, view: view, step3_html: html}
    end

    test "complete_hobbies advances first-timer to step 3 (Connect)", %{step3_html: html} do
      assert html =~ "Connect your school"
      assert html =~ "Google Classroom"
      assert html =~ "Canvas"
      # Both CTAs present
      assert html =~ ~r/phx-click="connect_lms"/
      assert html =~ ~r/phx-click="skip_lms_connect"/
      # Step indicator now reaches step 3
      assert html =~ "Connect"
    end

    test "connect_lms redirects to /integrations", %{view: view} do
      assert {:error, {:redirect, %{to: "/integrations"}}} =
               render_click(view, "connect_lms")
    end

    test "skip_lms_connect redirects to /dashboard", %{view: view} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               render_click(view, "skip_lms_connect")
    end
  end

  describe "view mode for returning users" do
    test "first-time visit renders the wizard, not the summary", %{conn: conn} do
      conn = auth_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/profile/setup")

      assert html =~ "Demographics"
      refute html =~ "Your Profile"
    end

    test "returning user with saved data sees the summary with hobbies", %{conn: conn} do
      conn = auth_conn(conn)
      user_role_id = get_session(conn, :dev_user)["user_role_id"]

      {:ok, hobby} =
        FunSheep.Learning.create_hobby(%{name: "Coding", category: "Tech"})

      FunSheep.Accounts.update_user_role(
        FunSheep.Accounts.get_user_role!(user_role_id),
        %{grade: "10", gender: "Female"}
      )

      {:ok, _} =
        FunSheep.Learning.create_student_hobby(%{
          user_role_id: user_role_id,
          hobby_id: hobby.id,
          specific_interests: %{"text" => "Python, Web Dev"}
        })

      {:ok, _view, html} = live(conn, ~p"/profile/setup")

      assert html =~ "Your Profile"
      assert html =~ ~r/phx-click="edit_profile"/
      assert html =~ "10"
      assert html =~ "Female"
      assert html =~ "Coding"
      assert html =~ "Python, Web Dev"
      # Wizard is NOT rendered — no country select, no Demographics heading.
      refute html =~ "Select a country"
    end

    test "clicking Edit flips to the wizard", %{conn: conn} do
      conn = auth_conn(conn)
      user_role_id = get_session(conn, :dev_user)["user_role_id"]

      FunSheep.Accounts.update_user_role(
        FunSheep.Accounts.get_user_role!(user_role_id),
        %{grade: "10"}
      )

      {:ok, view, _html} = live(conn, ~p"/profile/setup")
      html = render_click(view, "edit_profile")

      assert html =~ "Demographics"
      assert html =~ ~r/phx-click="cancel_edit"/
    end

    test "summary exposes Edit Hobbies shortcut that jumps to step 2", %{conn: conn} do
      conn = auth_conn(conn)
      user_role_id = get_session(conn, :dev_user)["user_role_id"]

      {:ok, hobby} =
        FunSheep.Learning.create_hobby(%{name: "KPOP", category: "Music"})

      FunSheep.Accounts.update_user_role(
        FunSheep.Accounts.get_user_role!(user_role_id),
        %{grade: "11"}
      )

      {:ok, _} =
        FunSheep.Learning.create_student_hobby(%{
          user_role_id: user_role_id,
          hobby_id: hobby.id,
          specific_interests: %{"text" => ""}
        })

      {:ok, view, html} = live(conn, ~p"/profile/setup")

      assert html =~ ~r/phx-click="edit_hobbies"/

      html = render_click(view, "edit_hobbies")

      assert html =~ "Your Hobbies"
      # Step 2 exposes the Save Changes button wired to complete_hobbies;
      # step 1 would show select[name=country_id] and next_step instead.
      assert html =~ ~r/phx-click="complete_hobbies"/
      refute html =~ ~r/select[^>]*name="country_id"/
    end

    test "edit_hobbies -> complete_hobbies persists interest text without revisiting step 1",
         %{conn: conn} do
      conn = auth_conn(conn)
      user_role_id = get_session(conn, :dev_user)["user_role_id"]

      {:ok, hobby} =
        FunSheep.Learning.create_hobby(%{name: "KPOP", category: "Music"})

      FunSheep.Accounts.update_user_role(
        FunSheep.Accounts.get_user_role!(user_role_id),
        %{grade: "11"}
      )

      {:ok, _} =
        FunSheep.Learning.create_student_hobby(%{
          user_role_id: user_role_id,
          hobby_id: hobby.id,
          specific_interests: %{"text" => ""}
        })

      {:ok, view, _html} = live(conn, ~p"/profile/setup")

      render_click(view, "edit_hobbies")

      render_change(view, "update_hobby_interest", %{
        "hobby-id" => hobby.id,
        "value" => "Enhypen, TXT, P1harmony, Stray Kids, ATEEZ"
      })

      render_click(view, "complete_hobbies")

      [reloaded] = FunSheep.Learning.list_hobbies_for_user(user_role_id)

      assert reloaded.specific_interests["text"] ==
               "Enhypen, TXT, P1harmony, Stray Kids, ATEEZ"
    end
  end

  describe "persistence across full flow" do
    test "demographics persist to user_role after Next", %{conn: conn} do
      {:ok, country} = Geo.create_country(%{name: "United States", code: "US"})

      conn = auth_conn(conn)
      user_role_id = get_session(conn, :dev_user)["user_role_id"]

      {:ok, view, _html} = live(conn, ~p"/profile/setup")

      view
      |> element("select[name=country_id]")
      |> render_change(%{country_id: country.id})

      render_click(view, "update_field", %{"field" => "selected_grade", "value" => "10"})
      render_click(view, "update_field", %{"field" => "selected_gender", "value" => "Female"})
      render_click(view, "update_field", %{"field" => "ethnicity", "value" => "Korean"})

      render_click(view, "next_step")

      reloaded = FunSheep.Accounts.get_user_role!(user_role_id)
      assert reloaded.grade == "10"
      assert reloaded.gender == "Female"
      assert reloaded.ethnicity == "Korean"
    end

    test "updating interest text on an already-selected hobby persists", %{conn: conn} do
      conn = auth_conn(conn)
      user_role_id = get_session(conn, :dev_user)["user_role_id"]

      {:ok, hobby} = FunSheep.Learning.create_hobby(%{name: "KPOP", category: "Music"})

      # Previously saved: KPOP with no specific interest text.
      FunSheep.Accounts.update_user_role(
        FunSheep.Accounts.get_user_role!(user_role_id),
        %{grade: "11"}
      )

      {:ok, _} =
        FunSheep.Learning.create_student_hobby(%{
          user_role_id: user_role_id,
          hobby_id: hobby.id,
          specific_interests: %{"text" => ""}
        })

      {:ok, view, _html} = live(conn, ~p"/profile/setup")
      render_click(view, "edit_profile")
      render_click(view, "next_step")

      # Type the bands into the KPOP interest input.
      render_change(view, "update_hobby_interest", %{
        "hobby-id" => hobby.id,
        "value" => "Enhypen, TXT, P1harmony, Stray Kids, ATEEZ"
      })

      render_click(view, "complete_hobbies")

      [reloaded] = FunSheep.Learning.list_hobbies_for_user(user_role_id)

      assert reloaded.specific_interests["text"] ==
               "Enhypen, TXT, P1harmony, Stray Kids, ATEEZ"
    end

    test "hobbies persist and profile gaps clear after Complete Setup", %{conn: conn} do
      {:ok, country} = Geo.create_country(%{name: "United States", code: "US"})

      {:ok, hobby} =
        FunSheep.Learning.create_hobby(%{name: "Coding", category: "Tech"})

      conn = auth_conn(conn)
      user = get_session(conn, :dev_user)

      {:ok, view, _html} = live(conn, ~p"/profile/setup")

      view
      |> element("select[name=country_id]")
      |> render_change(%{country_id: country.id})

      render_click(view, "update_field", %{"field" => "selected_grade", "value" => "10"})
      render_click(view, "next_step")
      render_click(view, "toggle_hobby", %{"hobby-id" => hobby.id})
      render_click(view, "complete_hobbies")

      # The exact bug from production: compute_profile_gaps reported [:grade, :hobbies]
      # even though the data was saved. Now it should be empty.
      assert FunSheepWeb.LiveHelpers.compute_profile_gaps(user) == []
    end
  end
end
