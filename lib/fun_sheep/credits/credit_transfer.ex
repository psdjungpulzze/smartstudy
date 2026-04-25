defmodule FunSheep.Credits.CreditTransfer do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "credit_transfers" do
    field :amount_quarter_units, :integer
    field :note, :string
    belongs_to :from_user_role, FunSheep.Accounts.UserRole
    belongs_to :to_user_role, FunSheep.Accounts.UserRole
    timestamps(updated_at: false)
  end

  def changeset(transfer, attrs) do
    transfer
    |> cast(attrs, [:from_user_role_id, :to_user_role_id, :amount_quarter_units, :note])
    |> validate_required([:from_user_role_id, :to_user_role_id, :amount_quarter_units])
    |> validate_number(:amount_quarter_units, greater_than: 0)
  end
end
