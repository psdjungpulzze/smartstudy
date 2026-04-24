defmodule FunSheep.Social.Block do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_blocks" do
    belongs_to :blocker, FunSheep.Accounts.UserRole
    belongs_to :blocked, FunSheep.Accounts.UserRole

    timestamps(updated_at: false)
  end

  def changeset(block, attrs) do
    block
    |> cast(attrs, [:blocker_id, :blocked_id])
    |> validate_required([:blocker_id, :blocked_id])
    |> unique_constraint([:blocker_id, :blocked_id])
    |> check_constraint(:blocker_id, name: :no_self_block)
  end
end
