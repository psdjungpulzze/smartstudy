defmodule FunSheep.Geo.University do
  @moduledoc """
  Higher-education institution (college, university, polytechnic, 대학교).

  Ingested from IPEDS (US UNITID), College Scorecard (OPEID), WHED (global
  id), and ROR (research org registry). Upserts are keyed on
  `(source, source_id)`.

  Intentionally separate from `FunSheep.Geo.School` because postsecondary
  registries use different PIDs, classifications (Carnegie, control,
  level), and student-facing UX needs.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "universities" do
    field :name, :string
    field :native_name, :string

    # Natural keys
    field :source, :string
    field :source_id, :string
    field :ipeds_unitid, :string
    field :whed_id, :string
    field :opeid, :string
    field :ror_id, :string

    # Classification
    field :control, :string
    field :level, :string
    field :type, :string
    field :operational_status, :string

    # Location / contact
    field :address, :string
    field :city, :string
    field :postal_code, :string
    field :phone, :string
    field :website, :string
    field :lat, :float
    field :lng, :float

    field :student_count, :integer
    field :metadata, :map, default: %{}

    belongs_to :country, FunSheep.Geo.Country
    belongs_to :state, FunSheep.Geo.State

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(university, attrs) do
    university
    |> cast(attrs, [
      :name,
      :native_name,
      :source,
      :source_id,
      :ipeds_unitid,
      :whed_id,
      :opeid,
      :ror_id,
      :control,
      :level,
      :type,
      :operational_status,
      :address,
      :city,
      :postal_code,
      :phone,
      :website,
      :lat,
      :lng,
      :student_count,
      :metadata,
      :country_id,
      :state_id
    ])
    |> validate_required([:name, :source, :source_id, :country_id])
    |> foreign_key_constraint(:country_id)
    |> foreign_key_constraint(:state_id)
    |> unique_constraint([:source, :source_id], name: :universities_source_pid_index)
  end
end
