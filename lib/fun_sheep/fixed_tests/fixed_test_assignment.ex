defmodule FunSheep.FixedTests.FixedTestAssignment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "fixed_test_assignments" do
    field :due_at, :utc_datetime
    field :note, :string

    belongs_to :bank, FunSheep.FixedTests.FixedTestBank
    belongs_to :assigned_by, FunSheep.Accounts.UserRole
    belongs_to :assigned_to, FunSheep.Accounts.UserRole

    timestamps(type: :utc_datetime)
  end

  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [:bank_id, :assigned_by_id, :assigned_to_id, :due_at, :note])
    |> validate_required([:bank_id, :assigned_by_id, :assigned_to_id])
    |> unique_constraint([:bank_id, :assigned_to_id])
  end
end
