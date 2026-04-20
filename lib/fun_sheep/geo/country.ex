defmodule FunSheep.Geo.Country do
  @moduledoc """
  Sovereign country in the geographic hierarchy.

  `code` is the ISO 3166-1 alpha-2 (e.g. "US", "KR"). `iso3` is alpha-3
  (e.g. "USA", "KOR"). `numeric_code` is ISO 3166-1 numeric. These codes
  are the natural keys used by every ingestion pipeline — country rows
  are upserted by `code`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "countries" do
    field :name, :string
    field :native_name, :string
    field :code, :string
    field :iso3, :string
    field :numeric_code, :string

    has_many :states, FunSheep.Geo.State
    has_many :districts, FunSheep.Geo.District
    has_many :schools, FunSheep.Geo.School
    has_many :universities, FunSheep.Geo.University

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(country, attrs) do
    country
    |> cast(attrs, [:name, :native_name, :code, :iso3, :numeric_code])
    |> validate_required([:name, :code])
    |> update_change(:code, &String.upcase/1)
    |> unique_constraint(:code)
    |> unique_constraint(:name)
  end
end
