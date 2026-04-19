defmodule FunSheep.Billing.TestUsage do
  @moduledoc """
  Tracks individual test completions for billing/usage enforcement.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "test_usages" do
    field :test_type, :string

    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :course, FunSheep.Courses.Course

    timestamps(type: :utc_datetime)
  end

  def changeset(test_usage, attrs) do
    test_usage
    |> cast(attrs, [:user_role_id, :test_type, :course_id])
    |> validate_required([:user_role_id, :test_type])
    |> validate_inclusion(:test_type, ~w(quick_test assessment format_test))
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:course_id)
  end
end
