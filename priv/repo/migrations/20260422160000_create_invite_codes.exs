defmodule FunSheep.Repo.Migrations.CreateInviteCodes do
  use Ecto.Migration

  def change do
    create table(:invite_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, null: false

      add :guardian_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :relationship_type, :string, null: false
      add :child_display_name, :string, null: false
      add :child_grade, :string
      add :child_email, :string

      add :redeemed_by_user_role_id,
          references(:user_roles, type: :binary_id, on_delete: :nilify_all)

      add :redeemed_at, :utc_datetime
      add :expires_at, :utc_datetime, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:invite_codes, [:code])
    create index(:invite_codes, [:guardian_id])
    create index(:invite_codes, [:expires_at])
  end
end
