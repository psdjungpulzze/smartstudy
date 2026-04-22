defmodule FunSheepWeb.IntegrationControllerTest do
  use FunSheepWeb.ConnCase, async: true

  alias FunSheep.Integrations

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

  defp user_role_fixture do
    {:ok, user_role} =
      FunSheep.Accounts.create_user_role(%{
        interactor_user_id: "ic_interactor_#{System.unique_integer([:positive])}",
        role: :student,
        email: "ic_#{System.unique_integer([:positive])}@test.example",
        display_name: "Test Student"
      })

    user_role
  end

  describe "GET /integrations/connect/:provider" do
    test "redirects to the mock callback in mock mode", %{conn: conn} do
      user_role = user_role_fixture()

      conn =
        conn
        |> auth(user_role)
        |> get(~p"/integrations/connect/google_classroom")

      assert redirected_to(conn) =~ "/integrations/callback"
      assert redirected_to(conn) =~ "google_classroom"
    end

    test "shows 'coming soon' flash for unsupported providers", %{conn: conn} do
      user_role = user_role_fixture()

      conn =
        conn
        |> auth(user_role)
        |> get(~p"/integrations/connect/parentsquare")

      assert redirected_to(conn) == "/integrations"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "coming soon"
    end

    test "redirects unauthenticated users to login", %{conn: conn} do
      conn = get(conn, ~p"/integrations/connect/google_classroom")
      assert redirected_to(conn) == "/dev/login"
    end
  end

  describe "GET /integrations/callback" do
    test "upserts a connection and enqueues sync", %{conn: conn} do
      user_role = user_role_fixture()

      original = Application.get_env(:fun_sheep, :integrations_provider_modules, %{})

      Application.put_env(:fun_sheep, :integrations_provider_modules, %{
        google_classroom: FunSheep.Integrations.Providers.Fake
      })

      Application.put_env(:fun_sheep, :fake_provider, %{
        courses: {:ok, []},
        assignments: %{}
      })

      on_exit(fn ->
        Application.put_env(:fun_sheep, :integrations_provider_modules, original)
        Application.delete_env(:fun_sheep, :fake_provider)
      end)

      conn =
        conn
        |> auth(user_role)
        |> get(~p"/integrations/callback?credential_id=cred_abc&service_id=google_classroom")

      assert redirected_to(conn) == "/integrations"

      connection = Integrations.get_for_user_and_provider(user_role.id, :google_classroom)
      assert connection.credential_id == "cred_abc"
      # The inline Oban mode runs the sync worker during the callback, so the
      # connection will already be :active (Fake provider returned empty).
      assert connection.status in [:syncing, :active]
    end

    test "missing credential_id flashes an error", %{conn: conn} do
      user_role = user_role_fixture()

      conn =
        conn
        |> auth(user_role)
        |> get(~p"/integrations/callback")

      assert redirected_to(conn) == "/integrations"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Missing credential"
    end
  end

  describe "DELETE /integrations/:id" do
    test "revokes and removes the connection", %{conn: conn} do
      user_role = user_role_fixture()

      {:ok, connection} =
        Integrations.create_connection(%{
          user_role_id: user_role.id,
          provider: :google_classroom,
          service_id: "google_classroom",
          external_user_id: user_role.interactor_user_id,
          credential_id: "cred_x",
          status: :active
        })

      conn =
        conn
        |> auth(user_role)
        |> delete(~p"/integrations/#{connection.id}")

      assert redirected_to(conn) == "/integrations"
      assert Integrations.get_connection(connection.id) == nil
    end

    test "forbidden when the connection belongs to another user", %{conn: conn} do
      owner = user_role_fixture()
      other = user_role_fixture()

      {:ok, connection} =
        Integrations.create_connection(%{
          user_role_id: owner.id,
          provider: :canvas,
          service_id: "canvas",
          external_user_id: owner.interactor_user_id,
          credential_id: "cred_y"
        })

      conn =
        conn
        |> auth(other)
        |> delete(~p"/integrations/#{connection.id}")

      assert conn.status == 403
    end
  end

  describe "POST /integrations/:id/sync" do
    test "enqueues a sync", %{conn: conn} do
      user_role = user_role_fixture()

      {:ok, connection} =
        Integrations.create_connection(%{
          user_role_id: user_role.id,
          provider: :google_classroom,
          service_id: "google_classroom",
          external_user_id: user_role.interactor_user_id,
          credential_id: "cred_sync"
        })

      conn =
        conn
        |> auth(user_role)
        |> post(~p"/integrations/#{connection.id}/sync")

      assert redirected_to(conn) == "/integrations"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Sync queued"
    end
  end
end
