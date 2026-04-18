defmodule StudySmart.Geo.School do
  @moduledoc """
  Schema for schools within a district.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "schools" do
    field :name, :string

    belongs_to :district, StudySmart.Geo.District
    has_many :user_roles, StudySmart.Accounts.UserRole
    has_many :courses, StudySmart.Courses.Course
    has_many :questions, StudySmart.Questions.Question

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(school, attrs) do
    school
    |> cast(attrs, [:name, :district_id])
    |> validate_required([:name, :district_id])
    |> foreign_key_constraint(:district_id)
  end
end
