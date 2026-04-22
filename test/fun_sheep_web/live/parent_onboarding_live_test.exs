defmodule FunSheepWeb.ParentOnboardingLiveTest do
  @moduledoc """
  Flow B — LiveView tests for the 4-step parent onboarding wizard.
  """

  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts

  defp parent_conn(conn) do
    {:ok, user} =
      Accounts.create_user_role(%{
        interactor_user_id: "parent_#{System.unique_integer([:positive])}",
        role: :parent,
        email: "p_#{System.unique_integer([:positive])}@t.com",
        display_name: "Parent"
      })

    conn =
      init_test_session(conn, %{
        dev_user_id: user.id,
        dev_user: %{
          "id" => user.id,
          "user_role_id" => user.id,
          "interactor_user_id" => user.interactor_user_id,
          "role" => "parent",
          "email" => user.email,
          "display_name" => user.display_name
        }
      })

    {conn, user}
  end

  test "renders step 1 with the child-details form", %{conn: conn} do
    {conn, _user} = parent_conn(conn)
    {:ok, _view, html} = live(conn, ~p"/onboarding/parent")

    assert html =~ "Who are you studying for"
    # Apostrophe gets HTML-escaped — match the escaped form.
    assert html =~ "Child&#39;s name"
    assert html =~ "Add this child"
  end

  test "add_child populates the list", %{conn: conn} do
    {conn, _user} = parent_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/parent")

    # Specific selector to avoid the sign-out form in the layout.
    view
    |> form("form[phx-submit=add_child]", %{
      "display_name" => "Lia",
      "email" => "lia@t.com",
      "grade" => "5"
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Lia"
    assert html =~ "Grade 5"
  end

  test "Next button is disabled with no children", %{conn: conn} do
    {conn, _user} = parent_conn(conn)
    {:ok, _view, html} = live(conn, ~p"/onboarding/parent")

    # The "Next" button is rendered but disabled until a child has been added.
    assert html =~ ~r/disabled[^>]*>\s*Next — send invites/s
  end

  test "full wizard: add child → send invites → skip upfront → done", %{conn: conn} do
    {conn, _user} = parent_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/parent")

    # Add a child
    view
    |> form("form[phx-submit=add_child]", %{
      "display_name" => "Lia",
      "email" => "lia@t.com",
      "grade" => "5"
    })
    |> render_submit()

    # Advance to step 2
    view
    |> element("button[phx-click=goto_step][phx-value-step='2']")
    |> render_click()

    # Send invites → step 3
    view
    |> element("button", "Send invites")
    |> render_click()

    html = render(view)
    assert html =~ "Unlock now"
    assert html =~ "Claim code:"

    # Skip upfront → step 4
    view
    |> element("button", "Skip for now")
    |> render_click()

    html = render(view)
    # Apostrophe escaped as &#39;
    assert html =~ "You&#39;re set up"
    assert html =~ "Go to parent dashboard"
  end
end
