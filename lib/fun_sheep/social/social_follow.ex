defmodule FunSheep.Social.SocialFollow do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "social_follows" do
    belongs_to :follower, FunSheep.Accounts.UserRole, foreign_key: :follower_id
    belongs_to :followee, FunSheep.Accounts.UserRole, foreign_key: :followee_id

    timestamps(type: :utc_datetime)
  end

  def changeset(follow, attrs) do
    follow
    |> cast(attrs, [:follower_id, :followee_id])
    |> validate_required([:follower_id, :followee_id])
    |> validate_not_self_follow()
    |> unique_constraint([:follower_id, :followee_id])
    |> foreign_key_constraint(:follower_id)
    |> foreign_key_constraint(:followee_id)
  end

  defp validate_not_self_follow(changeset) do
    follower_id = get_field(changeset, :follower_id)
    followee_id = get_field(changeset, :followee_id)

    if follower_id && follower_id == followee_id do
      add_error(changeset, :followee_id, "cannot follow yourself")
    else
      changeset
    end
  end
end
