defmodule FunSheep.Geo.District do
  @moduledoc """
  Schema for districts within a state.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "districts" do
    field :name, :string

    belongs_to :state, FunSheep.Geo.State
    has_many :schools, FunSheep.Geo.School

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(district, attrs) do
    district
    |> cast(attrs, [:name, :state_id])
    |> validate_required([:name, :state_id])
    |> foreign_key_constraint(:state_id)
    |> unique_constraint([:name, :state_id])
  end
end
