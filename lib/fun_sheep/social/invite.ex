defmodule FunSheep.Social.Invite do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending accepted expired declined)
  @contexts ~w(general course test)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "social_invites" do
    field :invitee_email, :string
    field :invite_token, :string
    field :invite_token_expires_at, :utc_datetime
    field :status, :string, default: "pending"
    field :context, :string, default: "general"
    field :context_id, :binary_id
    field :message, :string
    field :accepted_at, :utc_datetime

    belongs_to :inviter, FunSheep.Accounts.UserRole
    belongs_to :invitee_user_role, FunSheep.Accounts.UserRole

    timestamps(updated_at: false)
  end

  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [
      :inviter_id,
      :invitee_user_role_id,
      :invitee_email,
      :invite_token,
      :invite_token_expires_at,
      :status,
      :context,
      :context_id,
      :message,
      :accepted_at
    ])
    |> validate_required([:inviter_id, :context, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:context, @contexts)
    |> validate_at_least_one_invitee()
    |> unique_constraint(:invite_token)
  end

  def accept_changeset(invite, accepted_at \\ DateTime.utc_now()) do
    invite
    |> change(status: "accepted", accepted_at: DateTime.truncate(accepted_at, :second))
  end

  def status_changeset(invite, status) do
    invite |> change(status: status)
  end

  defp validate_at_least_one_invitee(changeset) do
    email = get_field(changeset, :invitee_email)
    user_role_id = get_field(changeset, :invitee_user_role_id)

    if is_nil(email) and is_nil(user_role_id) do
      add_error(changeset, :invitee_email, "either invitee_email or invitee_user_role_id must be set")
    else
      changeset
    end
  end
end
