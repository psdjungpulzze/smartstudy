defmodule FunSheep.Repo.Migrations.CreateAdminAuditLogs do
  use Ecto.Migration

  def change do
    create table(:admin_audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Nullable because the actor may be a system process (e.g. a mix task
      # run at bootstrap time, before any admin user exists).
      add :actor_user_role_id,
          references(:user_roles, type: :binary_id, on_delete: :nilify_all)

      add :actor_label, :string, null: false
      add :action, :string, null: false
      add :target_type, :string
      add :target_id, :string
      add :metadata, :map, null: false, default: %{}
      add :ip, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:admin_audit_logs, [:actor_user_role_id])
    create index(:admin_audit_logs, [:action])
    create index(:admin_audit_logs, [:target_type, :target_id])
    create index(:admin_audit_logs, [:inserted_at])
  end
end
