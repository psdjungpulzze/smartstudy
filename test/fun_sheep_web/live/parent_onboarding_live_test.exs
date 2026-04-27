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

  # ── Additional coverage tests ────────────────────────────────────────────

  test "update_draft event keeps the form populated", %{conn: conn} do
    {conn, _user} = parent_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/parent")

    html =
      view
      |> form("form[phx-submit=add_child]", %{
        "display_name" => "Draft Name",
        "email" => "",
        "grade" => "8"
      })
      |> render_change()

    assert html =~ "Who are you studying for"
  end

  test "add_child with empty name shows validation error", %{conn: conn} do
    {conn, _user} = parent_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/parent")

    html =
      view
      |> form("form[phx-submit=add_child]", %{"display_name" => "", "email" => "", "grade" => ""})
      |> render_submit()

    assert html =~ "Please enter the child&#39;s name" or html =~ "Please enter the child's name"
  end

  test "add_child with invalid email shows validation error", %{conn: conn} do
    {conn, _user} = parent_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/parent")

    html =
      view
      |> form("form[phx-submit=add_child]", %{
        "display_name" => "Kid",
        "email" => "notanemail",
        "grade" => "3"
      })
      |> render_submit()

    assert html =~ "email looks off"
  end

  test "remove_child removes the child from the list", %{conn: conn} do
    {conn, _user} = parent_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/parent")

    view
    |> form("form[phx-submit=add_child]", %{
      "display_name" => "RemoveMe",
      "email" => "removeme@t.com",
      "grade" => "7"
    })
    |> render_submit()

    html = render(view)
    assert html =~ "RemoveMe"

    render_click(view, "remove_child", %{"index" => "0"})

    html = render(view)
    refute html =~ "RemoveMe"
  end

  test "goto_step 2 without children shows error", %{conn: conn} do
    {conn, _user} = parent_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/parent")

    html = render_click(view, "goto_step", %{"step" => "2"})
    assert html =~ "Add at least one child first"
  end

  test "send_invites with no children shows error", %{conn: conn} do
    {conn, _user} = parent_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/parent")

    html = render_click(view, "send_invites", %{})
    assert html =~ "Add at least one child first"
  end

  test "add child without email generates a claim code only path", %{conn: conn} do
    {conn, _user} = parent_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/parent")

    view
    |> form("form[phx-submit=add_child]", %{
      "display_name" => "NoEmail Kid",
      "email" => "",
      "grade" => "4"
    })
    |> render_submit()

    view
    |> element("button[phx-click=goto_step][phx-value-step='2']")
    |> render_click()

    view
    |> element("button", "Send invites")
    |> render_click()

    html = render(view)
    assert html =~ "Claim code:"
  end

  test "step_two shows claim code only note when no child email", %{conn: conn} do
    {conn, _user} = parent_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/parent")

    view
    |> form("form[phx-submit=add_child]", %{
      "display_name" => "NoEmailKid",
      "email" => "",
      "grade" => "6"
    })
    |> render_submit()

    html =
      view
      |> element("button[phx-click=goto_step][phx-value-step='2']")
      |> render_click()

    assert html =~ "Claim code only"
  end

  test "done step shows children count message", %{conn: conn} do
    {conn, _user} = parent_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/parent")

    view
    |> form("form[phx-submit=add_child]", %{
      "display_name" => "One Child",
      "email" => "onechild@t.com",
      "grade" => "3"
    })
    |> render_submit()

    view
    |> element("button[phx-click=goto_step][phx-value-step='2']")
    |> render_click()

    view
    |> element("button", "Send invites")
    |> render_click()

    view
    |> element("button", "Skip for now")
    |> render_click()

    html = render(view)
    # child noun (singular)
    assert html =~ "child"
    assert html =~ "has been invited"
  end

  test "progress header shows onboarding step labels", %{conn: conn} do
    {conn, _user} = parent_conn(conn)
    {:ok, _view, html} = live(conn, ~p"/onboarding/parent")

    assert html =~ "Child details"
    assert html =~ "Send invites"
    assert html =~ "Unlock now"
    assert html =~ "Done"
  end
end
