defmodule FunSheep.Social.UserBlock do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_blocks" do
    belongs_to :blocker, FunSheep.Accounts.UserRole, foreign_key: :blocker_id
    belongs_to :blocked, FunSheep.Accounts.UserRole, foreign_key: :blocked_id

    timestamps(type: :utc_datetime)
  end

  def changeset(block, attrs) do
    block
    |> cast(attrs, [:blocker_id, :blocked_id])
    |> validate_required([:blocker_id, :blocked_id])
    |> unique_constraint([:blocker_id, :blocked_id])
    |> foreign_key_constraint(:blocker_id)
    |> foreign_key_constraint(:blocked_id)
  end
end
