defmodule FunSheepWeb.WebhookCredentialEventTest do
  use FunSheepWeb.ConnCase, async: true

  alias FunSheep.Integrations

  setup do
    {:ok, user_role} =
      FunSheep.Accounts.create_user_role(%{
        interactor_user_id: "webhook_#{System.unique_integer([:positive])}",
        role: :student,
        email: "webhook_#{System.unique_integer([:positive])}@test.example",
        display_name: "Webhook Test"
      })

    {:ok, connection} =
      Integrations.create_connection(%{
        user_role_id: user_role.id,
        provider: :google_classroom,
        service_id: "google_classroom",
        external_user_id: user_role.interactor_user_id,
        credential_id: "cred_hook",
        status: :active
      })

    %{user_role: user_role, connection: connection}
  end

  test "credential.revoked flips connection to :revoked", %{conn: conn, connection: connection} do
    payload = %{
      "type" => "credential.revoked",
      "data" => %{"credential_id" => connection.credential_id}
    }

    conn = post(conn, ~p"/api/webhooks/interactor", payload)
    assert json_response(conn, 200) == %{"status" => "ok"}

    reloaded = Integrations.get_connection(connection.id)
    assert reloaded.status == :revoked
  end

  test "credential.expired flips to :expired", %{conn: conn, connection: connection} do
    payload = %{
      "type" => "credential.expired",
      "data" => %{"credential_id" => connection.credential_id}
    }

    conn = post(conn, ~p"/api/webhooks/interactor", payload)
    assert json_response(conn, 200) == %{"status" => "ok"}

    assert Integrations.get_connection(connection.id).status == :expired
  end

  test "credential.refreshed clears error + marks active", %{conn: conn, connection: connection} do
    {:ok, _} = Integrations.mark_errored(connection, "old error")

    payload = %{
      "type" => "credential.refreshed",
      "data" => %{"credential_id" => connection.credential_id}
    }

    _ = post(conn, ~p"/api/webhooks/interactor", payload)

    reloaded = Integrations.get_connection(connection.id)
    assert reloaded.status == :active
    assert reloaded.last_sync_error == nil
  end

  test "unknown credential_id is acknowledged without error", %{conn: conn} do
    payload = %{"type" => "credential.revoked", "data" => %{"credential_id" => "does_not_exist"}}

    conn = post(conn, ~p"/api/webhooks/interactor", payload)
    assert json_response(conn, 200)["status"] == "received"
  end
end
