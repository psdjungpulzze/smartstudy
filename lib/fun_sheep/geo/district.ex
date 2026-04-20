defmodule FunSheep.Geo.District do
  @moduledoc """
  Local education agency (LEA) — aka school district, local authority,
  academy trust, 교육지원청.

  Ingested rows are identified by `(source, source_id)`. Common source
  values: `"nces_ccd"` (LEAID), `"gias_uk"` (local authority code),
  `"kr_neis"` (시도교육청 코드). Legacy seed rows have no source.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @required_for_ingested ~w(source source_id)a

  schema "districts" do
    field :name, :string
    field :native_name, :string

    # Natural keys
    field :source, :string
    field :source_id, :string
    field :nces_leaid, :string

    # Classification
    field :type, :string
    field :operational_status, :string

    # Contact / location
    field :address, :string
    field :city, :string
    field :postal_code, :string
    field :phone, :string
    field :website, :string
    field :lat, :float
    field :lng, :float

    field :metadata, :map, default: %{}

    belongs_to :state, FunSheep.Geo.State
    belongs_to :country, FunSheep.Geo.Country
    has_many :schools, FunSheep.Geo.School

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(district, attrs) do
    district
    |> cast(attrs, [
      :name,
      :native_name,
      :source,
      :source_id,
      :nces_leaid,
      :type,
      :operational_status,
      :address,
      :city,
      :postal_code,
      :phone,
      :website,
      :lat,
      :lng,
      :metadata,
      :state_id,
      :country_id
    ])
    |> validate_required([:name, :state_id])
    |> maybe_require_source_pair()
    |> foreign_key_constraint(:state_id)
    |> foreign_key_constraint(:country_id)
    |> unique_constraint([:source, :source_id], name: :districts_source_pid_index)
    |> unique_constraint([:name, :state_id])
  end

  defp maybe_require_source_pair(changeset) do
    case {get_field(changeset, :source), get_field(changeset, :source_id)} do
      {nil, nil} -> changeset
      _ -> validate_required(changeset, @required_for_ingested)
    end
  end
end
