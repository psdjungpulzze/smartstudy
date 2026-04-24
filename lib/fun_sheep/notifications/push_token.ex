defmodule FunSheep.Notifications.PushToken do
  @moduledoc """
  Stores a device or browser push token for a user.

  One user can have multiple tokens (phone + tablet + web browser).
  Tokens are deactivated rather than deleted when a device is removed so
  the history is preserved for debugging.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @platforms ~w(ios android web)a

  schema "push_tokens" do
    field :token, :string
    field :platform, Ecto.Enum, values: @platforms
    field :active, :boolean, default: true

    belongs_to :user_role, FunSheep.Accounts.UserRole

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(push_token, attrs) do
    push_token
    |> cast(attrs, [:user_role_id, :token, :platform, :active])
    |> validate_required([:user_role_id, :token, :platform])
    |> unique_constraint([:user_role_id, :token])
    |> foreign_key_constraint(:user_role_id)
  end
end
