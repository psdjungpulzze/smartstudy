defmodule FunSheep.Credits.WoolCredit do
  use Ecto.Schema
  import Ecto.Changeset

  @sources ~w(referral material_upload test_created transfer_in transfer_out redemption admin_grant)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "wool_credits" do
    field :delta, :integer
    field :source, :string
    field :source_ref_id, :binary_id
    field :metadata, :map, default: %{}
    belongs_to :user_role, FunSheep.Accounts.UserRole
    timestamps(updated_at: false)
  end

  def changeset(credit, attrs) do
    credit
    |> cast(attrs, [:user_role_id, :delta, :source, :source_ref_id, :metadata])
    |> validate_required([:user_role_id, :delta, :source])
    |> validate_inclusion(:source, @sources)
    |> validate_number(:delta, not_equal_to: 0)
  end
end
