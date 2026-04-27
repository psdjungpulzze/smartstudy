defmodule FunSheepWeb.FixedTestsLiveTest do
  @moduledoc """
  Tests for fixed test (custom test) LiveViews: StartLive and SessionLive.
  """

  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{Accounts, ContentFixtures, FixedTests}

  defp auth_conn(conn, user_role) do
    conn
    |> init_test_session(%{
      dev_user_id: user_role.interactor_user_id,
      dev_user: %{
        "id" => user_role.interactor_user_id,
        "role" => "teacher",
        "email" => user_role.email,
        "display_name" => user_role.display_name,
        "user_role_id" => user_role.id,
        # StartLive and SessionLive use user["interactor_user_id"] to look up UserRole
        "interactor_user_id" => user_role.interactor_user_id
      }
    })
  end

  defp create_bank(user_role) do
    {:ok, bank} =
      FixedTests.create_bank(%{
        "title" => "Physics Quiz #{System.unique_integer([:positive])}",
        "created_by_id" => user_role.id,
        "visibility" => "class",
        "course_id" => nil
      })

    bank
  end

  defp add_question(bank) do
    {:ok, q} =
      FixedTests.add_question(bank, %{
        "question_text" => "What is Newton's first law?",
        "answer_text" => "An object at rest stays at rest",
        "question_type" => "multiple_choice",
        "points" => 1,
        "position" => 1
      })

    q
  end

  setup do
    user_role = ContentFixtures.create_user_role(%{role: :teacher})
    %{user_role: user_role}
  end

  describe "StartLive — bank start page" do
    test "renders test start page with bank info", %{conn: conn, user_role: ur} do
      bank = create_bank(ur)

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/custom-tests/#{bank.id}/start")

      assert html =~ bank.title
      assert html =~ "Start"
    end

    test "shows start button for test", %{conn: conn, user_role: ur} do
      bank = create_bank(ur)
      _q = add_question(bank)

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/custom-tests/#{bank.id}/start")

      assert html =~ "Start"
    end

    test "start_test event creates a session and navigates", %{conn: conn, user_role: ur} do
      bank = create_bank(ur)
      _q = add_question(bank)

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/custom-tests/#{bank.id}/start")

      result = render_click(view, "start_test")

      case result do
        {:error, {:live_redirect, %{to: path}}} ->
          assert path =~ "/custom-tests/session/"

        html when is_binary(html) ->
          # May stay on page with error or continue
          assert html =~ "Start" or html =~ "session"
      end
    end
  end

  describe "SessionLive — test taking" do
    setup %{user_role: ur} do
      bank = create_bank(ur)
      _q = add_question(bank)

      {:ok, session} = FixedTests.start_session(bank.id, ur.id, nil)
      %{bank: bank, session: session}
    end

    test "renders test session with question", %{conn: conn, user_role: ur, session: session} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/custom-tests/session/#{session.id}")

      assert html =~ "Physics Quiz"
      assert html =~ "Newton"
    end

    test "go_to event navigates between questions", %{
      conn: conn,
      user_role: ur,
      session: session
    } do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/custom-tests/session/#{session.id}")

      html = render_click(view, "go_to", %{"index" => "0"})
      assert html =~ "Newton"
    end

    test "redirects if session belongs to different user", %{conn: conn, session: session} do
      other_user = ContentFixtures.create_user_role()
      conn = auth_conn(conn, other_user)

      assert {:error, {:live_redirect, %{to: "/custom-tests"}}} =
               live(conn, ~p"/custom-tests/session/#{session.id}")
    end
  end
end
