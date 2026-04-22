defmodule FunSheepWeb.IntegrationsLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.Integrations

  defp user_role_fixture do
    {:ok, user_role} =
      FunSheep.Accounts.create_user_role(%{
        interactor_user_id: "il_#{System.unique_integer([:positive])}",
        role: :student,
        email: "il_#{System.unique_integer([:positive])}@test.example",
        display_name: "Test Student"
      })

    user_role
  end

  defp auth(conn, user_role) do
    init_test_session(conn, %{
      dev_user_id: user_role.id,
      dev_user: %{
        "id" => user_role.id,
        "user_role_id" => user_role.id,
        "role" => "student",
        "email" => user_role.email,
        "display_name" => "Test Student",
        "interactor_user_id" => user_role.interactor_user_id
      }
    })
  end

  describe "mount/render" do
    test "renders three provider cards by default", %{conn: conn} do
      user_role = user_role_fixture()

      {:ok, _view, html} =
        conn
        |> auth(user_role)
        |> live(~p"/integrations")

      assert html =~ "Connected apps"
      assert html =~ "Google Classroom"
      assert html =~ "Canvas LMS"
      assert html =~ "ParentSquare"
      assert html =~ "Coming soon"
    end

    test "shows a Connect button for supported providers when disconnected",
         %{conn: conn} do
      user_role = user_role_fixture()

      {:ok, _view, html} =
        conn
        |> auth(user_role)
        |> live(~p"/integrations")

      assert html =~ "/integrations/connect/google_classroom"
      assert html =~ "Not connected"
    end

    test "renders existing connection status and disconnect button", %{conn: conn} do
      user_role = user_role_fixture()

      {:ok, _connection} =
        Integrations.create_connection(%{
          user_role_id: user_role.id,
          provider: :google_classroom,
          service_id: "google_classroom",
          external_user_id: user_role.interactor_user_id,
          credential_id: "cred_live",
          status: :active,
          last_sync_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, _view, html} =
        conn
        |> auth(user_role)
        |> live(~p"/integrations")

      assert html =~ "Connected"
      assert html =~ "Disconnect"
      assert html =~ "Sync now"
      assert html =~ "Last synced"
    end

    test "live-updates when Integrations broadcasts a new event", %{conn: conn} do
      user_role = user_role_fixture()

      {:ok, connection} =
        Integrations.create_connection(%{
          user_role_id: user_role.id,
          provider: :canvas,
          service_id: "canvas",
          external_user_id: user_role.interactor_user_id,
          credential_id: "cred_canvas",
          status: :syncing
        })

      {:ok, view, _html} =
        conn
        |> auth(user_role)
        |> live(~p"/integrations")

      refute render(view) =~ "sync_failed_example"

      {:ok, errored} = Integrations.mark_errored(connection, "sync_failed_example")
      Integrations.broadcast(errored, :error, %{reason: "sync_failed_example"})

      assert render(view) =~ "sync_failed_example"
    end
  end
end
