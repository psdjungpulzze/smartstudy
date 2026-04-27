defmodule FunSheep.Repo.Migrations.AlterSocialFollowsRenameFolloweeAddStatusSource do
  use Ecto.Migration

  def up do
    # Rename followee_id → following_id
    execute "ALTER TABLE social_follows RENAME COLUMN followee_id TO following_id"

    # Add status and source columns
    alter table(:social_follows) do
      add :status, :string, null: false, default: "active"
      add :source, :string, null: false, default: "manual"
    end

    # Drop the old unique index on (follower_id, followee_id)
    drop_if_exists unique_index(:social_follows, [:follower_id, :followee_id],
                     name: :social_follows_follower_id_followee_id_index
                   )

    # Create new unique index on (follower_id, following_id)
    create unique_index(:social_follows, [:follower_id, :following_id])

    # Drop old index on followee_id if it exists
    drop_if_exists index(:social_follows, [:followee_id], name: :social_follows_followee_id_index)

    # Create index on following_id
    create_if_not_exists index(:social_follows, [:following_id])

    # Add check constraint to prevent self-follows
    create constraint(:social_follows, :no_self_follow, check: "follower_id != following_id")
  end

  def down do
    drop constraint(:social_follows, :no_self_follow)

    drop_if_exists index(:social_follows, [:following_id])

    create_if_not_exists index(:social_follows, [:followee_id])

    drop_if_exists unique_index(:social_follows, [:follower_id, :following_id])

    create unique_index(:social_follows, [:follower_id, :followee_id])

    alter table(:social_follows) do
      remove :status
      remove :source
    end

    execute "ALTER TABLE social_follows RENAME COLUMN following_id TO followee_id"
  end
end
