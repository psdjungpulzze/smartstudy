defmodule FunSheepWeb.ClaimCodeLiveTest do
  @moduledoc """
  Flow B — tests for `/claim/:code` redemption UI.
  """

  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts
  alias FunSheep.InviteCodes

  defp student_conn(conn) do
    {:ok, user} =
      Accounts.create_user_role(%{
        interactor_user_id: "student_#{System.unique_integer([:positive])}",
        role: :student,
        email: "s_#{System.unique_integer([:positive])}@t.com",
        display_name: "Kid"
      })

    conn =
      init_test_session(conn, %{
        dev_user_id: user.id,
        dev_user: %{
          "id" => user.id,
          "role" => "student",
          "email" => user.email,
          "display_name" => user.display_name
        }
      })

    {conn, user}
  end

  defp create_parent_invite do
    {:ok, parent} =
      Accounts.create_user_role(%{
        interactor_user_id: "parent_#{System.unique_integer([:positive])}",
        role: :parent,
        email: "p_#{System.unique_integer([:positive])}@t.com",
        display_name: "Mom"
      })

    {:ok, invite} =
      InviteCodes.create(parent.id, %{
        relationship_type: :parent,
        child_display_name: "Kid"
      })

    {parent, invite}
  end

  test "shows not-found for an unknown code", %{conn: conn} do
    {conn, _student} = student_conn(conn)
    {:ok, _view, html} = live(conn, ~p"/claim/ZZZZZZZZ")
    assert html =~ "Code not found"
  end

  test "shows expired UI for a redeemed code", %{conn: conn} do
    {_parent, invite} = create_parent_invite()
    {conn, student} = student_conn(conn)

    {:ok, _} = InviteCodes.redeem(invite.code, student)

    {:ok, _view, html} = live(conn, ~p"/claim/#{invite.code}")
    assert html =~ "already been used or expired"
  end

  test "signed-in student can redeem and sees success UI", %{conn: conn} do
    {_parent, invite} = create_parent_invite()
    {conn, _student} = student_conn(conn)

    {:ok, view, _html} = live(conn, ~p"/claim/#{invite.code}")

    view
    |> element("button", "Accept invite")
    |> render_click()

    html = render(view)
    assert html =~ "You&#39;re all set"
  end
end
