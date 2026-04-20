defmodule FunSheep.Geo.School do
  @moduledoc """
  K-12 institution (primary/elementary, middle, secondary/high, combined,
  special, vocational). Higher-ed lives in `FunSheep.Geo.University`.

  Upserts are keyed on `(source, source_id)` for every ingested row. Common
  sources: `"nces_ccd"` (NCESSCH 12-digit), `"gias_uk"` (URN), `"acara_au"`
  (ACARA ID), `"kr_neis"` (학교 행정표준코드), `"ib"` (IB school code).
  `district_id` is nullable — many countries have no district tier and
  international/private schools are commonly independent.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @required_for_ingested ~w(source source_id)a

  schema "schools" do
    field :name, :string
    field :native_name, :string

    # Natural keys — populated by ingesters, used for idempotent upsert
    field :source, :string
    field :source_id, :string
    field :nces_id, :string
    field :urn, :string
    field :acara_id, :string
    field :kr_code, :string
    field :ib_code, :string

    # Classification
    # public | private | charter | magnet | international | special | vocational
    field :type, :string
    # elementary | middle | high | combined | k12 | special | other
    field :level, :string
    field :lowest_grade, :string
    field :highest_grade, :string
    field :operational_status, :string

    # Location / contact
    field :address, :string
    field :city, :string
    field :postal_code, :string
    field :phone, :string
    field :website, :string
    field :lat, :float
    field :lng, :float
    # NCES EDGE: 11-13 (City), 21-23 (Suburb), 31-33 (Town), 41-43 (Rural)
    field :locale_code, :string

    field :student_count, :integer
    field :opened_at, :date
    field :closed_at, :date
    field :metadata, :map, default: %{}

    belongs_to :district, FunSheep.Geo.District
    belongs_to :state, FunSheep.Geo.State
    belongs_to :country, FunSheep.Geo.Country

    has_many :user_roles, FunSheep.Accounts.UserRole
    has_many :courses, FunSheep.Courses.Course
    has_many :questions, FunSheep.Questions.Question

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(school, attrs) do
    school
    |> cast(attrs, [
      :name,
      :native_name,
      :source,
      :source_id,
      :nces_id,
      :urn,
      :acara_id,
      :kr_code,
      :ib_code,
      :type,
      :level,
      :lowest_grade,
      :highest_grade,
      :operational_status,
      :address,
      :city,
      :postal_code,
      :phone,
      :website,
      :lat,
      :lng,
      :locale_code,
      :student_count,
      :opened_at,
      :closed_at,
      :metadata,
      :district_id,
      :state_id,
      :country_id
    ])
    |> validate_required([:name])
    |> maybe_require_source_pair()
    |> validate_parent_present()
    |> foreign_key_constraint(:district_id)
    |> foreign_key_constraint(:state_id)
    |> foreign_key_constraint(:country_id)
    |> unique_constraint([:source, :source_id], name: :schools_source_pid_index)
  end

  defp maybe_require_source_pair(changeset) do
    case {get_field(changeset, :source), get_field(changeset, :source_id)} do
      {nil, nil} -> changeset
      _ -> validate_required(changeset, @required_for_ingested)
    end
  end

  # At least one of district_id, state_id, country_id must be set so every
  # school is locatable in the hierarchy. District-only is the old default;
  # state_id or country_id satisfies independent/international schools.
  defp validate_parent_present(changeset) do
    case {get_field(changeset, :district_id), get_field(changeset, :state_id),
          get_field(changeset, :country_id)} do
      {nil, nil, nil} ->
        add_error(
          changeset,
          :district_id,
          "one of district_id, state_id, or country_id is required"
        )

      _ ->
        changeset
    end
  end
end
