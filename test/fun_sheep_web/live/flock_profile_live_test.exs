defmodule FunSheepWeb.FlockProfileLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.ContentFixtures

  # FlockProfileLive uses current_user["id"] as viewer_id in Social queries (needs UUID).
  # Use user_role.id (binary_id UUID) so Social.follow_state/2 can cast it correctly.
  defp auth_conn(conn, user_role) do
    conn
    |> init_test_session(%{
      dev_user_id: user_role.id,
      dev_user: %{
        "id" => user_role.id,
        "role" => "student",
        "email" => user_role.email,
        "display_name" => user_role.display_name,
        "user_role_id" => user_role.id
      }
    })
  end

  setup do
    viewer = FunSheep.ContentFixtures.create_user_role()
    profile = FunSheep.ContentFixtures.create_user_role()
    %{viewer: viewer, profile: profile}
  end

  describe "mount" do
    test "renders profile page with display name", %{conn: conn, viewer: viewer, profile: profile} do
      conn = auth_conn(conn, viewer)
      {:ok, _view, html} = live(conn, ~p"/flock/#{profile.id}")

      assert html =~ profile.display_name || "?"
    end

    test "renders follower and following counts", %{conn: conn, viewer: viewer, profile: profile} do
      conn = auth_conn(conn, viewer)
      {:ok, _view, html} = live(conn, ~p"/flock/#{profile.id}")

      assert html =~ "Followers"
      assert html =~ "Following"
    end

    test "shows Follow button when viewing another user", %{
      conn: conn,
      viewer: viewer,
      profile: profile
    } do
      conn = auth_conn(conn, viewer)
      {:ok, _view, html} = live(conn, ~p"/flock/#{profile.id}")

      assert html =~ "Follow"
    end

    test "shows Edit Profile button when viewing own profile", %{conn: conn, viewer: viewer} do
      conn = auth_conn(conn, viewer)
      {:ok, _view, html} = live(conn, ~p"/flock/#{viewer.id}")

      assert html =~ "Edit Profile"
    end

    test "shows streak, FP, and badges stats", %{conn: conn, viewer: viewer, profile: profile} do
      conn = auth_conn(conn, viewer)
      {:ok, _view, html} = live(conn, ~p"/flock/#{profile.id}")

      assert html =~ "Day Streak"
      assert html =~ "Total FP"
      assert html =~ "Badges"
    end

    test "shows back link to leaderboard", %{conn: conn, viewer: viewer, profile: profile} do
      conn = auth_conn(conn, viewer)
      {:ok, _view, html} = live(conn, ~p"/flock/#{profile.id}")

      assert html =~ "Back to Flock"
      assert html =~ "/leaderboard"
    end

    test "redirects to leaderboard for non-existent user", %{conn: conn, viewer: viewer} do
      conn = auth_conn(conn, viewer)
      fake_id = Ecto.UUID.generate()

      result = live(conn, ~p"/flock/#{fake_id}")
      assert {:error, {:live_redirect, %{to: "/leaderboard"}}} = result
    end
  end

  describe "follow/unfollow events" do
    test "follow event updates follow state", %{conn: conn, viewer: viewer, profile: profile} do
      conn = auth_conn(conn, viewer)
      {:ok, view, _html} = live(conn, ~p"/flock/#{profile.id}")

      html = render_click(view, "follow")
      assert html =~ "Following" or html =~ "Friends"
    end

    test "unfollow event after following reverts state", %{
      conn: conn,
      viewer: viewer,
      profile: profile
    } do
      FunSheep.Social.follow(viewer.id, profile.id)
      conn = auth_conn(conn, viewer)
      {:ok, view, _html} = live(conn, ~p"/flock/#{profile.id}")

      html = render_click(view, "unfollow")
      assert html =~ "Follow"
    end
  end

  describe "no badges state" do
    test "shows no badges earned message when user has no achievements", %{
      conn: conn,
      viewer: viewer,
      profile: profile
    } do
      conn = auth_conn(conn, viewer)
      {:ok, _view, html} = live(conn, ~p"/flock/#{profile.id}")

      assert html =~ "No badges earned yet"
    end
  end
end
