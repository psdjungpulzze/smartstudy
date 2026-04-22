defmodule FunSheep.Integrations do
  @moduledoc """
  Context for external LMS/school-app integrations.

  Owns `IntegrationConnection` records (the FunSheep-side bookkeeping
  that pairs a user-role with an Interactor credential) and dispatches
  provider-specific sync work via `FunSheep.Workers.IntegrationSyncWorker`.

  This context never stores provider access/refresh tokens — those live
  in Interactor Credential Management and are fetched on-demand by the
  sync worker.
  """

  import Ecto.Query, warn: false

  alias FunSheep.Repo
  alias FunSheep.Integrations.IntegrationConnection

  @type status :: :pending | :active | :syncing | :error | :expired | :revoked

  ## CRUD

  @doc "Returns the connection by id or `nil`."
  @spec get_connection(Ecto.UUID.t()) :: IntegrationConnection.t() | nil
  def get_connection(id), do: Repo.get(IntegrationConnection, id)

  @doc "Raises if the connection is missing."
  @spec get_connection!(Ecto.UUID.t()) :: IntegrationConnection.t()
  def get_connection!(id), do: Repo.get!(IntegrationConnection, id)

  @doc "Looks up a connection by its Interactor credential id."
  @spec get_by_credential_id(String.t()) :: IntegrationConnection.t() | nil
  def get_by_credential_id(credential_id) when is_binary(credential_id) do
    Repo.get_by(IntegrationConnection, credential_id: credential_id)
  end

  @doc "Lists every connection for a user-role, ordered by provider."
  @spec list_for_user(Ecto.UUID.t() | nil) :: [IntegrationConnection.t()]
  def list_for_user(nil), do: []

  def list_for_user(user_role_id) do
    from(ic in IntegrationConnection,
      where: ic.user_role_id == ^user_role_id,
      order_by: [asc: ic.provider]
    )
    |> Repo.all()
  end

  @doc "Fetches a user-role's connection for a specific provider, or nil."
  @spec get_for_user_and_provider(Ecto.UUID.t(), atom()) :: IntegrationConnection.t() | nil
  def get_for_user_and_provider(user_role_id, provider) when is_atom(provider) do
    Repo.get_by(IntegrationConnection, user_role_id: user_role_id, provider: provider)
  end

  @doc """
  Inserts a new connection, or returns `{:error, :already_exists}` if
  the user-role already has one for this provider.
  """
  @spec create_connection(map()) ::
          {:ok, IntegrationConnection.t()} | {:error, Ecto.Changeset.t()}
  def create_connection(attrs) do
    %IntegrationConnection{}
    |> IntegrationConnection.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Upsert: if a connection already exists for the (user_role, provider)
  pair, update its credential_id/status/metadata; otherwise create it.
  Used by the OAuth callback flow.
  """
  @spec upsert_connection(map()) ::
          {:ok, IntegrationConnection.t()} | {:error, Ecto.Changeset.t()}
  def upsert_connection(%{user_role_id: user_role_id, provider: provider} = attrs) do
    case get_for_user_and_provider(user_role_id, provider) do
      nil ->
        create_connection(attrs)

      existing ->
        existing
        |> IntegrationConnection.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc "Updates a connection with arbitrary attrs."
  @spec update_connection(IntegrationConnection.t(), map()) ::
          {:ok, IntegrationConnection.t()} | {:error, Ecto.Changeset.t()}
  def update_connection(%IntegrationConnection{} = connection, attrs) do
    connection
    |> IntegrationConnection.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a connection record."
  @spec delete_connection(IntegrationConnection.t()) ::
          {:ok, IntegrationConnection.t()} | {:error, Ecto.Changeset.t()}
  def delete_connection(%IntegrationConnection{} = connection) do
    Repo.delete(connection)
  end

  ## Status helpers — the sync worker and webhooks use these

  @doc "Sets `:status` (and clears or keeps error depending on status)."
  @spec mark_status(IntegrationConnection.t(), status()) ::
          {:ok, IntegrationConnection.t()} | {:error, Ecto.Changeset.t()}
  def mark_status(%IntegrationConnection{} = connection, status)
      when status in [:pending, :active, :syncing, :error, :expired, :revoked] do
    update_connection(connection, %{status: status})
  end

  @doc "Marks a sync as successful and stamps `last_sync_at`."
  @spec mark_synced(IntegrationConnection.t()) ::
          {:ok, IntegrationConnection.t()} | {:error, Ecto.Changeset.t()}
  def mark_synced(%IntegrationConnection{} = connection) do
    update_connection(connection, %{
      status: :active,
      last_sync_at: DateTime.utc_now() |> DateTime.truncate(:second),
      last_sync_error: nil
    })
  end

  @doc "Marks a sync as failed with an error message."
  @spec mark_errored(IntegrationConnection.t(), String.t()) ::
          {:ok, IntegrationConnection.t()} | {:error, Ecto.Changeset.t()}
  def mark_errored(%IntegrationConnection{} = connection, reason) when is_binary(reason) do
    update_connection(connection, %{status: :error, last_sync_error: reason})
  end

  @doc """
  Enqueues `FunSheep.Workers.IntegrationSyncWorker` for the given connection.
  """
  @spec enqueue_sync(IntegrationConnection.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_sync(%IntegrationConnection{id: id}) do
    %{"connection_id" => id}
    |> FunSheep.Workers.IntegrationSyncWorker.new()
    |> Oban.insert()
  end

  ## PubSub

  @pubsub FunSheep.PubSub

  @doc "Topic for per-user-role integration broadcasts."
  @spec topic(Ecto.UUID.t()) :: String.t()
  def topic(user_role_id), do: "integrations:#{user_role_id}"

  @doc "Subscribe the calling process to the given user-role's integration events."
  @spec subscribe(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe(user_role_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(user_role_id))
  end

  @doc "Broadcast an event about a connection to subscribers."
  @spec broadcast(IntegrationConnection.t(), atom(), map()) :: :ok | {:error, term()}
  def broadcast(%IntegrationConnection{user_role_id: user_role_id, id: id}, event, payload \\ %{}) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      topic(user_role_id),
      {:integration_event, event, Map.put(payload, :connection_id, id)}
    )
  end
end
