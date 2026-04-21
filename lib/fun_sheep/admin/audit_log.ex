defmodule FunSheep.Admin.AuditLog do
  @moduledoc """
  Append-only log of admin actions. Every mutation performed from an admin
  surface (UI, mix task, API) must write exactly one row here so access is
  auditable. Records are never updated; only inserted.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "admin_audit_logs" do
    field :actor_label, :string
    field :action, :string
    field :target_type, :string
    field :target_id, :string
    field :metadata, :map, default: %{}
    field :ip, :string

    belongs_to :actor, FunSheep.Accounts.UserRole, foreign_key: :actor_user_role_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @required [:actor_label, :action]
  @optional [:actor_user_role_id, :target_type, :target_id, :metadata, :ip]

  def changeset(log, attrs) do
    log
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> foreign_key_constraint(:actor_user_role_id)
  end
end
