defmodule FunSheepWeb.LeaderboardLiveShoutOutsTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts
  alias FunSheep.Gamification.ShoutOut

  defp user_role_conn(conn, attrs \\ %{}) do
    defaults = %{
      interactor_user_id: "leaderboard_so_#{System.unique_integer([:positive])}",
      role: :student,
      email: "lbso_#{System.unique_integer([:positive])}@test.com",
      display_name: "Shout Out Tester"
    }

    {:ok, user_role} = Accounts.create_user_role(Map.merge(defaults, attrs))

    conn =
      init_test_session(conn, %{
        dev_user_id: user_role.id,
        dev_user: %{
          "id" => user_role.id,
          "role" => "student",
          "email" => user_role.email,
          "display_name" => user_role.display_name
        }
      })

    {conn, user_role}
  end

  defp insert_shout_out(user_role, category, value, period_start \\ nil) do
    today = Date.utc_today()
    week_start = period_start || compute_week_start(today)

    {:ok, shout_out} =
      %ShoutOut{}
      |> ShoutOut.changeset(%{
        category: category,
        period: "weekly",
        period_start: week_start,
        period_end: Date.add(week_start, 7),
        metric_value: value,
        user_role_id: user_role.id
      })
      |> FunSheep.Repo.insert()

    shout_out
  end

  describe "Shout Outs tab" do
    test "shout_outs tab button is visible on the leaderboard page", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/leaderboard")

      assert html =~ "Shout Outs"
    end

    test "switching to shout_outs tab renders the tab content", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/leaderboard")

      html = view |> element("button[phx-value-tab='shout_outs']") |> render_click()

      assert html =~ "This Week&#39;s Stars" or html =~ "This Week's Stars"
    end

    test "empty state is shown when no shout outs exist for current week", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/leaderboard")

      html = view |> element("button[phx-value-tab='shout_outs']") |> render_click()

      # Empty state message
      assert html =~ "No shout outs yet this week"
    end

    test "shout out cards render when data exists", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)
      insert_shout_out(user_role, "most_xp", 750)

      {:ok, view, _html} = live(conn, ~p"/leaderboard")
      html = view |> element("button[phx-value-tab='shout_outs']") |> render_click()

      # Category label for most_xp
      assert html =~ "Most Active"
      assert html =~ "⚡"
      assert html =~ "750"
    end

    test "shows 'That's you!' badge when the current user is a winner", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)
      insert_shout_out(user_role, "longest_streak", 14)

      {:ok, view, _html} = live(conn, ~p"/leaderboard")
      html = view |> element("button[phx-value-tab='shout_outs']") |> render_click()

      assert html =~ "That&#39;s you!" or html =~ "That's you!"
    end

    test "does not show 'That's you!' badge for other winners", %{conn: conn} do
      {conn, current_user_role} = user_role_conn(conn)

      # Another user wins
      {:ok, other_user} =
        Accounts.create_user_role(%{
          interactor_user_id: "other_so_#{System.unique_integer([:positive])}",
          role: :student,
          email: "other_so_#{System.unique_integer([:positive])}@test.com",
          display_name: "Other Winner"
        })

      insert_shout_out(other_user, "most_tests_taken", 50)

      # Current user is not winning any shout out
      {:ok, view, _html} = live(conn, ~p"/leaderboard")
      html = view |> element("button[phx-value-tab='shout_outs']") |> render_click()

      # Winner card renders but no "That's you!" badge
      assert html =~ "Test Taker"
      refute html =~ "That&#39;s you!"
      refute html =~ "That's you!"

      # Suppress "unused variable" warning
      _ = current_user_role
    end

    test "tab switch between leaderboard and shout_outs works", %{conn: conn} do
      {conn, _user_role} = user_role_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/leaderboard")

      # Switch to shout outs
      html_so = view |> element("button[phx-value-tab='shout_outs']") |> render_click()
      assert html_so =~ "This Week&#39;s Stars" or html_so =~ "This Week's Stars"

      # Switch back to leaderboard
      html_lb = view |> element("button[phx-value-tab='leaderboard']") |> render_click()
      assert html_lb =~ "Leaderboard" or html_lb =~ "The Flock"
    end

    test "multiple shout out categories display correctly", %{conn: conn} do
      {conn, user_role} = user_role_conn(conn)

      insert_shout_out(user_role, "most_xp", 1000)
      insert_shout_out(user_role, "most_tests_taken", 25)
      insert_shout_out(user_role, "longest_streak", 7)

      {:ok, view, _html} = live(conn, ~p"/leaderboard")
      html = view |> element("button[phx-value-tab='shout_outs']") |> render_click()

      assert html =~ "Most Active"
      assert html =~ "Test Taker"
      assert html =~ "Streak Star"
    end
  end

  # Helper replicating the week-start logic in the context
  defp compute_week_start(today) do
    case Date.day_of_week(today, :monday) do
      1 -> today
      n -> Date.add(today, -(n - 1))
    end
  end
end
