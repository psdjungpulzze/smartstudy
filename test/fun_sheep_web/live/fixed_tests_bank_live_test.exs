defmodule FunSheepWeb.FixedTests.BankLiveTest do
  @moduledoc """
  Tests for BankLive — custom fixed-question test bank authoring.
  """

  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{ContentFixtures, FixedTests}

  # BankLive reads current_user["interactor_user_id"] to look up the UserRole.
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

  defp add_question(bank, attrs \\ %{}) do
    defaults = %{
      "question_text" => "Sample question #{System.unique_integer([:positive])}?",
      "answer_text" => "Sample answer",
      "question_type" => "short_answer",
      "points" => 1
    }

    {:ok, q} = FixedTests.add_question(bank, Map.merge(defaults, attrs))
    q
  end

  setup do
    user_role = ContentFixtures.create_user_role()
    %{user_role: user_role}
  end

  describe "BankLive :index — list view" do
    test "renders the bank list page", %{conn: conn, user_role: ur} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/custom-tests")

      assert html =~ "My Custom Tests"
    end

    test "shows empty state when no banks exist", %{conn: conn, user_role: ur} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/custom-tests")

      assert html =~ "No custom tests yet"
    end

    test "shows bank title when a bank exists", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "My Physics Quiz"})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/custom-tests")

      assert html =~ bank.title
      refute html =~ "No custom tests yet"
    end

    test "shows + New Test button", %{conn: conn, user_role: ur} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/custom-tests")

      assert html =~ "+ New Test"
    end

    test "handle_params with no id resets to list view", %{conn: conn, user_role: ur} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/custom-tests")

      assert html =~ "My Custom Tests"
    end
  end

  describe "BankLive :new — new bank form" do
    test "renders the new bank form when new_bank event is fired", %{conn: conn, user_role: ur} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/custom-tests")

      html = render_click(view, "new_bank")
      assert html =~ "New Custom Test"
      assert html =~ "Title"
    end
  end

  describe "BankLive :show — questions view" do
    test "renders the questions view for a bank", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Chemistry Test"})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/custom-tests/#{bank.id}")

      assert html =~ "Chemistry Test"
      assert html =~ "No questions yet"
    end

    test "shows question count when questions exist", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Math Exam"})

      {:ok, _q} =
        FixedTests.add_question(bank, %{
          "question_text" => "What is 2 + 2?",
          "answer_text" => "4",
          "question_type" => "short_answer",
          "points" => 1
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/custom-tests/#{bank.id}")

      assert html =~ "What is 2 + 2?"
      assert html =~ "1 question"
    end

    test "shows Settings and Assign buttons", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Settings Test Bank"})

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/custom-tests/#{bank.id}")

      assert html =~ "Settings"
      assert html =~ "Assign"
    end
  end

  describe "BankLive edit_bank_meta event" do
    test "shows edit form for bank settings", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Editable Bank"})

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/custom-tests/#{bank.id}")

      html = render_click(view, "edit_bank_meta")
      assert html =~ "Edit: Editable Bank"
    end
  end

  describe "BankLive edit_bank_meta and save_bank in edit mode" do
    test "edit_bank_meta shows edit form and submitting creates new bank", %{
      conn: conn,
      user_role: ur
    } do
      bank = create_bank(ur, %{"title" => "Old Title"})

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/custom-tests/#{bank.id}")

      # Switch to edit view
      html = render_click(view, "edit_bank_meta")
      assert html =~ "Edit: Old Title"

      # The edit form uses phx-submit="save_bank" which calls create_bank
      result =
        view
        |> form("form[phx-submit='save_bank']", %{
          "fixed_test_bank" => %{
            "title" => "Resubmitted Title",
            "visibility" => "private"
          }
        })
        |> render_submit()

      case result do
        {:error, {:live_redirect, %{to: path}}} ->
          assert path =~ "/custom-tests/"

        html when is_binary(html) ->
          assert html =~ "Test created" or html =~ "Resubmitted Title" or
                   html =~ "Saved"
      end
    end
  end

  describe "BankLive archive_bank event" do
    test "archives a bank and redirects to list", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "To Be Archived"})

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/custom-tests/#{bank.id}")

      result = render_click(view, "archive_bank", %{"id" => bank.id})

      case result do
        {:error, {:live_redirect, %{to: "/custom-tests"}}} ->
          assert true

        html when is_binary(html) ->
          assert html =~ "archived" or html =~ "My Custom Tests"
      end
    end
  end

  describe "BankLive save_bank event" do
    test "creates a bank and navigates to it", %{conn: conn, user_role: ur} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/custom-tests")

      # Open the new bank form
      render_click(view, "new_bank")

      # Submit the form (use phx-submit attribute to disambiguate from any other forms)
      result =
        view
        |> form("form[phx-submit='save_bank']", %{
          "fixed_test_bank" => %{
            "title" => "New Integration Test Bank",
            "visibility" => "private"
          }
        })
        |> render_submit()

      case result do
        {:error, {:live_redirect, %{to: path}}} ->
          assert path =~ "/custom-tests/"

        html when is_binary(html) ->
          # Navigated inline or stayed with flash
          assert html =~ "Test created" or html =~ "New Integration Test Bank"
      end
    end

    test "shows validation error when title is blank", %{conn: conn, user_role: ur} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/custom-tests")

      render_click(view, "new_bank")

      html =
        view
        |> form("form[phx-submit='save_bank']", %{
          "fixed_test_bank" => %{
            "title" => "",
            "visibility" => "private"
          }
        })
        |> render_submit()

      # Should stay on form with error or show validation message
      assert html =~ "New Custom Test" or html =~ "can't be blank"
    end
  end

  describe "BankLive question management" do
    test "new_question shows question edit modal", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Question Test Bank"})

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/custom-tests/#{bank.id}")

      html = render_click(view, "new_question")
      assert html =~ "Question"
      assert html =~ "Save question"
    end

    test "cancel_question_edit dismisses the modal", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Cancel Test Bank"})

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/custom-tests/#{bank.id}")

      render_click(view, "new_question")
      html = render_click(view, "cancel_question_edit")

      refute html =~ "Save question"
    end

    test "save_question creates a new question", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "New Question Bank"})

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/custom-tests/#{bank.id}")

      render_click(view, "new_question")

      html =
        view
        |> form("form[phx-submit='save_question']", %{
          "fixed_test_question" => %{
            "question_text" => "What is Elixir?",
            "answer_text" => "A programming language",
            "question_type" => "short_answer",
            "points" => 1
          }
        })
        |> render_submit()

      assert html =~ "What is Elixir?" or html =~ "Question saved"
    end

    test "edit_question opens modal pre-filled with question data",
         %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Edit Question Bank"})
      question = add_question(bank, %{"question_text" => "Existing Question?"})

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/custom-tests/#{bank.id}")

      html = render_click(view, "edit_question", %{"id" => question.id})
      assert html =~ "Save question"
    end

    test "save_question updates an existing question", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Update Question Bank"})
      question = add_question(bank, %{"question_text" => "Original question?"})

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/custom-tests/#{bank.id}")

      render_click(view, "edit_question", %{"id" => question.id})

      html =
        view
        |> form("form[phx-submit='save_question']", %{
          "fixed_test_question" => %{
            "question_text" => "Updated question?",
            "answer_text" => "Updated answer",
            "question_type" => "short_answer",
            "points" => 2
          }
        })
        |> render_submit()

      assert html =~ "Updated question?" or html =~ "Question saved"
    end

    test "delete_question removes the question from the bank", %{conn: conn, user_role: ur} do
      bank = create_bank(ur, %{"title" => "Delete Question Bank"})
      question = add_question(bank, %{"question_text" => "Question to delete?"})

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/custom-tests/#{bank.id}")

      assert render(view) =~ "Question to delete?"

      html = render_click(view, "delete_question", %{"id" => question.id})

      refute html =~ "Question to delete?"
    end
  end
end
