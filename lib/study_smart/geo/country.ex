defmodule StudySmart.Geo.Country do
  @moduledoc """
  Schema for countries in the geographic hierarchy.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "countries" do
    field :name, :string
    field :code, :string

    has_many :states, StudySmart.Geo.State

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(country, attrs) do
    country
    |> cast(attrs, [:name, :code])
    |> validate_required([:name, :code])
    |> unique_constraint(:code)
    |> unique_constraint(:name)
  end
end
