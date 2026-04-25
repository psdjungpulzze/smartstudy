defmodule FunSheep.Repo.Migrations.CreateSocialFollows do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:social_follows, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :follower_id, references(:user_roles, type: :binary_id, on_delete: :delete_all), null: false
      add :followee_id, references(:user_roles, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists unique_index(:social_follows, [:follower_id, :followee_id])
    create_if_not_exists index(:social_follows, [:follower_id])
    create_if_not_exists index(:social_follows, [:followee_id])

    create_if_not_exists table(:user_blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :blocker_id, references(:user_roles, type: :binary_id, on_delete: :delete_all), null: false
      add :blocked_id, references(:user_roles, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists unique_index(:user_blocks, [:blocker_id, :blocked_id])
    create_if_not_exists index(:user_blocks, [:blocker_id])
  end
end
