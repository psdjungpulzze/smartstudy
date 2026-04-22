defmodule FunSheep.Integrations.IntegrationConnection do
  @moduledoc """
  Schema representing a user's connection to an external LMS/school app
  (Google Classroom, Canvas LMS, ParentSquare).

  Only stores the Interactor `credential_id` — provider access/refresh
  tokens live in Interactor Credential Management and are re-fetched on
  each sync via `/api/v1/credentials/{id}/token`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @providers [:google_classroom, :canvas, :parentsquare]
  @statuses [:pending, :active, :syncing, :error, :expired, :revoked]

  schema "integration_connections" do
    field :provider, Ecto.Enum, values: @providers
    field :service_id, :string
    field :credential_id, :string
    field :external_user_id, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :last_sync_at, :utc_datetime
    field :last_sync_error, :string
    field :metadata, :map, default: %{}

    belongs_to :user_role, FunSheep.Accounts.UserRole

    timestamps(type: :utc_datetime)
  end

  @doc "All supported provider atoms."
  @spec providers() :: [atom()]
  def providers, do: @providers

  @doc "All supported status atoms."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  @doc false
  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :provider,
      :service_id,
      :credential_id,
      :external_user_id,
      :status,
      :last_sync_at,
      :last_sync_error,
      :metadata,
      :user_role_id
    ])
    |> validate_required([:provider, :service_id, :external_user_id, :user_role_id])
    |> unique_constraint([:user_role_id, :provider])
    |> foreign_key_constraint(:user_role_id)
  end
end
