defmodule StudySmart.Geo.State do
  @moduledoc """
  Schema for states/provinces within a country.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "states" do
    field :name, :string

    belongs_to :country, StudySmart.Geo.Country
    has_many :districts, StudySmart.Geo.District

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(state, attrs) do
    state
    |> cast(attrs, [:name, :country_id])
    |> validate_required([:name, :country_id])
    |> foreign_key_constraint(:country_id)
    |> unique_constraint([:name, :country_id])
  end
end
