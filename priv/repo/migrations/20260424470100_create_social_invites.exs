defmodule FunSheep.Repo.Migrations.CreateSocialInvites do
  use Ecto.Migration

  def change do
    create table(:social_invites, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :inviter_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :invitee_user_role_id, references(:user_roles, type: :binary_id, on_delete: :nilify_all)
      add :invitee_email, :string
      add :invite_token, :string
      add :invite_token_expires_at, :utc_datetime
      add :status, :string, null: false, default: "pending"
      add :context, :string, null: false, default: "general"
      add :context_id, :binary_id
      add :message, :text
      add :accepted_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:social_invites, [:invite_token], where: "invite_token IS NOT NULL")
    create index(:social_invites, [:inviter_id])
    create index(:social_invites, [:invitee_user_role_id])
    create index(:social_invites, [:status])
  end
end
