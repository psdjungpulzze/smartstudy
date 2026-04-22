defmodule FunSheep.IntegrationsTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Integrations
  alias FunSheep.Integrations.IntegrationConnection

  setup do
    {:ok, user_role} =
      FunSheep.Accounts.create_user_role(%{
        interactor_user_id: "interactor_#{System.unique_integer([:positive])}",
        role: :student,
        email: "integrations_#{System.unique_integer([:positive])}@test.example",
        display_name: "Test Student"
      })

    %{user_role: user_role}
  end

  describe "create_connection/1" do
    test "persists a connection for a valid payload", %{user_role: user_role} do
      assert {:ok, %IntegrationConnection{} = conn} =
               Integrations.create_connection(%{
                 user_role_id: user_role.id,
                 provider: :google_classroom,
                 service_id: "google_classroom",
                 external_user_id: user_role.interactor_user_id,
                 credential_id: "cred_123"
               })

      assert conn.provider == :google_classroom
      assert conn.status == :pending
    end

    test "rejects duplicate (user_role, provider)", %{user_role: user_role} do
      attrs = %{
        user_role_id: user_role.id,
        provider: :canvas,
        service_id: "canvas",
        external_user_id: user_role.interactor_user_id
      }

      assert {:ok, _} = Integrations.create_connection(attrs)
      assert {:error, changeset} = Integrations.create_connection(attrs)

      assert %{user_role_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "requires user_role_id, provider, service_id, external_user_id" do
      assert {:error, changeset} = Integrations.create_connection(%{})

      errors = errors_on(changeset)
      assert "can't be blank" in errors.user_role_id
      assert "can't be blank" in errors.provider
      assert "can't be blank" in errors.service_id
      assert "can't be blank" in errors.external_user_id
    end
  end

  describe "upsert_connection/1" do
    test "creates the first time, updates the second", %{user_role: user_role} do
      attrs = %{
        user_role_id: user_role.id,
        provider: :google_classroom,
        service_id: "google_classroom",
        external_user_id: user_role.interactor_user_id,
        credential_id: "cred_first"
      }

      assert {:ok, conn1} = Integrations.upsert_connection(attrs)
      assert conn1.credential_id == "cred_first"

      updated_attrs = Map.put(attrs, :credential_id, "cred_second")
      assert {:ok, conn2} = Integrations.upsert_connection(updated_attrs)

      assert conn2.id == conn1.id
      assert conn2.credential_id == "cred_second"
    end
  end

  describe "status helpers" do
    test "mark_status / mark_synced / mark_errored", %{user_role: user_role} do
      {:ok, connection} =
        Integrations.create_connection(%{
          user_role_id: user_role.id,
          provider: :canvas,
          service_id: "canvas",
          external_user_id: user_role.interactor_user_id
        })

      {:ok, syncing} = Integrations.mark_status(connection, :syncing)
      assert syncing.status == :syncing

      {:ok, synced} = Integrations.mark_synced(syncing)
      assert synced.status == :active
      assert synced.last_sync_at
      assert synced.last_sync_error == nil

      {:ok, errored} = Integrations.mark_errored(synced, "upstream 500")
      assert errored.status == :error
      assert errored.last_sync_error == "upstream 500"
    end
  end

  describe "lookups" do
    test "get_by_credential_id / get_for_user_and_provider / list_for_user",
         %{user_role: user_role} do
      {:ok, gc} =
        Integrations.create_connection(%{
          user_role_id: user_role.id,
          provider: :google_classroom,
          service_id: "google_classroom",
          external_user_id: user_role.interactor_user_id,
          credential_id: "cred_gc"
        })

      {:ok, canvas} =
        Integrations.create_connection(%{
          user_role_id: user_role.id,
          provider: :canvas,
          service_id: "canvas",
          external_user_id: user_role.interactor_user_id,
          credential_id: "cred_canvas"
        })

      assert Integrations.get_by_credential_id("cred_gc").id == gc.id
      assert Integrations.get_by_credential_id("nope") == nil

      assert Integrations.get_for_user_and_provider(user_role.id, :canvas).id == canvas.id
      assert Integrations.get_for_user_and_provider(user_role.id, :parentsquare) == nil

      ids =
        user_role.id
        |> Integrations.list_for_user()
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert ids == Enum.sort([gc.id, canvas.id])
      assert Integrations.list_for_user(nil) == []
    end
  end

  describe "pubsub" do
    test "broadcast emits :integration_event on the user-role topic", %{user_role: user_role} do
      {:ok, connection} =
        Integrations.create_connection(%{
          user_role_id: user_role.id,
          provider: :google_classroom,
          service_id: "google_classroom",
          external_user_id: user_role.interactor_user_id
        })

      :ok = Integrations.subscribe(user_role.id)
      :ok = Integrations.broadcast(connection, :synced, %{courses: 1})

      assert_receive {:integration_event, :synced, payload}
      assert payload.connection_id == connection.id
      assert payload.courses == 1
    end
  end
end
