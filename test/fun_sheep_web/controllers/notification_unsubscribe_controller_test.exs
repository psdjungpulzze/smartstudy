defmodule FunSheepWeb.NotificationUnsubscribeControllerTest do
  use FunSheepWeb.ConnCase, async: true

  alias FunSheep.Notifications.UnsubscribeToken
  alias FunSheep.Repo
  alias FunSheep.Accounts.UserRole
  alias FunSheep.ContentFixtures

  test "flips digest_frequency to :off on a valid token", %{conn: conn} do
    parent = ContentFixtures.create_user_role(%{role: :parent, digest_frequency: :weekly})

    token = UnsubscribeToken.mint(parent.id)
    conn = get(conn, ~p"/notifications/unsubscribe/#{token}")

    assert conn.status == 200
    assert conn.resp_body =~ "unsubscribed"

    updated = Repo.get!(UserRole, parent.id)
    assert updated.digest_frequency == :off
  end

  test "returns a friendly message for invalid tokens", %{conn: conn} do
    conn = get(conn, ~p"/notifications/unsubscribe/not-real")
    assert conn.status == 200
    assert conn.resp_body =~ "isn't valid"
  end
end
