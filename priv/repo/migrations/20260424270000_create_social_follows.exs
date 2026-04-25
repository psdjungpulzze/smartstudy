defmodule FunSheep.Repo.Migrations.CreateSocialFollows do
  use Ecto.Migration

  def change do
    create table(:social_follows, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :follower_id, references(:user_roles, type: :binary_id, on_delete: :delete_all), null: false
      add :following_id, references(:user_roles, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "active"
      add :source, :string, null: false, default: "manual"

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:social_follows, [:follower_id, :following_id])
    create index(:social_follows, [:follower_id])
    create index(:social_follows, [:following_id])

    create constraint(:social_follows, :no_self_follow,
      check: "follower_id != following_id"
    )
  end
end
