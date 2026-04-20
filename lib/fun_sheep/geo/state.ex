defmodule FunSheep.Geo.State do
  @moduledoc """
  First-order administrative subdivision (state, province, prefecture, do).

  `iso_code` is the ISO 3166-2 subdivision code (e.g. "US-CA", "KR-11",
  "GB-LND") — the natural key used by every ingestion pipeline.
  `subdivision_type` records the local term (State, Province, 특별시, 道).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "states" do
    field :name, :string
    field :native_name, :string
    field :iso_code, :string
    field :fips_code, :string
    field :subdivision_type, :string

    belongs_to :country, FunSheep.Geo.Country
    has_many :districts, FunSheep.Geo.District
    has_many :schools, FunSheep.Geo.School
    has_many :universities, FunSheep.Geo.University

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(state, attrs) do
    state
    |> cast(attrs, [
      :name,
      :native_name,
      :iso_code,
      :fips_code,
      :subdivision_type,
      :country_id
    ])
    |> validate_required([:name, :country_id])
    |> foreign_key_constraint(:country_id)
    |> unique_constraint([:name, :country_id])
    |> unique_constraint(:iso_code)
  end
end
