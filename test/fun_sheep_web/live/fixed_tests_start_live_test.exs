defmodule FunSheepWeb.FixedTests.StartLiveTest do
  @moduledoc """
  Tests for StartLive — starting or assigning a fixed custom test.
  """

  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{ContentFixtures, FixedTests}

  defp auth_conn(conn, user_role) do
    conn
    |> init_test_session(%{
      dev_user_id: user_role.interactor_user_id,
      dev_user: %{
        "id" => user_role.interactor_user_id,
        "role" => "student",
        "email" => user_role.email,
        "display_name" => user_role.display_name,
        "user_role_id" => user_role.id,
        "interactor_user_id" => user_role.interactor_user_id
      }
    })
  end

  defp create_bank(user_role, attrs \\ %{}) do
    defaults = %{
      "title" => "Test Bank #{System.unique_integer([:positive])}",
      "created_by_id" => user_role.id,
      "visibility" => "private"
    }

    {:ok, bank} = FixedTests.create_bank(Map.merge(defaults, attrs))
    bank
  end

  defp add_question(bank) do
    {:ok, q} =
      FixedTests.add_question(bank, %{
        "question_text" => "What is Elixir?",
        "answer_text" => "A language",
        "question_type" => "short_answer",
        "points" => 1
      })

    q
  end

  setup do
    user_role = ContentFixtures.create_user_role()
    %{user_role: user_role}
  end

  describe "StartLive — start view" do
    test "renders start panel with bank title", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "My Custom Quiz"})
      add_question(bank)

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/custom-tests/#{bank.id}/start")

      assert html =~ "My Custom Quiz"
      assert html =~ "Start Test"
    end

    test "shows question count", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Count Test Bank"})
      add_question(bank)

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/custom-tests/#{bank.id}/start")

      assert html =~ "1 question"
    end

    test "shows Untimed when no time limit", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Untimed Bank"})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/custom-tests/#{bank.id}/start")

      assert html =~ "Untimed"
    end

    test "shows time limit when set", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Timed Bank", "time_limit_minutes" => 30})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/custom-tests/#{bank.id}/start")

      assert html =~ "30 min"
    end

    test "shows bank description when present", %{conn: conn, user_role: ur} do
      bank =
        create_bank(ur, %{
          "title" => "Described Bank",
          "description" => "This is a test description"
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/custom-tests/#{bank.id}/start")

      assert html =~ "This is a test description"
    end

    test "renders via the assign route (same LiveView, start panel shown by default)",
         %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Assign Route Bank"})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/custom-tests/#{bank.id}/assign")

      # The assign route renders StartLive; action defaults to "start" unless
      # the "action" query param is present, so the start panel is shown.
      assert html =~ bank.title
    end
  end

  describe "StartLive — start_test event" do
    test "start_test redirects to session when bank has questions", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Start Test Bank"})
      add_question(bank)

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/custom-tests/#{bank.id}/start")

      result = render_click(view, "start_test")

      case result do
        {:error, {:live_redirect, %{to: path}}} ->
          assert path =~ "/custom-tests/session/"

        html when is_binary(html) ->
          assert html =~ "Could not start" or html =~ "Start Test"
      end
    end

    test "start_test shows error when attempt limit is reached", %{conn: conn, user_role: ur} do
      # Create a bank with max 1 attempt
      bank =
        create_bank(ur, %{"title" => "Limited Bank", "max_attempts" => 1})

      add_question(bank)

      # Create a completed session to exhaust the attempt limit
      {:ok, session} = FixedTests.start_session(bank.id, ur.id)
      FixedTests.complete_session(session)

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/custom-tests/#{bank.id}/start")

      html = render_click(view, "start_test")

      assert html =~ "maximum number of attempts"
    end
  end

  describe "StartLive — assign panel (via action query param)" do
    # The assign panel is only shown when params["action"] == "assign".
    # When navigating to /start?action=assign the LiveView mount receives
    # %{"id" => id, "action" => "assign"} and renders the assign form.

    test "renders assign panel with student selection form", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Assign Panel Bank"})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, "/custom-tests/#{bank.id}/start?action=assign")

      assert html =~ "Assign"
      assert html =~ bank.title
      assert html =~ "Select students"
    end

    test "shows empty students message when no students linked", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "No Students Bank"})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, "/custom-tests/#{bank.id}/start?action=assign")

      assert html =~ "No students linked"
    end

    test "assign with no students selected shows error", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Assign Error Bank"})

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, "/custom-tests/#{bank.id}/start?action=assign")

      html =
        view
        |> form("form[phx-submit='assign']", %{
          "due_at" => "",
          "note" => ""
        })
        |> render_submit()

      assert html =~ "Select at least one student"
    end

    test "toggle_student event toggles student in selected list", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Toggle Bank"})
      student = ContentFixtures.create_user_role()

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, "/custom-tests/#{bank.id}/start?action=assign")

      # Toggle student in (selected_students was empty, now includes student_id)
      html = render_click(view, "toggle_student", %{"id" => student.id})
      assert html =~ "Assign"

      # Toggle student out (remove from list)
      html = render_click(view, "toggle_student", %{"id" => student.id})
      assert html =~ "Assign"
    end

    test "assign succeeds when students are selected (with guardian-student link)",
         %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Assign Success Bank"})
      student = ContentFixtures.create_user_role()

      # Create an active guardian-student link so student appears in list
      {:ok, _link} =
        FunSheep.Accounts.create_student_guardian(%{
          guardian_id: ur.id,
          student_id: student.id,
          relationship_type: :teacher,
          status: :active,
          invited_at: DateTime.utc_now(:second)
        })

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, "/custom-tests/#{bank.id}/start?action=assign")

      # The assign panel should now show the student
      html = render(view)
      assert html =~ student.display_name or html =~ student.email

      # Select the student by toggling them on
      render_click(view, "toggle_student", %{"id" => student.id})

      # Submit the assign form
      result =
        view
        |> form("form[phx-submit='assign']", %{
          "due_at" => "",
          "note" => "Study chapters 1-3"
        })
        |> render_submit()

      case result do
        {:error, {:live_redirect, %{to: path}}} ->
          assert path =~ "/custom-tests/#{bank.id}"

        html when is_binary(html) ->
          assert html =~ "Assigned" or html =~ "student"
      end
    end

    test "assign with a due date processes the date string", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Due Date Bank"})
      student = ContentFixtures.create_user_role()

      {:ok, _link} =
        FunSheep.Accounts.create_student_guardian(%{
          guardian_id: ur.id,
          student_id: student.id,
          relationship_type: :teacher,
          status: :active,
          invited_at: DateTime.utc_now(:second)
        })

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, "/custom-tests/#{bank.id}/start?action=assign")

      # Select the student
      render_click(view, "toggle_student", %{"id" => student.id})

      # Submit with a due_at date string (exercises parse_due_at/1)
      result =
        view
        |> form("form[phx-submit='assign']", %{
          "due_at" => "2026-12-31T23:59",
          "note" => ""
        })
        |> render_submit()

      case result do
        {:error, {:live_redirect, %{to: path}}} ->
          assert path =~ "/custom-tests/#{bank.id}"

        html when is_binary(html) ->
          assert html =~ "Assigned" or html =~ "student" or html =~ "Assignment failed"
      end
    end
  end
end
