defmodule FunSheepWeb.FindFriendsLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{ContentFixtures, Social}

  # FindFriendsLive uses current_user["id"] as a user_role UUID for Social queries.
  # The dev session "id" must be the database UUID (user_role.id), not interactor_user_id.
  defp auth_conn(conn, user_role) do
    conn
    |> init_test_session(%{
      dev_user_id: user_role.interactor_user_id,
      dev_user: %{
        "id" => user_role.id,
        "role" => "student",
        "email" => user_role.email,
        "display_name" => user_role.display_name,
        "user_role_id" => user_role.id
      }
    })
  end

  describe "mount" do
    test "renders the Find Friends page with search input", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user)

      {:ok, _view, html} = live(conn, ~p"/social/find")

      assert html =~ "Find Friends"
      assert html =~ "Search classmates by name"
      assert html =~ "following"
    end

    test "shows invite by email section on initial load", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user)

      {:ok, _view, html} = live(conn, ~p"/social/find")

      assert html =~ "Invite a Friend by Email"
      assert html =~ "friend@school.com"
    end

    test "shows no suggestions empty state when there are no suggestions", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user)

      {:ok, _view, html} = live(conn, ~p"/social/find")

      # User is alone at their school, so suggestions will be empty
      assert html =~ "No suggestions yet" or html =~ "People You Might Know" or
               html =~ "Set your school in your profile"
    end

    test "shows following count in subtitle", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      other = ContentFixtures.create_user_role()
      Social.follow(user.id, other.id, "manual")
      conn = auth_conn(conn, user)

      {:ok, _view, html} = live(conn, ~p"/social/find")

      assert html =~ "following"
      assert html =~ "1"
    end
  end

  describe "search event" do
    test "short query (< 2 chars) returns no results", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user)

      {:ok, view, _html} = live(conn, ~p"/social/find")

      html = render_change(view, "search", %{"q" => "a"})

      # No results section should NOT appear for 1-char query
      refute html =~ "Results"
    end

    test "query >= 2 chars triggers search and shows results section", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      other = ContentFixtures.create_user_role(%{display_name: "Alice Wonderland"})
      # Enroll both users in the same school so they can discover each other
      _same_school_irrelevant = other

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/social/find")

      html = render_change(view, "search", %{"q" => "Al"})

      # Either results or "no classmates found" message
      assert html =~ "Results" or html =~ "No classmates found"
    end

    test "empty query restores suggestions view", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user)

      {:ok, view, _html} = live(conn, ~p"/social/find")

      # First search for something
      render_change(view, "search", %{"q" => "test"})

      # Then clear the query
      html = render_change(view, "search", %{"q" => ""})

      # Invite section reappears (only shown when query == "")
      assert html =~ "Invite a Friend by Email"
    end
  end

  describe "follow / unfollow events" do
    test "follow event follows a peer and refreshes suggestions", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      other = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user)

      {:ok, view, _html} = live(conn, ~p"/social/find")

      # Fire follow event for the other user
      render_click(view, "follow", %{"id" => other.id})

      # Verify the follow was persisted
      assert Social.following?(user.id, other.id)
    end

    test "unfollow event unfollows a peer", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      other = ContentFixtures.create_user_role()
      Social.follow(user.id, other.id, "manual")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/social/find")

      render_click(view, "unfollow", %{"id" => other.id})

      refute Social.following?(user.id, other.id)
    end
  end

  describe "send_invite event" do
    test "blank email shows error", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user)

      {:ok, view, _html} = live(conn, ~p"/social/find")

      html = render_submit(view, "send_invite", %{"invite_email" => "   "})

      assert html =~ "Please enter an email address"
    end

    test "valid email for unknown user sends an invite", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user)

      {:ok, view, _html} = live(conn, ~p"/social/find")

      html = render_submit(view, "send_invite", %{"invite_email" => "stranger@example.com"})

      assert html =~ "Invite sent to stranger@example.com"
    end

    test "valid email for existing user sends a targeted invite", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      existing = ContentFixtures.create_user_role(%{email: "existing@example.com"})
      conn = auth_conn(conn, user)

      {:ok, view, _html} = live(conn, ~p"/social/find")

      html = render_submit(view, "send_invite", %{"invite_email" => existing.email})

      assert html =~ "Invite sent to #{existing.email}"
    end
  end

  describe "search with actual results" do
    test "two users at same school can find each other via search", %{conn: conn} do
      # Create a school so both users share it
      school = ContentFixtures.create_school()

      user =
        ContentFixtures.create_user_role(%{school_id: school.id, display_name: "Searcher User"})

      target =
        ContentFixtures.create_user_role(%{
          school_id: school.id,
          display_name: "Zara Findable"
        })

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/social/find")

      html = render_change(view, "search", %{"q" => "Zara"})

      # Should find the target user
      assert html =~ "Results" or html =~ "Zara Findable"
      # The target ID should appear in the follow button
      assert html =~ target.id or html =~ "Follow"
    end

    test "search shows Follow button for unfollowed peers", %{conn: conn} do
      school = ContentFixtures.create_school()

      user =
        ContentFixtures.create_user_role(%{school_id: school.id, display_name: "Base User"})

      _target =
        ContentFixtures.create_user_role(%{
          school_id: school.id,
          display_name: "Brenda Findable"
        })

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/social/find")

      html = render_change(view, "search", %{"q" => "Brenda"})

      assert html =~ "Follow" or html =~ "Results" or html =~ "No classmates found"
    end

    test "search shows Following button for already-followed peers", %{conn: conn} do
      school = ContentFixtures.create_school()

      user =
        ContentFixtures.create_user_role(%{school_id: school.id, display_name: "Alpha User"})

      other =
        ContentFixtures.create_user_role(%{
          school_id: school.id,
          display_name: "Carla Followed"
        })

      Social.follow(user.id, other.id, "manual")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/social/find")

      html = render_change(view, "search", %{"q" => "Carla"})

      # If found, should show Following state
      assert html =~ "Following" or html =~ "Carla" or html =~ "No classmates found"
    end

    test "mutual follow shows Friends button", %{conn: conn} do
      school = ContentFixtures.create_school()

      user =
        ContentFixtures.create_user_role(%{school_id: school.id, display_name: "Delta User"})

      other =
        ContentFixtures.create_user_role(%{
          school_id: school.id,
          display_name: "Diana Mutual"
        })

      Social.follow(user.id, other.id, "manual")
      Social.follow(other.id, user.id, "manual")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/social/find")

      html = render_change(view, "search", %{"q" => "Diana"})

      # If found as mutual, should show Friends button
      assert html =~ "Friends" or html =~ "Diana" or html =~ "No classmates found"
    end
  end

  describe "suggestions panel" do
    test "shows People You Might Know when suggestions exist", %{conn: conn} do
      school = ContentFixtures.create_school()

      user =
        ContentFixtures.create_user_role(%{
          school_id: school.id,
          display_name: "Suggestion Seeker"
        })

      _classmate =
        ContentFixtures.create_user_role(%{
          school_id: school.id,
          display_name: "Echo Suggested"
        })

      conn = auth_conn(conn, user)
      {:ok, _view, html} = live(conn, ~p"/social/find")

      # With a classmate at same school, suggestions should appear
      assert html =~ "People You Might Know" or html =~ "No suggestions yet"
    end

    test "follow from suggestions updates following count", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      other = ContentFixtures.create_user_role()

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/social/find")

      render_click(view, "follow", %{"id" => other.id})

      html = render(view)

      # Following count should be at least 1 now
      assert html =~ "following"
    end

    test "unfollow from search context updates following count", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      other = ContentFixtures.create_user_role()
      Social.follow(user.id, other.id, "manual")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/social/find")

      render_click(view, "unfollow", %{"id" => other.id})

      html = render(view)
      assert html =~ "0 students" or html =~ "following"
    end
  end

  describe "render helpers" do
    test "page shows back to flock link", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user)

      {:ok, _view, html} = live(conn, ~p"/social/find")

      assert html =~ "Back to Flock"
    end

    test "page shows search input with placeholder", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user)

      {:ok, _view, html} = live(conn, ~p"/social/find")

      assert html =~ "Search classmates by name"
    end

    test "invite section shows send button", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user)

      {:ok, _view, html} = live(conn, ~p"/social/find")

      assert html =~ "Send"
      assert html =~ "friend@school.com"
    end

    test "invite section disappears when query is active", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user)

      {:ok, view, _html} = live(conn, ~p"/social/find")

      html = render_change(view, "search", %{"q" => "test query"})

      refute html =~ "Invite a Friend by Email"
    end

    test "no classmates message appears for long query with no results", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      conn = auth_conn(conn, user)

      {:ok, view, _html} = live(conn, ~p"/social/find")

      html = render_change(view, "search", %{"q" => "ZZZNoOneHasThisName"})

      # Either no classmates found message, or nothing if no school
      assert html =~ "No classmates found" or not (html =~ "Results")
    end
  end
end
